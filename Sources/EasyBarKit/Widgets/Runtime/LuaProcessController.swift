import EasyBarShared
import Foundation

/// Owns Lua process lifecycle.
final class LuaProcessController: @unchecked Sendable {
  /// Captures the inputs needed to launch the Lua runtime agent.
  struct LaunchContext: Sendable {
    let runtimeAgentPath: String
    let runtimePath: String
    let luaPath: String
    let luaSocketPath: String
    let transportAuthenticationToken: String
    let widgetsPath: String
    let defaultCommandTimeoutSeconds: TimeInterval
    let defaultCommandMaxOutputBytes: Int
    let environment: [String: String]
  }

  /// Captures local resources kept by the host while the runtime agent is running.
  struct LaunchResources: @unchecked Sendable {
    let error = Pipe()
  }

  /// Describes one observed Lua child-process termination.
  struct Termination: Equatable, Sendable {
    typealias Reason = ProcessTerminationStatus

    let processIdentifier: Int32
    let reason: Reason
    let wasRequested: Bool
  }

  typealias TerminationHandler = @Sendable (Termination) -> Void

  /// One atomic lifecycle state for start, shutdown, and termination races.
  enum Lifecycle {
    case stopped
    case starting(shutdownRequested: Bool)
    case running(
      processIdentifier: Int32,
      processGroupIdentifier: Int32,
      shuttingDown: Bool
    )
  }

  /// All mutable process ownership protected by one lock.
  struct State {
    var lifecycle: Lifecycle = .stopped
    var terminationTask: Task<Void, Never>?
    var forcedKillTask: Task<Void, Never>?
    var shutdownWaiters: [CheckedContinuation<Void, Never>] = []
    var terminationHandler: TerminationHandler?
  }

  enum ShutdownSnapshot {
    case none
    case starting(wasAlreadyShuttingDown: Bool)
    case running(
      processIdentifier: Int32,
      processGroupIdentifier: Int32,
      wasAlreadyShuttingDown: Bool
    )
  }

  let logger: ProcessLogger
  let state = LockedState(State())

  /// Creates one Lua process controller.
  init(logger: ProcessLogger) {
    self.logger = logger
  }

  /// Returns the running Lua process identifier when available.
  var processIdentifier: Int32? {
    state.withLock { state in
      guard case .running(let processIdentifier, _, _) = state.lifecycle else {
        return nil
      }
      return processIdentifier
    }
  }

  /// Starts the Lua runtime process using the prepared launch context.
  func start(
    context: LaunchContext,
    resources: LaunchResources,
    terminationHandler: @escaping TerminationHandler
  ) -> (processIdentifier: Int32, error: Pipe)? {
    guard reserveStart() else { return nil }
    logLaunch(context: context)

    do {
      let pid = try spawnProcess(context: context, resources: resources)
      cancelForcedKillWorkItem()

      let shutdownWasRequested = state.withLock { state -> Bool in
        guard case .starting(let shutdownRequested) = state.lifecycle else {
          return true
        }

        state.lifecycle = .running(
          processIdentifier: pid,
          processGroupIdentifier: pid,
          shuttingDown: shutdownRequested
        )
        state.terminationHandler = terminationHandler
        return shutdownRequested
      }

      installTerminationSource(for: pid)

      logger.debug(
        "lua runtime started",
        .field("pid", pid),
        .field("pgid", pid)
      )

      if shutdownWasRequested {
        terminateProcess(processIdentifier: pid, processGroupIdentifier: pid)
      }

      return (pid, resources.error)
    } catch {
      closeLaunchResourcesAfterFailedSpawn(resources)
      finishFailedStart()
      logger.error(
        "failed to start lua runtime",
        .field("error", "\(error)")
      )
      return nil
    }
  }

  /// Terminates a running process without marking its exit as requested.
  @discardableResult
  func terminateForRecovery() -> Bool {
    let process = state.withLock { state -> (Int32, Int32)? in
      guard
        case .running(let processIdentifier, let processGroupIdentifier, false) =
          state.lifecycle
      else {
        return nil
      }
      return (processIdentifier, processGroupIdentifier)
    }

    guard let process else { return false }
    terminateProcess(
      processIdentifier: process.0,
      processGroupIdentifier: process.1
    )
    return true
  }

