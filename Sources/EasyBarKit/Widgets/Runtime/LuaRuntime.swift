import EasyBarShared
import Foundation

/// Actor-owned facade for the Lua runtime used by scripted widgets.
actor LuaRuntime {
  private let logger: ProcessLogger
  private let processController: LuaProcessController
  private let transport: LuaTransport
  private let metricsCoordinator: MetricsCoordinator

  private var lineHandler: (@Sendable (String) -> Void)?
  private var terminationHandler: LuaProcessController.TerminationHandler?
  private var runtimeGeneration: UInt64 = 0

  /// Creates one Lua runtime.
  init(logger: ProcessLogger, metricsCoordinator: MetricsCoordinator = .shared) {
    self.logger = logger
    self.metricsCoordinator = metricsCoordinator
    self.processController = LuaProcessController(logger: logger.child("process"))
    self.transport = LuaTransport(
      logger: logger.child("transport"),
      metricsCoordinator: metricsCoordinator
    )
  }

  /// Returns the running Lua process identifier when available.
  var processIdentifier: Int32? {
    return processController.processIdentifier
  }

  /// Sets the current transport line handler for the Lua runtime.
  func setLineHandler(_ handler: @escaping @Sendable (String) -> Void) {
    lineHandler = handler
  }

  /// Sets the current child-process termination handler.
  func setTerminationHandler(
    _ handler: @escaping LuaProcessController.TerminationHandler
  ) {
    terminationHandler = handler
  }

  /// Starts the Lua runtime if it is not already running.
  @discardableResult
  func start(config: ConfigSnapshot) async -> Bool {
    if let processIdentifier = processController.processIdentifier {
      logger.debug(
        "lua runtime start skipped because it is already running",
        .field("pid", processIdentifier)
      )
      return true
    }

    guard let context = processController.launchContext(config: config) else { return false }

    let resources = LuaProcessController.LaunchResources()
    runtimeGeneration &+= 1
    let generation = runtimeGeneration

    do {
      try transport.startListening(
        socketPath: context.luaSocketPath,
        authenticationToken: context.transportAuthenticationToken,
        error: resources.error,
        lineHandler: lineHandler ?? { _ in }
      )
    } catch {
      logger.error("failed to start lua transport", .field("error", "\(error)"))
      return false
    }

    guard
      let result = processController.start(
        context: context,
        resources: resources,
        terminationHandler: { [weak self] termination in
          Task {
            await self?.handleProcessTermination(
              termination,
              generation: generation
            )
          }
        }
      )
    else {
      transport.shutdown()
      return false
    }

    await metricsCoordinator.recordLuaRuntimeStarted(pid: result.processIdentifier)
    logger.debug(
      "lua runtime facade started",
      .field("pid", result.processIdentifier),
    )
    return true
  }

  /// Stops the Lua runtime and clears all pipe handlers.
  func shutdown() async {
    let hadRunningProcess = processController.processIdentifier != nil

    transport.shutdown()
    await processController.shutdownAndWait()

    if hadRunningProcess {
      await metricsCoordinator.recordLuaRuntimeStopped()
    }

    runtimeGeneration &+= 1
    logger.debug("lua runtime facade shutdown completed")
  }

  /// Handles one child-process exit after the controller has reaped it.
  private func handleProcessTermination(
    _ termination: LuaProcessController.Termination,
    generation: UInt64
  ) async {
    guard runtimeGeneration == generation else { return }
    guard !termination.wasRequested else { return }

    transport.shutdown()
    await metricsCoordinator.recordLuaRuntimeStopped()
    terminationHandler?(termination)
  }

  /// Terminates the current child as an unexpected failure so supervision restarts it.
  func terminateForRecovery(reason: String) {
    logger.error("terminating lua runtime for recovery", .field("reason", reason))
    if !processController.terminateForRecovery() {
      logger.debug("lua runtime recovery termination skipped because no process is running")
    }
  }

  /// Sends one encoded event line to the Lua runtime socket transport.
  func send(_ string: String) {
    transport.send(string)
  }
}
