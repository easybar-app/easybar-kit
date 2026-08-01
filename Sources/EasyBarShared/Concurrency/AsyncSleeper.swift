import Foundation

/// Abstracts async sleeping so schedulers can be tested without real-time delays.
public protocol AsyncSleeper: Sendable {
  /// Suspends for the requested duration.
  func sleep(nanoseconds: UInt64) async throws
}

/// Default sleeper backed by `Task.sleep`.
public struct TaskSleeper: AsyncSleeper {
  /// Creates a task-backed sleeper.
  public init() {}

  /// Suspends the current task for the requested duration.
  public func sleep(nanoseconds: UInt64) async throws {
    try await Task.sleep(for: .nanoseconds(Int64(clamping: nanoseconds)))
  }
}
