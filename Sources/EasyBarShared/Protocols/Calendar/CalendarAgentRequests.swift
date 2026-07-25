import Foundation

public struct CalendarAgentQuery: Codable, Equatable, Sendable {
  /// Inclusive fetch start date.
  public var startDate: Date
  /// Exclusive fetch end date.
  public var endDate: Date
  /// Optional section start date used for the regular calendar popup.
  public var sectionStartDate: Date?
  /// Optional number of section days used for the regular calendar popup.
  public var sectionDayCount: Int?
  /// Whether birthdays should be included.
  public var showBirthdays: Bool
  /// Text shown when no events are available.
  public var emptyText: String
  /// Title used for today sections.
  public var todayTitle: String
  /// Title used for tomorrow sections.
  public var tomorrowTitle: String
  /// Label used for all-day event times.
  public var allDayLabel: String
  /// Title used for the birthdays section.
  public var birthdaysTitle: String
  /// Date format used for birthday rows.
  public var birthdaysDateFormat: String
  /// Whether birthday ages should be shown.
  public var birthdaysShowAge: Bool
  /// Optional allowlist of visible calendar names. Empty means all calendars.
  public var includedCalendarNames: [String]
  /// Optional denylist of visible calendar names.
  public var excludedCalendarNames: [String]
  /// Optional allowlist of calendar identifiers.
  public var includedCalendarIDs: [String]
  /// Optional denylist of calendar identifiers.
  public var excludedCalendarIDs: [String]
  /// Optional allowlist of calendar source identifiers.
  public var includedCalendarSourceIDs: [String]
  /// Optional denylist of calendar source identifiers.
  public var excludedCalendarSourceIDs: [String]

  /// Creates one calendar agent query.
  public init(
    startDate: Date,
    endDate: Date,
    sectionStartDate: Date? = nil,
    sectionDayCount: Int? = nil,
    showBirthdays: Bool,
    emptyText: String,
    todayTitle: String = "Today",
    tomorrowTitle: String = "Tomorrow",
    allDayLabel: String = "All day",
    birthdaysTitle: String,
    birthdaysDateFormat: String,
    birthdaysShowAge: Bool,
    includedCalendarNames: [String] = [],
    excludedCalendarNames: [String] = [],
    includedCalendarIDs: [String] = [],
    excludedCalendarIDs: [String] = [],
    includedCalendarSourceIDs: [String] = [],
    excludedCalendarSourceIDs: [String] = []
  ) {
    self.startDate = startDate
    self.endDate = endDate
    self.sectionStartDate = sectionStartDate
    self.sectionDayCount = sectionDayCount
    self.showBirthdays = showBirthdays
    self.emptyText = emptyText
    self.todayTitle = todayTitle
    self.tomorrowTitle = tomorrowTitle
    self.allDayLabel = allDayLabel
    self.birthdaysTitle = birthdaysTitle
    self.birthdaysDateFormat = birthdaysDateFormat
    self.birthdaysShowAge = birthdaysShowAge
    self.includedCalendarNames = includedCalendarNames
    self.excludedCalendarNames = excludedCalendarNames
    self.includedCalendarIDs = includedCalendarIDs
    self.excludedCalendarIDs = excludedCalendarIDs
    self.includedCalendarSourceIDs = includedCalendarSourceIDs
    self.excludedCalendarSourceIDs = excludedCalendarSourceIDs
  }

  private enum CodingKeys: String, CodingKey {
    case startDate
    case endDate
    case sectionStartDate
    case sectionDayCount
    case showBirthdays
    case emptyText
    case todayTitle
    case tomorrowTitle
    case allDayLabel
    case birthdaysTitle
    case birthdaysDateFormat
    case birthdaysShowAge
    case includedCalendarNames
    case excludedCalendarNames
    case includedCalendarIDs
    case excludedCalendarIDs
    case includedCalendarSourceIDs
    case excludedCalendarSourceIDs
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    startDate = try container.decode(Date.self, forKey: .startDate)
    endDate = try container.decode(Date.self, forKey: .endDate)
    sectionStartDate = try container.decodeIfPresent(Date.self, forKey: .sectionStartDate)
    sectionDayCount = try container.decodeIfPresent(Int.self, forKey: .sectionDayCount)
    showBirthdays = try container.decode(Bool.self, forKey: .showBirthdays)
    emptyText = try container.decode(String.self, forKey: .emptyText)
    todayTitle = try container.decodeIfPresent(String.self, forKey: .todayTitle) ?? "Today"
    tomorrowTitle = try container.decodeIfPresent(String.self, forKey: .tomorrowTitle) ?? "Tomorrow"
    allDayLabel = try container.decodeIfPresent(String.self, forKey: .allDayLabel) ?? "All day"
    birthdaysTitle = try container.decode(String.self, forKey: .birthdaysTitle)
    birthdaysDateFormat = try container.decode(String.self, forKey: .birthdaysDateFormat)
    birthdaysShowAge = try container.decode(Bool.self, forKey: .birthdaysShowAge)
    includedCalendarNames =
      try container.decodeIfPresent([String].self, forKey: .includedCalendarNames) ?? []
    excludedCalendarNames =
      try container.decodeIfPresent([String].self, forKey: .excludedCalendarNames) ?? []
    includedCalendarIDs =
      try container.decodeIfPresent([String].self, forKey: .includedCalendarIDs) ?? []
    excludedCalendarIDs =
      try container.decodeIfPresent([String].self, forKey: .excludedCalendarIDs) ?? []
    includedCalendarSourceIDs =
      try container.decodeIfPresent([String].self, forKey: .includedCalendarSourceIDs) ?? []
    excludedCalendarSourceIDs =
      try container.decodeIfPresent([String].self, forKey: .excludedCalendarSourceIDs) ?? []
  }
}

