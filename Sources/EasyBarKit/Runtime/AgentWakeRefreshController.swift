import EasyBarShared
import Foundation

/// Shares the wake-triggered refresh observation used by app-side agent services.
final class AgentWakeRefreshController: @unchecked Sendable {
  /// Human-readable service label used in logs and queue names.
  private let label: String
  /// Debounce delay before running a wake refresh.
  private let delay: TimeInterval
  /// Logger used for wake-refresh diagnostics.
  private let logger: ProcessLogger
  /// Observer for app-wide wake events.
  private let eventObserver: EasyBarEventObserver

  /// Scheduler that coalesces wake refresh requests.
  private lazy var scheduler = DebouncedActionScheduler(
    label: "\(label) wake refresh",
    delay: delay,
    logger: logger.child("scheduler")
  )

  /// Creates a wake refresh controller.
  init(
    label: String,
    delay: TimeInterval = 0.20,
    eventHub: EventHub,
    logger: ProcessLogger
  ) {
    self.label = label
    self.delay = delay
    self.eventObserver = EasyBarEventObserver(eventHub: eventHub)
    self.logger = logger
  }

  /// Starts observing `system_woke` and schedules the refresh callback.
  func start(refresh: @escaping @Sendable () -> Void) {
    eventObserver.start(eventNames: [AppEvent.systemWoke.rawValue]) { [weak self] payload in
      guard let self else { return }
      guard payload.appEvent == .systemWoke else { return }

      self.scheduler.schedule { [weak self] in
        guard let self else { return }

        self.logger.debug("\(self.label) refreshing after system_woke")
        refresh()
      }
    }
  }

  /// Stops wake observation and cancels queued refresh work.
  func stop() {
    scheduler.cancel()
    eventObserver.stop()
  }
}
