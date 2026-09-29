import Foundation

/// Schedules one retry action at a time using capped incremental delays.
///
/// Sendability is guarded by `LockedState`; pending task ownership and attempt
/// counters are only read or changed while holding the lock.
public final class BackoffScheduler: @unchecked Sendable {
  /// Stores state data.
  private struct State {
    /// The scheduled task for this state.
    var scheduledTask: Task<Void, Never>?
    /// The stable identifier for this state.
    var scheduledID: UInt64?
    /// The stable identifier for this state.
    var nextScheduledID: UInt64 = 1
    /// The attempt index for this state.
    var attemptIndex = 0
  }

  private let label: String
  private let delays: [TimeInterval]
  private let logger: ProcessLogger
  private let logLevel: ProcessLogLevel
  private let sleeper: any AsyncSleeper
  private let state = LockedState(State())

  /// Creates one capped backoff scheduler.
  public init(
    label: String,
    delays: [TimeInterval],
    logger: ProcessLogger,
    logLevel: ProcessLogLevel = .warn,
    sleeper: any AsyncSleeper = TaskSleeper()
  ) {
    self.label = label
    self.delays = delays
    self.logger = logger
    self.logLevel = logLevel
    self.sleeper = sleeper
  }

  /// Schedules the next backoff attempt when none is currently pending.
  public func schedule(_ action: @escaping @Sendable () -> Void) {
    schedule(after: nil, action)
  }

  /// Schedules one retry using an explicit delay without advancing the backoff sequence.
  public func schedule(after delayOverride: TimeInterval?, _ action: @escaping @Sendable () -> Void) {
    let scheduled = state.withLock { state -> (id: UInt64, delay: TimeInterval)? in
      guard state.scheduledID == nil else {
        return nil
      }

      let scheduledID = state.nextScheduledID
      state.nextScheduledID += 1
      state.scheduledID = scheduledID

      if let delayOverride {
        return (scheduledID, delayOverride)
      }

      let delay = delayForAttempt(state.attemptIndex)
      state.attemptIndex += 1
      return (scheduledID, delay)
    }

    guard let scheduled else { return }

    logScheduled(delay: scheduled.delay)

    let nanoseconds = clampedSleepNanoseconds(from: scheduled.delay)
    let sleeper = sleeper
    let scheduledID = scheduled.id
    let task = Task { [weak self] in
      do {
        try await sleeper.sleep(nanoseconds: nanoseconds)
      } catch {
        guard let self else { return }
        _ = self.clearScheduledTask(id: scheduledID)
        return
      }

      guard let self else { return }
      guard self.clearScheduledTask(id: scheduledID) else { return }
      action()
    }

    let shouldCancel = state.withLock { state -> Bool in
      guard state.scheduledID == scheduledID else { return true }
      state.scheduledTask = task
      return false
    }

    if shouldCancel {
      task.cancel()
    }
  }

  /// Returns whether one retry is still pending.
  var hasScheduledAction: Bool {
    state.withLock { $0.scheduledID != nil }
  }

  /// Cancels any pending retry and resets the delay sequence.
  public func cancel() {
    let task = state.withLock { state -> Task<Void, Never>? in
      let task = state.scheduledTask
      state.scheduledTask = nil
      state.scheduledID = nil
      state.attemptIndex = 0
      return task
    }

    task?.cancel()
  }

  /// Resets the delay sequence without touching any pending retry.
  public func resetDelay() {
    state.withLock { state in
      state.attemptIndex = 0
    }
  }

  /// Returns the delay for attempt.
  private func delayForAttempt(_ attemptIndex: Int) -> TimeInterval {
    guard !delays.isEmpty else {
      return 0
    }

    return delays[min(attemptIndex, delays.count - 1)]
  }

  /// Returns the log scheduled.
  private func logScheduled(delay: TimeInterval) {
    switch logLevel {
    case .trace:
      logger.trace("\(label) scheduled", .field("delay", "\(delay)"))
    case .debug:
      logger.debug("\(label) scheduled", .field("delay", "\(delay)"))
    case .info:
      logger.info("\(label) scheduled", .field("delay", "\(delay)"))
    case .warn:
      logger.warn("\(label) scheduled", .field("delay", "\(delay)"))
    case .error:
      logger.error("\(label) scheduled", .field("delay", "\(delay)"))
    }
  }

  /// Clears scheduled task.
  private func clearScheduledTask(id: UInt64) -> Bool {
    state.withLock { state -> Bool in
      guard state.scheduledID == id else {
        return false
      }

      state.scheduledTask = nil
      state.scheduledID = nil
      return true
    }
  }
}