  /// Stops the Lua runtime process and waits until startup or child exit has completed.
  func shutdownAndWait() async {
    switch beginShutdownSnapshot() {
    case .none:
      logger.debug("lua runtime shutdown skipped because no process is running")
      return

    case .starting(let wasAlreadyShuttingDown):
      if wasAlreadyShuttingDown {
        logger.debug("lua runtime shutdown already requested during startup")
      } else {
        logger.debug("lua runtime shutdown requested during startup")
      }
      await waitForShutdownCompletion()

    case .running(
      let processIdentifier,
      let processGroupIdentifier,
      let wasAlreadyShuttingDown
    ):
      if wasAlreadyShuttingDown {
        logger.debug(
          "lua runtime shutdown already in progress",
          .field("pid", processIdentifier)
        )
        await waitForShutdownCompletion()
        return
      }

      logger.debug(
        "shutting down lua runtime",
        .field("pid", processIdentifier),
        .field("pgid", processGroupIdentifier)
      )
      terminateProcess(
        processIdentifier: processIdentifier,
        processGroupIdentifier: processGroupIdentifier
      )
      await waitForShutdownCompletion()
    }
  }

  /// Clears the tracked Lua process and returns its termination delivery state.
  func clearTrackedProcessIfMatching(pid: Int32) -> (
    wasRequested: Bool,
    handler: TerminationHandler?
  )? {
    let clearedState = state.withLock {
      state -> (
        wasRequested: Bool,
        forcedKillTask: Task<Void, Never>?,
        waiters: [CheckedContinuation<Void, Never>],
        handler: TerminationHandler?
      )? in
      guard case .running(let processIdentifier, _, let shuttingDown) = state.lifecycle,
        processIdentifier == pid
      else {
        return nil
      }

      let result = (
        wasRequested: shuttingDown,
        forcedKillTask: state.forcedKillTask,
        waiters: state.shutdownWaiters,
        handler: state.terminationHandler
      )

      state.lifecycle = .stopped
      state.terminationTask = nil
      state.forcedKillTask = nil
      state.shutdownWaiters.removeAll()
      state.terminationHandler = nil
      return result
    }

    guard let clearedState else { return nil }
    clearedState.forcedKillTask?.cancel()
    resumeShutdownWaiters(clearedState.waiters)
    return (clearedState.wasRequested, clearedState.handler)
  }

  /// Atomically reserves the only allowed in-flight start operation.
  private func reserveStart() -> Bool {
    let result = state.withLock { state -> (reserved: Bool, message: String?) in
      switch state.lifecycle {
      case .stopped:
        state.lifecycle = .starting(shutdownRequested: false)
        return (true, nil)
      case .starting:
        return (false, "lua runtime start already in progress")
      case .running(_, _, let shuttingDown):
        return (
          false,
          shuttingDown
            ? "lua runtime start skipped because shutdown is in progress"
            : "lua runtime already started"
        )
      }
    }

    if let message = result.message {
      logger.debug(message)
    }
    return result.reserved
  }

  /// Rolls a failed start reservation back and wakes shutdown callers.
  private func finishFailedStart() {
    let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      guard case .starting = state.lifecycle else { return [] }
      state.lifecycle = .stopped
      let waiters = state.shutdownWaiters
      state.shutdownWaiters.removeAll()
      state.terminationHandler = nil
      return waiters
    }
    resumeShutdownWaiters(waiters)
  }

  /// Suspends until the current start or shutdown sequence has completed.
  private func waitForShutdownCompletion() async {
    let alreadyStopped = state.withLock { state -> Bool in
      if case .stopped = state.lifecycle {
        return true
      }
      return false
    }
    if alreadyStopped { return }

    await withCheckedContinuation { continuation in
      let shouldResumeImmediately = state.withLock { state -> Bool in
        if case .stopped = state.lifecycle {
          return true
        }
        state.shutdownWaiters.append(continuation)
        return false
      }

      if shouldResumeImmediately {
        continuation.resume()
      }
    }
  }

  /// Resumes all pending shutdown waiters.
  private func resumeShutdownWaiters(_ waiters: [CheckedContinuation<Void, Never>]) {
    for waiter in waiters {
      waiter.resume()
    }
  }

  /// Atomically requests shutdown and snapshots a running process when available.
  private func beginShutdownSnapshot() -> ShutdownSnapshot {
    state.withLock { state in
      switch state.lifecycle {
      case .stopped:
        return .none

      case .starting(let shutdownRequested):
        state.lifecycle = .starting(shutdownRequested: true)
        return .starting(wasAlreadyShuttingDown: shutdownRequested)

      case .running(
        let processIdentifier,
        let processGroupIdentifier,
        let shuttingDown
      ):
        state.lifecycle = .running(
          processIdentifier: processIdentifier,
          processGroupIdentifier: processGroupIdentifier,
          shuttingDown: true
        )
        return .running(
          processIdentifier: processIdentifier,
          processGroupIdentifier: processGroupIdentifier,
          wasAlreadyShuttingDown: shuttingDown
        )
      }
    }
  }
}
