import Foundation

/// Service-level limits applied to calendar agent requests before EventKit work begins.
public enum CalendarAgentRequestLimits {
  /// Longest fetch or mutation interval accepted by the calendar agent.
  public static let maximumDateSpan: TimeInterval = 366 * 24 * 60 * 60
  /// Largest number of day sections accepted in one snapshot.
  public static let maximumSectionDayCount = 366
  /// Largest number of values accepted by one calendar filter list.
  public static let maximumFilterValueCount = 128
  /// Largest one calendar filter token.
  public static let maximumFilterValueLength = 512
  /// Largest client-generated request correlation identifier.
  public static let maximumRequestIDLength = 128
  /// Largest user-visible query label.
  public static let maximumQueryTextLength = 512
  /// Largest date-format string accepted by the protocol.
  public static let maximumDateFormatLength = 128
  /// Largest event title accepted by a mutation.
  public static let maximumEventTitleLength = 1_024
  /// Largest event location accepted by a mutation.
  public static let maximumEventLocationLength = 4_096
  /// Largest calendar or event identifier accepted by a mutation.
  public static let maximumIdentifierLength = 4_096
  /// Largest number of alarms accepted by one mutation.
  public static let maximumAlertCount = 32
  /// Largest supported alert lead time.
  public static let maximumAlertOffset: TimeInterval = 366 * 24 * 60 * 60
  /// Largest supported travel duration.
  public static let maximumTravelTime: TimeInterval = 7 * 24 * 60 * 60
}

/// One calendar request rejected before it reaches EventKit.
public enum CalendarAgentRequestValidationError: LocalizedError, Equatable, Sendable {
  case invalidDateRange
  case dateRangeTooLarge
  case incompleteSectionRange
  case invalidSectionDayCount
  case textTooLong(field: String, maximum: Int)
  case tooManyValues(field: String, maximum: Int)
  case invalidNumber(field: String)
  case valueOutOfRange(field: String)

  public var errorDescription: String? {
    switch self {
    case .invalidDateRange:
      return "The calendar date range must be finite and end after it starts."
    case .dateRangeTooLarge:
      return "The calendar date range exceeds the supported maximum."
    case .incompleteSectionRange:
      return "Calendar sectionStartDate and sectionDayCount must be supplied together."
    case .invalidSectionDayCount:
      return "Calendar sectionDayCount is outside the supported range."
    case .textTooLong(let field, let maximum):
      return "Calendar field '\(field)' exceeds \(maximum) characters."
    case .tooManyValues(let field, let maximum):
      return "Calendar field '\(field)' exceeds \(maximum) values."
    case .invalidNumber(let field):
      return "Calendar field '\(field)' must be finite."
    case .valueOutOfRange(let field):
      return "Calendar field '\(field)' is outside the supported range."
    }
  }
}

/// Validates calendar requests at the process boundary.
public enum CalendarAgentRequestValidator {
  /// Validates only the payload selected by one wire-level command.
  public static func validate(_ request: CalendarAgentRequest) throws {
    if let requestID = request.requestID {
      let trimmed = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty,
        requestID.utf8.count <= CalendarAgentRequestLimits.maximumRequestIDLength,
        !requestID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      else {
        throw CalendarAgentRequestValidationError.valueOutOfRange(field: "requestID")
      }
    }

    switch request.command {
    case .fetch, .subscribe:
      if let query = request.query {
        try validate(query)
      }
    case .createEvent:
      if let draft = request.createEvent {
        try validate(draft)
      }
    case .updateEvent:
      if let draft = request.updateEvent {
        try validate(draft)
      }
    case .deleteEvent:
      if let draft = request.deleteEvent {
        try validate(draft)
      }
    case .ping, .version, .logs, .restart:
      break
    }
  }

  /// Validates one fetch or subscription query.
  public static func validate(_ query: CalendarAgentQuery) throws {
    try validateDateRange(start: query.startDate, end: query.endDate)

    switch (query.sectionStartDate, query.sectionDayCount) {
    case (nil, nil):
      break
    case (let start?, let count?):
      guard isFinite(start) else {
        throw CalendarAgentRequestValidationError.invalidDateRange
      }
      guard (1...CalendarAgentRequestLimits.maximumSectionDayCount).contains(count) else {
        throw CalendarAgentRequestValidationError.invalidSectionDayCount
      }
    default:
      throw CalendarAgentRequestValidationError.incompleteSectionRange
    }

    try validateText(query.emptyText, field: "emptyText")
    try validateText(query.todayTitle, field: "todayTitle")
    try validateText(query.tomorrowTitle, field: "tomorrowTitle")
    try validateText(query.allDayLabel, field: "allDayLabel")
    try validateText(query.birthdaysTitle, field: "birthdaysTitle")
    try validateText(
      query.birthdaysDateFormat,
      field: "birthdaysDateFormat",
      maximum: CalendarAgentRequestLimits.maximumDateFormatLength
    )

    try validateFilter(query.includedCalendarNames, field: "includedCalendarNames")
    try validateFilter(query.excludedCalendarNames, field: "excludedCalendarNames")
    try validateFilter(query.includedCalendarSourceNames, field: "includedCalendarSourceNames")
    try validateFilter(query.excludedCalendarSourceNames, field: "excludedCalendarSourceNames")
    try validateFilter(query.includedCalendarIDs, field: "includedCalendarIDs")
    try validateFilter(query.excludedCalendarIDs, field: "excludedCalendarIDs")
    try validateFilter(query.includedCalendarSourceIDs, field: "includedCalendarSourceIDs")
    try validateFilter(query.excludedCalendarSourceIDs, field: "excludedCalendarSourceIDs")
  }