/// One create-event payload sent to the calendar agent.
public struct CalendarAgentCreateEvent: Codable, Equatable, Sendable {
  /// Event title.
  public var title: String
  /// Event start date.
  public var startDate: Date
  /// Event end date.
  public var endDate: Date
  /// Whether the event is all day.
  public var isAllDay: Bool
  /// Optional calendar identifier to create the event in.
  public var calendarID: String?
  /// Optional event location.
  public var location: String?
  /// Optional alert lead times in seconds before the event.
  public var alertOffsetsSeconds: [TimeInterval]
  /// Optional travel time in seconds.
  public var travelTimeSeconds: TimeInterval?

  /// Creates one calendar agent create-event payload.
  public init(
    title: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool,
    calendarID: String? = nil,
    location: String? = nil,
    alertOffsetsSeconds: [TimeInterval] = [],
    travelTimeSeconds: TimeInterval? = nil
  ) {
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.isAllDay = isAllDay
    self.calendarID = calendarID
    self.location = location
    self.alertOffsetsSeconds = alertOffsetsSeconds
    self.travelTimeSeconds = travelTimeSeconds
  }
}

/// One update-event payload sent to the calendar agent.
public struct CalendarAgentUpdateEvent: Codable, Equatable, Sendable {
  /// Stable EventKit event identifier.
  public var eventIdentifier: String
  /// Updated event title.
  public var title: String
  /// Updated event start date.
  public var startDate: Date
  /// Updated event end date.
  public var endDate: Date
  /// Whether the event is all day.
  public var isAllDay: Bool
  /// Optional calendar identifier to move the event to.
  public var calendarID: String?
  /// Optional event location.
  public var location: String?
  /// Optional alert lead times in seconds before the event.
  public var alertOffsetsSeconds: [TimeInterval]
  /// Optional travel time in seconds.
  public var travelTimeSeconds: TimeInterval?

  /// Creates one calendar agent update-event payload.
  public init(
    eventIdentifier: String,
    title: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool,
    calendarID: String? = nil,
    location: String? = nil,
    alertOffsetsSeconds: [TimeInterval] = [],
    travelTimeSeconds: TimeInterval? = nil
  ) {
    self.eventIdentifier = eventIdentifier
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.isAllDay = isAllDay
    self.calendarID = calendarID
    self.location = location
    self.alertOffsetsSeconds = alertOffsetsSeconds
    self.travelTimeSeconds = travelTimeSeconds
  }
}

/// One delete-event payload sent to the calendar agent.
public struct CalendarAgentDeleteEvent: Codable, Equatable, Sendable {
  /// Stable EventKit event identifier.
  public var eventIdentifier: String

  /// Creates one calendar agent delete-event payload.
  public init(eventIdentifier: String) {
    self.eventIdentifier = eventIdentifier
  }
}

/// One request sent to the calendar agent.
public struct CalendarAgentRequest: Codable, Equatable, Sendable {
  /// Optional client-generated identifier echoed by direct agent responses.
  public var requestID: String?
  /// Command to execute on the agent.
  public var command: CalendarAgentCommand
  /// Optional query used for fetch and subscribe requests.
  public var query: CalendarAgentQuery?
  /// Optional create-event payload used for event creation.
  public var createEvent: CalendarAgentCreateEvent?
  /// Optional update-event payload used for event updates.
  public var updateEvent: CalendarAgentUpdateEvent?
  /// Optional delete-event payload used for event deletion.
  public var deleteEvent: CalendarAgentDeleteEvent?
  /// Optional live-log subscription used by the logs command.
  public var logSubscription: IPC.LogSubscription?

  /// Creates one calendar agent request.
  public init(
    command: CalendarAgentCommand,
    requestID: String? = nil,
    query: CalendarAgentQuery? = nil,
    createEvent: CalendarAgentCreateEvent? = nil,
    updateEvent: CalendarAgentUpdateEvent? = nil,
    deleteEvent: CalendarAgentDeleteEvent? = nil,
    logSubscription: IPC.LogSubscription? = nil
  ) {
    self.requestID = requestID
    self.command = command
    self.query = query
    self.createEvent = createEvent
    self.updateEvent = updateEvent
    self.deleteEvent = deleteEvent
    self.logSubscription = logSubscription
  }

  /// Returns a copy carrying one client-generated correlation identifier.
  public func correlated(requestID: String) -> Self {
    var request = self
    request.requestID = requestID
    return request
  }

  /// Builds one fetch request.
  public static func fetch(_ query: CalendarAgentQuery) -> Self {
    return Self(command: .fetch, query: query)
  }

  /// Builds one subscribe request.
  public static func subscribe(_ query: CalendarAgentQuery) -> Self {
    return Self(command: .subscribe, query: query)
  }

  /// Builds one live-log subscription request.
  public static func logs(_ subscription: IPC.LogSubscription = IPC.LogSubscription()) -> Self {
    return Self(command: .logs, logSubscription: subscription)
  }

  /// Builds one create-event request.
  public static func createEvent(_ payload: CalendarAgentCreateEvent) -> Self {
    return Self(command: .createEvent, createEvent: payload)
  }

  /// Builds one update-event request.
  public static func updateEvent(_ payload: CalendarAgentUpdateEvent) -> Self {
    return Self(command: .updateEvent, updateEvent: payload)
  }

  /// Builds one delete-event request.
  public static func deleteEvent(_ payload: CalendarAgentDeleteEvent) -> Self {
    return Self(command: .deleteEvent, deleteEvent: payload)
  }
}

/// One version payload returned by the calendar agent.
