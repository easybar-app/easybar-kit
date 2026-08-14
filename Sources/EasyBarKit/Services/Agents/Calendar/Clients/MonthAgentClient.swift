import EasyBarCalendarPresentation
import EasyBarShared
import Foundation

/// Agent client used by the reusable month-calendar popup.
@MainActor
final class MonthCalendarAgentClient {
  /// Logger used for month-calendar agent diagnostics.
  private let logger: ProcessLogger
  /// Active calendar-agent config snapshot.
  private var calendarAgentConfig: ConfigSnapshot.CalendarAgent
  /// Active calendar built-in config snapshot.
  private var calendarConfig: Config.CalendarBuiltinConfig
  /// Metrics recorder for calendar-agent lifecycle and messages.
  private let metricsCoordinator: MetricsCoordinator
  private let store: NativeMonthCalendarStore
  private let eventRelay: CalendarAgentEventRelay
  private var refreshRelatedClients: @MainActor () -> Void = {}

  /// Delay schedule for staged month preload requests.
  private let preloadDelays: [TimeInterval] = [0.0, 0.20, 0.75, 1.75, 3.5, 6.5, 10.0]

  /// Pending staged month preload tasks.
  private var preloadTasks: [Task<Void, Never>] = []

  /// Long-lived calendar-agent stream controller.
  private lazy var stream: CalendarAgentStreamController = CalendarAgentStreamController(
    label: "month calendar agent client",
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

  /// Creates one month-calendar agent client.
  init(
    logger: ProcessLogger,
    calendarAgentConfig: ConfigSnapshot.CalendarAgent,
    calendarConfig: Config.CalendarBuiltinConfig,
    store: NativeMonthCalendarStore,
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

  /// Installs the refresh action run after successful calendar mutations.
  func setRelatedClientRefresh(_ refresh: @escaping @MainActor () -> Void) {
    refreshRelatedClients = refresh
  }

  /// Returns whether the month-calendar agent client is currently active.
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

  /// Starts the month-calendar agent socket client when enabled.
  func start() {
    stream.start(enabled: calendarAgentConfig.enabled)
  }

  /// Stops the month-calendar agent socket client.
  func stop() {
    cancelStagedPreload()
    stream.stop()
  }

  /// Starts staged month loading centered on the visible month.
  func focusVisibleMonth(_ visibleMonth: Date) {
    cancelStagedPreload()

    let calendar = resolvedCalendar()
    let maximumRadius = CalendarMonthRangeBuilder.maximumSafeSubscriptionRadius(
      for: visibleMonth,
      calendar: calendar
    )

    for (index, radius) in (0...maximumRadius).enumerated() {
      let delay = preloadDelays[min(index, preloadDelays.count - 1)]
      let task = Task { @MainActor [weak self] in
        do {
          try await Task.sleep(for: .seconds(max(delay, 0)))
        } catch {
          return
        }

        self?.refreshMonthSubscriptionIfNeeded(
          for: visibleMonth,
          radius: radius
        )
      }

      preloadTasks.append(task)
    }
  }

  /// Refreshes the active month subscription if the preload window changed.
  func refreshMonthSubscriptionIfNeeded(for visibleMonth: Date, radius: Int) {
    let calendar = resolvedCalendar()
    let changed = store.prepareMonthSubscriptionRange(
      for: visibleMonth,
      radius: radius,
      calendar: calendar
    )
    guard changed else { return }

    refresh()
  }

  /// Requests one fresh month-calendar snapshot.
  func refresh() {
    stream.refresh()
  }

  /// Sends one create-event request through the calendar agent.
  func createEvent(
    _ event: CalendarAgentCreateEvent,
    completion: @escaping @MainActor @Sendable (_ success: Bool, _ message: String?) -> Void
  ) {
    let request = CalendarAgentRequest(
      command: .createEvent,
      createEvent: event
    )

    sendOneShot(request: request, successKind: .created, completion: completion)
  }

  /// Sends one update-event request through the calendar agent.
  func updateEvent(
    _ event: CalendarAgentUpdateEvent,
    completion: @escaping @MainActor @Sendable (_ success: Bool, _ message: String?) -> Void
  ) {
    let request = CalendarAgentRequest(
      command: .updateEvent,
      updateEvent: event
    )

    sendOneShot(request: request, successKind: .updated, completion: completion)
  }

  /// Sends one delete-event request through the calendar agent.
  func deleteEvent(
    _ event: CalendarAgentDeleteEvent,
    completion: @escaping @MainActor @Sendable (_ success: Bool, _ message: String?) -> Void
  ) {
    let request = CalendarAgentRequest(
      command: .deleteEvent,
      deleteEvent: event
    )

    sendOneShot(request: request, successKind: .deleted, completion: completion)
  }

  /// Sends one mutating request through the calendar agent.
  private func sendOneShot(
    request: CalendarAgentRequest,
    successKind: CalendarAgentMessageKind,
    completion: @escaping @MainActor @Sendable (_ success: Bool, _ message: String?) -> Void
  ) {
    let socketPath = calendarAgentConfig.socketPath

    DetachedTask.run(priority: .userInitiated) { [weak self] in
      do {
        let response = try CalendarAgentOneShotClient.send(
          request: request,
          socketPath: socketPath
        )

        await MainActor.run { [weak self] in
          self?.handleMutationResponse(
            response,
            successKind: successKind,
            completion: completion
          )
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.handleMutationError(
            error,
            completion: completion
          )
        }
      }
    }
  }

  /// Handles one calendar-agent mutation response on the main actor.
  private func handleMutationResponse(
    _ response: CalendarAgentMessage,
    successKind: CalendarAgentMessageKind,
    completion: @MainActor @Sendable (_ success: Bool, _ message: String?) -> Void
  ) {
    switch response.kind {
    case successKind:
      refresh()
      refreshRelatedClients()
      completion(true, nil)

    case .error:
      let message = response.message ?? "unknown"
      logger.error(
        "month calendar mutation failed",
        .field("message", message)
      )
      completion(false, message)

    default:
      logger.error(
        "month calendar mutation unexpected response",
        .field("response", response.kind.rawValue)
      )
      completion(false, "unexpected_response")
    }
  }

  /// Handles one calendar-agent mutation failure on the main actor.
  private func handleMutationError(
    _ error: Error,
    completion: @MainActor @Sendable (_ success: Bool, _ message: String?) -> Void
  ) {
    logger.error(
      "month calendar mutation failed",
      .field("error", error)
    )
    completion(false, error.localizedDescription)
  }

  /// Builds the current month-calendar fetch request.
  private func makeRequest() -> CalendarAgentRequest {
    let requestedRange: DateInterval

    if let prepared = store.monthSubscriptionRange() {
      requestedRange = DateInterval(start: prepared.start, end: prepared.end)
    } else {
      requestedRange = defaultRequestedDateRange(referenceDate: Date())
    }

    let options = calendarConfig.presentationMonthRequestOptions

    logger.debug(
      "requesting month calendar snapshot",
      .field("start", requestedRange.start.timeIntervalSince1970),
      .field("end", requestedRange.end.timeIntervalSince1970),
      .field("show_birthdays", options.birthdays.showBirthdays),
      .field("birthdays_show_age", options.birthdays.showAge)
    )

    return CalendarRequestFactory.makeMonthSubscribeRequest(
      range: requestedRange,
      options: options
    )
  }

  /// Returns the default month preload range around the given reference date.
  private func defaultRequestedDateRange(referenceDate: Date) -> DateInterval {
    let calendar = resolvedCalendar()
    let currentMonthStart = CalendarMonthRangeBuilder.startOfMonth(
      referenceDate, calendar: calendar)

    return CalendarMonthRangeBuilder.visibleGridRange(for: currentMonthStart, calendar: calendar)
      ?? DateInterval(
        start: currentMonthStart,
        end:
          calendar.date(byAdding: .month, value: 1, to: currentMonthStart)
          ?? referenceDate.addingTimeInterval(31 * 86_400)
      )
  }

  /// Cancels any pending staged month expansion.
  private func cancelStagedPreload() {
    for preloadTask in preloadTasks {
      preloadTask.cancel()
    }
    preloadTasks.removeAll()
  }

  /// Returns the calendar resolved for month-grid subscription ranges.
  private func resolvedCalendar() -> Calendar {
    var calendar = Calendar.current

    if let firstWeekday = calendarConfig.month.popup.calendar.firstWeekday {
      calendar.firstWeekday = firstWeekday
    }

    return calendar
  }

}
