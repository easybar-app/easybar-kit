import Foundation

/// Lifecycle operation that must be serialized by the runtime coordinator.
enum RuntimeLifecycleOperation: String, Hashable {
  /// Reloads config and reapplies all dependent runtime state.
  case reloadConfig
  /// Restarts only the Lua/widget runtime.
  case restartLuaRuntime
}

/// Result of attempting to begin a serialized lifecycle operation.
enum RuntimeLifecycleBeginResult {
  /// The operation was rejected because runtime services are stopped.
  case notStarted
  /// The operation was queued because another operation is already running.
  case queued
  /// The operation may proceed for the returned generation.
  case started(generation: UInt64)
}

/// Small state machine that owns runtime lifecycle and reload/restart queue state.
struct RuntimeLifecycleStateMachine {
  /// Whether runtime services are currently started.
  private(set) var started = false
  /// Generation used to cancel stale lifecycle work.
  private(set) var generation: UInt64 = 0
  /// Operation currently holding lifecycle ownership.
  private var activeOperation: RuntimeLifecycleOperation?
  /// Operations requested while lifecycle ownership is busy.
  private var pendingOperations = Set<RuntimeLifecycleOperation>()

  /// Returns whether the runtime is currently busy with another lifecycle operation.
  private var isBusy: Bool {
    activeOperation != nil
  }

  /// Starts the runtime lifecycle and returns the generation for startup work.
  mutating func start() -> UInt64? {
    guard !started else { return nil }

    let generation = advanceGeneration()
    started = true
    return generation
  }

  /// Stops the runtime lifecycle and clears all queued or in-flight work.
  mutating func stop() -> Bool {
    guard started else { return false }

    started = false
    _ = advanceGeneration()
    resetWork()
    return true
  }

  /// Begins one lifecycle operation or queues it when another operation is active.
  mutating func begin(_ operation: RuntimeLifecycleOperation) -> RuntimeLifecycleBeginResult {
    guard started else { return .notStarted }

    if isBusy {
      pendingOperations.insert(operation)
      return .queued
    }

    activeOperation = operation
    return .started(generation: generation)
  }

  /// Returns whether startup work for the provided generation may still continue.
  func canContinueStartup(generation expectedGeneration: UInt64) -> Bool {
    started && generation == expectedGeneration
  }

  /// Returns whether lifecycle work for the provided generation may still continue.
  mutating func canContinueLifecycleWork(generation expectedGeneration: UInt64) -> Bool {
    guard started, generation == expectedGeneration else {
      if generation == expectedGeneration {
        resetWork()
      }

      return false
    }

    return true
  }

  /// Marks one lifecycle operation as finished and returns the next queued operation.
  mutating func finish() -> RuntimeLifecycleOperation? {
    activeOperation = nil
    return dequeueNextOperation()
  }

  /// Advances the lifecycle generation and returns the new value.
  private mutating func advanceGeneration() -> UInt64 {
    generation &+= 1
    return generation
  }

  /// Clears queued and in-flight lifecycle work.
  private mutating func resetWork() {
    activeOperation = nil
    pendingOperations.removeAll()
  }

  /// Dequeues the next pending lifecycle operation in priority order.
  private mutating func dequeueNextOperation() -> RuntimeLifecycleOperation? {
    if pendingOperations.remove(.reloadConfig) != nil {
      return .reloadConfig
    }

    if pendingOperations.remove(.restartLuaRuntime) != nil {
      return .restartLuaRuntime
    }

    return nil
  }
}
