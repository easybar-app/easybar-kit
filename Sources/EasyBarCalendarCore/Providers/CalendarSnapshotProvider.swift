import EasyBarShared
import EventKit
import Foundation

/// Builds calendar snapshots and applies calendar event mutations.
final class CalendarSnapshotProvider: @unchecked Sendable {
  /// Locale used for stable date formatting.
  static let formatterLocale = Locale(identifier: "en_US_POSIX")
  /// Calendar used for stable date formatting.
  static let formatterCalendar = Calendar(identifier: .gregorian)
  /// Time zone used for user-facing calendar output.
  static let formatterTimeZone = TimeZone.autoupdatingCurrent
  /// Cached birthday formatters keyed by format string.
  static let birthdayFormatters = LockedState([String: DateFormatter]())
  /// Serializes access to shared Foundation formatter instances.
  static let formatterLock = NSLock()
  /// Cached link detector reused across event snapshots.
  static let linkDetector = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.link.rawValue
  )
  /// Serializes use of the shared link detector.
  static let linkDetectorLock = NSLock()

  /// Formatter for timed event rows.
  static let eventTimeFormatter: DateFormatter = makeFormatter(format: "HH:mm")
  /// Formatter for future day section titles.
  static let dayTitleFormatter: DateFormatter = makeFormatter(format: "dd.MM.yyyy")

  /// EventKit store used for reads and mutations.
  let eventStore: EKEventStore
  /// Notification center used for EventKit change observation.
  private let notificationCenter: NotificationCenter
  /// Shared authorization state used by the provider and controller.
  private let authState = CalendarAuthorizationState()
  /// Logger used for snapshot and mutation diagnostics.
  private let logger: ProcessLogger
  /// Controller that owns calendar permission flow.
  private let authorizationController: CalendarAuthorizationController
  /// EventKit change observer token.
  private var observer: NSObjectProtocol?
  /// Callback invoked when calendar data may have changed.
  private var onChange: (() -> Void)?

  /// Creates one calendar snapshot provider that logs through the provided logger.
  init(
    logger: ProcessLogger,
    eventStore: EKEventStore = EKEventStore(),
    notificationCenter: NotificationCenter = .default,
    authorizationStatus: (() -> EKAuthorizationStatus)? = nil,
    requestAccess: ((@escaping (Bool, Error?) -> Void) -> Void)? = nil
  ) {
    self.logger = logger
    self.eventStore = eventStore
    self.notificationCenter = notificationCenter
    authorizationController = CalendarAuthorizationController(
      eventStore: eventStore,
      authState: authState,
      logger: logger.child("authorization"),
      authorizationStatus: authorizationStatus,
      requestAccess: requestAccess
    )
  }

  /// Starts calendar access, observation, and change callbacks.
  func start(onChange: @escaping () -> Void) {
    stop()
    self.onChange = onChange

    authorizationController.start { [weak self] in
      self?.onChange?()
    }

    observer = notificationCenter.addObserver(
      forName: .EKEventStoreChanged,
      object: eventStore,
      queue: .main
    ) { [weak self] _ in
      self?.logger.info("calendar store changed")
      self?.onChange?()
    }
  }

  /// Stops observing calendar store changes.
  func stop() {
    authorizationController.stop()

    if let observer {
      notificationCenter.removeObserver(observer)
      self.observer = nil
    }

    onChange = nil
  }

  /// Builds one calendar snapshot for the requested query.
  func snapshot(for query: CalendarAgentQuery) -> CalendarAgentSnapshot {
    authorizationController.refreshStatus()

    let hasAccess = authorizationController.effectiveAccessGranted()
    let permissionState = authorizationController.permissionState()
    let now = Date()

    guard hasAccess else {
      logger.debug(
        "calendar snapshot",
        .field("access_granted", false),
        .field("permission_state", permissionState),
      )
      return makeAccessDeniedSnapshot(permissionState: permissionState, generatedAt: now)
    }

    do {
      try CalendarAgentRequestValidator.validate(query)
    } catch {
      logger.warn("calendar snapshot rejected", .field("error", error))
      return makeEmptySnapshot(
        permissionState: permissionState,
        generatedAt: now,
        writableCalendars: writableCalendars()
      )
    }

    guard let fetchRange = normalizedFetchRange(from: query) else {
      logger.warn("calendar snapshot invalid fetch range")
      return makeEmptySnapshot(
        permissionState: permissionState,
        generatedAt: now,
        writableCalendars: writableCalendars()
      )
    }

    let events = makeNormalizedEvents(
      query: query,
      fetchStart: fetchRange.start,
      fetchEndExclusive: fetchRange.end
    )

    let sections = makeSections(
      query: query,
      events: events
    )

    let snapshot = CalendarAgentSnapshot(
      accessGranted: true,
      permissionState: permissionState,
      generatedAt: now,
      writableCalendars: writableCalendars(),
      events: events,
      sections: sections
    )

    logger.debug(
      "calendar snapshot",
      .field("access_granted", true),
      .field("permission_state", permissionState),
      .field("fetch_start", fetchRange.start),
      .field("fetch_end", fetchRange.end),
      .field("section_start", String(describing: query.sectionStartDate)),
      .field("section_day_count", String(describing: query.sectionDayCount)),
      .field("show_birthdays", query.showBirthdays),
      .field("included_calendar_names", query.includedCalendarNames),
      .field("excluded_calendar_names", query.excludedCalendarNames),
      .field("included_calendar_ids", query.includedCalendarIDs),
      .field("excluded_calendar_ids", query.excludedCalendarIDs),
      .field("included_calendar_source_ids", query.includedCalendarSourceIDs),
      .field("excluded_calendar_source_ids", query.excludedCalendarSourceIDs),
      .field("writable_calendars", snapshot.writableCalendars.count),
      .field("events", snapshot.events.count),
      .field("sections", snapshot.sections.count),
    )

    return snapshot
  }

  /// Creates one new calendar event through EventKit.
  func createEvent(_ draft: CalendarAgentCreateEvent) throws {
    try CalendarAgentRequestValidator.validate(draft)
    authorizationController.refreshStatus()

    guard authorizationController.effectiveAccessGranted() else {
      throw CalendarAgentMutationError.accessDenied
    }

    let event = EKEvent(eventStore: eventStore)
    event.calendar = try resolvedCalendar(id: draft.calendarID)
    event.title = normalizedTitle(draft.title)
    event.startDate = draft.startDate
    event.endDate = draft.endDate
    event.isAllDay = draft.isAllDay
    event.location = normalizedOptionalText(draft.location)
    applyTravelTime(draft.travelTimeSeconds, to: event)
    event.alarms = draft.alertOffsetsSeconds.map { EKAlarm(relativeOffset: -abs($0)) }

    try eventStore.save(event, span: .thisEvent, commit: true)

    logger.info(
      "calendar event created",
      .field("title", event.title ?? "Untitled"),
      .field("start", draft.startDate),
      .field("end", draft.endDate),
      .field("all_day", draft.isAllDay),
      .field("calendar", event.calendar.title),
      .field("location", event.location ?? ""),
    )

    Task { @MainActor [weak self] in
      self?.onChange?()
    }

  }

  /// Updates one existing calendar event through EventKit.
  func updateEvent(_ draft: CalendarAgentUpdateEvent) throws {
    try CalendarAgentRequestValidator.validate(draft)
    authorizationController.refreshStatus()

    guard authorizationController.effectiveAccessGranted() else {
      throw CalendarAgentMutationError.accessDenied
    }

    guard let event = resolvedEvent(id: draft.eventIdentifier) else {
      throw CalendarAgentMutationError.eventNotFound
    }

    event.calendar = try resolvedCalendar(id: draft.calendarID)
    event.title = normalizedTitle(draft.title)
    event.startDate = draft.startDate
    event.endDate = draft.endDate
    event.isAllDay = draft.isAllDay
    event.location = normalizedOptionalText(draft.location)
    applyTravelTime(draft.travelTimeSeconds, to: event)

    if draft.alertOffsetsSeconds.isEmpty {
      event.alarms = nil
    } else {
      event.alarms = draft.alertOffsetsSeconds.map { EKAlarm(relativeOffset: -abs($0)) }
    }

    try eventStore.save(event, span: .thisEvent, commit: true)

    logger.info(
      "calendar event updated",
      .field("event_id", draft.eventIdentifier),
      .field("title", event.title ?? "Untitled"),
      .field("start", draft.startDate),
      .field("end", draft.endDate),
      .field("all_day", draft.isAllDay),
      .field("calendar", event.calendar.title),
      .field("location", event.location ?? ""),
    )

    Task { @MainActor [weak self] in
      self?.onChange?()
    }
  }

  /// Deletes one existing calendar event through EventKit.
  func deleteEvent(_ draft: CalendarAgentDeleteEvent) throws {
    try CalendarAgentRequestValidator.validate(draft)
    authorizationController.refreshStatus()

    guard authorizationController.effectiveAccessGranted() else {
      throw CalendarAgentMutationError.accessDenied
    }

    guard let event = resolvedEvent(id: draft.eventIdentifier) else {
      throw CalendarAgentMutationError.eventNotFound
    }

    try eventStore.remove(event, span: .thisEvent, commit: true)

    logger.info(
      "calendar event deleted",
      .field("event_id", draft.eventIdentifier),
      .field("title", event.title ?? "Untitled"),
    )

    Task { @MainActor [weak self] in
      self?.onChange?()
    }
  }

  /// Applies EventKit travel time when the current macOS implementation supports it.
  private func applyTravelTime(_ seconds: TimeInterval?, to event: EKEvent) {
    guard !EventKitTravelTimeAdapter.write(seconds, to: event), seconds != nil else { return }

    logger.debug(
      "calendar event travel time unsupported",
      .field("seconds", seconds ?? 0)
    )
  }

  /// Returns one normalized fetch range when valid.
  private func normalizedFetchRange(from query: CalendarAgentQuery) -> DateInterval? {
    guard query.startDate < query.endDate else { return nil }
    return DateInterval(start: query.startDate, end: query.endDate)
  }

  /// Returns one empty snapshot for denied access.
  private func makeAccessDeniedSnapshot(
    permissionState: String,
    generatedAt: Date
  ) -> CalendarAgentSnapshot {
    CalendarAgentSnapshot(
      accessGranted: false,
      permissionState: permissionState,
      generatedAt: generatedAt,
      writableCalendars: [],
      events: [],
      sections: []
    )
  }

  /// Returns one empty successful snapshot.
  private func makeEmptySnapshot(
    permissionState: String,
    generatedAt: Date,
    writableCalendars: [CalendarAgentWritableCalendar]
  ) -> CalendarAgentSnapshot {
    CalendarAgentSnapshot(
      accessGranted: true,
      permissionState: permissionState,
      generatedAt: generatedAt,
      writableCalendars: writableCalendars,
      events: [],
      sections: []
    )
  }

  /// Creates one stable formatter for deterministic popup rendering.
  static func makeFormatter(format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = formatterLocale
    formatter.calendar = formatterCalendar
    formatter.timeZone = formatterTimeZone
    formatter.dateFormat = format
    return formatter
  }
}
