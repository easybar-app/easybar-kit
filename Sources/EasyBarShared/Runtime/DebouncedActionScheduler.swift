import Foundation

/// Schedules one replaceable delayed action using Swift tasks.
///
/// Sendability is guarded by `LockedState`; pending task replacement and
/// generation checks are serialized through that lock.
public final class DebouncedActionScheduler: @unchecked Sendable {
  /// Stores state data.
  private struct State {
    /// The pending task for this state.
    var pendingTask: Task<Void, Never>?
    /// The pending generation for this state.
    var pendingGeneration: UInt64?
    /// The generation for this state.
    var generation: UInt64 = 0
  }

  private let label: String?
  private let delay: TimeInterval
  private let logger: ProcessLogger
  private let sleeper: any AsyncSleeper
  private let state = LockedState(State())

  /// Creates one debounced scheduler.
  public init(
    label: String? = nil,
    delay: TimeInterval,
    logger: ProcessLogger,
    sleeper: any AsyncSleeper = TaskSleeper()
  ) {
    self.label = label
    self.delay = delay
    self.logger = logger
    self.sleeper = sleeper
  }

  /// Replaces any pending action with a new delayed action.
  public func schedule(_ action: @escaping @Sendable () -> Void) {
    schedule(after: delay, action)
  }

  /// Replaces any pending action with a new delayed action and delay.
  public func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void) {
    let scheduledGeneration = state.withLock { state -> UInt64 in
      state.generation &+= 1
      state.pendingTask?.cancel()
      state.pendingTask = nil
      state.pendingGeneration = state.generation
      return state.generation
    }

    if let label {
      logger.debug(
        "\(label) scheduled",
        .field("delay", delay),
      )
    }

    let nanoseconds = clampedSleepNanoseconds(from: delay)
    let sleeper = sleeper
    let task = Task { [weak self] in
      do {
        try await sleeper.sleep(nanoseconds: nanoseconds)
      } catch {
        guard let self else { return }
        _ = self.finishScheduledAction(generation: scheduledGeneration)
        return
      }

      guard let self else { return }
      guard self.finishScheduledAction(generation: scheduledGeneration) else { return }
      action()
    }

    let shouldCancel = state.withLock { state -> Bool in
      guard state.pendingGeneration == scheduledGeneration else { return true }
      state.pendingTask = task
      return false
    }

    if shouldCancel {
      task.cancel()
    }
  }

  /// Returns whether one delayed action is still pending.
  var hasPendingAction: Bool {
    state.withLock { $0.pendingGeneration != nil }
  }

  /// Cancels any pending action.
  public func cancel() {
    let task = state.withLock { state -> Task<Void, Never>? in
      state.generation &+= 1
      let task = state.pendingTask
      state.pendingTask = nil
      state.pendingGeneration = nil
      return task
    }

    task?.cancel()
  }

  /// Clears the pending action if it is still the currently scheduled generation.
  private func finishScheduledAction(generation scheduledGeneration: UInt64) -> Bool {
    state.withLock { state -> Bool in
      guard state.pendingGeneration == scheduledGeneration else {
        return false
      }

      state.pendingTask = nil
      state.pendingGeneration = nil
      return true
    }
  }
}