  /// Validates one create-event request.
  public static func validate(_ draft: CalendarAgentCreateEvent) throws {
    try validateMutation(
      title: draft.title,
      startDate: draft.startDate,
      endDate: draft.endDate,
      calendarID: draft.calendarID,
      location: draft.location,
      alertOffsetsSeconds: draft.alertOffsetsSeconds,
      travelTimeSeconds: draft.travelTimeSeconds
    )
  }

  /// Validates one update-event request.
  public static func validate(_ draft: CalendarAgentUpdateEvent) throws {
    try validateIdentifier(draft.eventIdentifier, field: "eventIdentifier")
    try validateMutation(
      title: draft.title,
      startDate: draft.startDate,
      endDate: draft.endDate,
      calendarID: draft.calendarID,
      location: draft.location,
      alertOffsetsSeconds: draft.alertOffsetsSeconds,
      travelTimeSeconds: draft.travelTimeSeconds
    )
  }

  /// Validates one delete-event request.
  public static func validate(_ draft: CalendarAgentDeleteEvent) throws {
    try validateIdentifier(draft.eventIdentifier, field: "eventIdentifier")
  }

  /// Validates one finite, forward, bounded date range.
  private static func validateDateRange(start: Date, end: Date) throws {
    guard isFinite(start), isFinite(end), start < end else {
      throw CalendarAgentRequestValidationError.invalidDateRange
    }

    guard end.timeIntervalSince(start) <= CalendarAgentRequestLimits.maximumDateSpan else {
      throw CalendarAgentRequestValidationError.dateRangeTooLarge
    }
  }

  /// Validates fields shared by create and update requests.
  private static func validateMutation(
    title: String,
    startDate: Date,
    endDate: Date,
    calendarID: String?,
    location: String?,
    alertOffsetsSeconds: [TimeInterval],
    travelTimeSeconds: TimeInterval?
  ) throws {
    try validateDateRange(start: startDate, end: endDate)
    try validateText(
      title,
      field: "title",
      maximum: CalendarAgentRequestLimits.maximumEventTitleLength
    )

    if let calendarID {
      try validateIdentifier(calendarID, field: "calendarID")
    }
    if let location {
      try validateText(
        location,
        field: "location",
        maximum: CalendarAgentRequestLimits.maximumEventLocationLength
      )
    }

    guard alertOffsetsSeconds.count <= CalendarAgentRequestLimits.maximumAlertCount else {
      throw CalendarAgentRequestValidationError.tooManyValues(
        field: "alertOffsetsSeconds",
        maximum: CalendarAgentRequestLimits.maximumAlertCount
      )
    }

    for value in alertOffsetsSeconds {
      guard value.isFinite else {
        throw CalendarAgentRequestValidationError.invalidNumber(field: "alertOffsetsSeconds")
      }
      guard value >= 0, value <= CalendarAgentRequestLimits.maximumAlertOffset else {
        throw CalendarAgentRequestValidationError.valueOutOfRange(field: "alertOffsetsSeconds")
      }
    }

    if let travelTimeSeconds {
      guard travelTimeSeconds.isFinite else {
        throw CalendarAgentRequestValidationError.invalidNumber(field: "travelTimeSeconds")
      }
      guard
        travelTimeSeconds >= 0,
        travelTimeSeconds <= CalendarAgentRequestLimits.maximumTravelTime
      else {
        throw CalendarAgentRequestValidationError.valueOutOfRange(field: "travelTimeSeconds")
      }
    }
  }

  /// Validates one protocol identifier.
  private static func validateIdentifier(_ value: String, field: String) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw CalendarAgentRequestValidationError.valueOutOfRange(field: field)
    }
    try validateText(
      value,
      field: field,
      maximum: CalendarAgentRequestLimits.maximumIdentifierLength
    )
  }

  /// Validates one bounded text field.
  private static func validateText(
    _ value: String,
    field: String,
    maximum: Int = CalendarAgentRequestLimits.maximumQueryTextLength
  ) throws {
    guard value.count <= maximum else {
      throw CalendarAgentRequestValidationError.textTooLong(field: field, maximum: maximum)
    }
  }

  /// Validates one bounded filter list and every token in it.
  private static func validateFilter(_ values: [String], field: String) throws {
    guard values.count <= CalendarAgentRequestLimits.maximumFilterValueCount else {
      throw CalendarAgentRequestValidationError.tooManyValues(
        field: field,
        maximum: CalendarAgentRequestLimits.maximumFilterValueCount
      )
    }

    for value in values {
      try validateText(
        value,
        field: field,
        maximum: CalendarAgentRequestLimits.maximumFilterValueLength
      )
    }
  }

  /// Returns whether one Foundation date carries a finite representation.
  private static func isFinite(_ date: Date) -> Bool {
    date.timeIntervalSinceReferenceDate.isFinite
  }
}
