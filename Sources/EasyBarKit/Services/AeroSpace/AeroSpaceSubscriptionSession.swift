import EasyBarShared
import Foundation

/// Schedules AeroSpace subscription reconnect attempts.
protocol AeroSpaceReconnectScheduling: Sendable {
  /// Schedules one reconnect action.
  func schedule(_ action: @escaping @Sendable () -> Void)
  /// Cancels any pending reconnect action.
  func cancel()
  /// Resets the reconnect delay sequence.
  func resetDelay()
}

extension BackoffScheduler: AeroSpaceReconnectScheduling {}

/// Lifecycle surface consumed by `AeroSpaceService`.
protocol AeroSpaceSubscriptionControlling: Sendable {
  /// Starts subscription attempts until stopped.
  func start()
  /// Stops the active session and pending reconnect work.
  func stop()
}

/// Creates AeroSpace subscription sessions.
protocol AeroSpaceSubscriptionLaunching: Sendable {
  /// Creates one subscription session.
  func makeSubscription() -> AeroSpaceSubscriptionSession
}

/// One launchable AeroSpace subscription session.
protocol AeroSpaceSubscriptionSession: AnyObject, Sendable {
  /// Starts the subscription and installs event/disconnect callbacks.
  func start(
    onEventFrame: @escaping @Sendable (Data) -> Void,
    onDisconnect: @escaping @Sendable (AeroSpaceSubscriptionSession, String?) -> Void
  ) throws

  /// Stops the subscription and releases its resources.
  func stop()

  /// Releases callbacks and file descriptors without changing controller lifecycle state.
  func invalidate()
}
