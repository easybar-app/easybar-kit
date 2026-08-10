import EasyBarCalendarPresentation
import EasyBarShared
import Foundation

@MainActor
final class UpcomingCalendarAgentClient {
  private let logger: ProcessLogger
  private var calendarAgentConfig: ConfigSnapshot.CalendarAgent
  private var calendarConfig: Config.CalendarBuiltinConfig
  private let metricsCoordinator: MetricsCoordinator
  private let store: NativeUpcomingCalendarStore
  private let eventRelay: CalendarAgentEventRelay

  private lazy var stream: CalendarAgentStreamController = CalendarAgentStreamController(
    label: "upcoming calendar agent client",
    socketPath: { [weak self] in self?.calendarAgentConfig.socketPath ?? "" },
    makeRequest: { [weak self] in
      self?.makeRequest() ?? CalendarAgentRequest(command: .ping)
    },
    applySnapshot: { snapshot in
      self.store.apply(snapshot: snapshot)
    },
    clearState: {
      self.store.clear()
    },
    metricsCoordinator: metricsCoordinator,
    eventRelay: eventRelay,
    logger: logger.child("stream")
  )

  init(
    logger: ProcessLogger,
    calendarAgentConfig: ConfigSnapshot.CalendarAgent,
    calendarConfig: Config.CalendarBuiltinConfig,
    store: NativeUpcomingCalendarStore,
    eventRelay: CalendarAgentEventRelay,
    metricsCoordinator: MetricsCoordinator = .shared
  ) {
    self.logger = logger
    self.calendarAgentConfig = calendarAgentConfig
    self.calendarConfig = calendarConfig
    self.store = store
    self.eventRelay = eventRelay
    self.metricsCoordinator = metricsCoordinator
  }

  /// Returns whether the upcoming-calendar agent client is currently active.
  var isConnected: Bool {
    return stream.isConnected
  }

  /// Replaces the active calendar config snapshots.
  func updateConfiguration(
    calendarAgentConfig: ConfigSnapshot.CalendarAgent,
    calendarConfig: Config.CalendarBuiltinConfig
  ) {
    let previousConfig = self.calendarAgentConfig

    self.calendarAgentConfig = calendarAgentConfig
    self.calendarConfig = calendarConfig

    guard
      stream.configurationDidChange(
        previousEnabled: previousConfig.enabled,
        previousSocketPath: previousConfig.socketPath,
        enabled: calendarAgentConfig.enabled,
        socketPath: calendarAgentConfig.socketPath
      )
    else { return }
    stream.refresh()
  }

  /// Starts the upcoming-calendar agent socket client when enabled.
  func start() {
    stream.start(enabled: calendarAgentConfig.enabled)
  }

  /// Stops the upcoming-calendar agent socket client.
  func stop() {
    stream.stop()
  }

  /// Requests one fresh snapshot from the calendar agent.
  func refresh() {
    stream.refresh()
  }

  /// Builds the current upcoming-calendar request.
  private func makeRequest() -> CalendarAgentRequest {
    let now = Date()
    let upcoming = calendarConfig.upcoming
    let options = calendarConfig.presentationUpcomingRequestOptions
    let requestedRange = CalendarRequestFactory.requestedUpcomingDateRange(
      now: now,
      dayCount: options.dayCount
    )

    logger.debug(
      "requesting upcoming calendar snapshot",
      .field("start", requestedRange.start.timeIntervalSince1970),
      .field("end", requestedRange.end.timeIntervalSince1970),
      .field("days", options.dayCount),
      .field("exclude_past_events", upcoming.events.excludePastEvents),
      .field("show_birthdays", options.birthdays.showBirthdays),
    )

    return CalendarRequestFactory.makeUpcomingSubscribeRequest(now: now, options: options)
  }
}
