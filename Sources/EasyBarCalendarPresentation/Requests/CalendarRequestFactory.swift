import EasyBarShared
import Foundation

/// Calendar filters shared across calendar clients.
public struct CalendarRequestFilters: Equatable, Sendable {
  /// Optional visible calendar-title allowlist.
  public let includedCalendarNames: [String]
  /// Optional visible calendar-title denylist.
  public let excludedCalendarNames: [String]
  /// Optional human-readable calendar-source-title allowlist.
  public let includedCalendarSourceNames: [String]
  /// Optional human-readable calendar-source-title denylist.
  public let excludedCalendarSourceNames: [String]
  /// Optional advanced calendar-identifier allowlist.
  public let includedCalendarIDs: [String]
  /// Optional advanced calendar-identifier denylist.
  public let excludedCalendarIDs: [String]
  /// Optional advanced calendar-source-identifier allowlist.
  public let includedCalendarSourceIDs: [String]
  /// Optional advanced calendar-source-identifier denylist.
  public let excludedCalendarSourceIDs: [String]

  public init(
    includedCalendarNames: [String] = [],
    excludedCalendarNames: [String] = [],
    includedCalendarSourceNames: [String] = [],
    excludedCalendarSourceNames: [String] = [],
    includedCalendarIDs: [String] = [],
    excludedCalendarIDs: [String] = [],
    includedCalendarSourceIDs: [String] = [],
    excludedCalendarSourceIDs: [String] = []
  ) {
    self.includedCalendarNames = includedCalendarNames
    self.excludedCalendarNames = excludedCalendarNames
    self.includedCalendarSourceNames = includedCalendarSourceNames
    self.excludedCalendarSourceNames = excludedCalendarSourceNames
    self.includedCalendarIDs = includedCalendarIDs
    self.excludedCalendarIDs = excludedCalendarIDs
    self.includedCalendarSourceIDs = includedCalendarSourceIDs
    self.excludedCalendarSourceIDs = excludedCalendarSourceIDs
  }
}

/// Birthday-related request options shared across calendar clients.
public struct CalendarBirthdayRequestOptions: Equatable, Sendable {
  public let showBirthdays: Bool
  public let showAge: Bool

  public init(showBirthdays: Bool, showAge: Bool) {
    self.showBirthdays = showBirthdays
    self.showAge = showAge
  }
}

/// Options used to build one upcoming-calendar request.
public struct CalendarUpcomingRequestOptions: Equatable, Sendable {
  public let dayCount: Int
  public let emptyText: String
  public let allDayLabel: String
  public let birthdaysDateFormat: String
  public let birthdaysTitle: String
  public let birthdays: CalendarBirthdayRequestOptions
  public let filters: CalendarRequestFilters

  public init(
    dayCount: Int,
    emptyText: String,
    allDayLabel: String = "All day",
    birthdaysDateFormat: String = "dd.MM.yyyy",
    birthdaysTitle: String = "",
    birthdays: CalendarBirthdayRequestOptions,
    filters: CalendarRequestFilters
  ) {
    self.dayCount = dayCount
    self.emptyText = emptyText
    self.allDayLabel = allDayLabel
    self.birthdaysDateFormat = birthdaysDateFormat
    self.birthdaysTitle = birthdaysTitle
    self.birthdays = birthdays
    self.filters = filters
  }
}

/// Options used to build one month-calendar request.
public struct CalendarMonthRequestOptions: Equatable, Sendable {
  public let emptyText: String
  public let allDayLabel: String
  public let birthdaysDateFormat: String
  public let birthdaysTitle: String
  public let birthdays: CalendarBirthdayRequestOptions
  public let filters: CalendarRequestFilters

  public init(
    emptyText: String,
    allDayLabel: String = "All day",
    birthdaysDateFormat: String = "dd.MM.yyyy",
    birthdaysTitle: String = "",
    birthdays: CalendarBirthdayRequestOptions,
    filters: CalendarRequestFilters
  ) {
    self.emptyText = emptyText
    self.allDayLabel = allDayLabel
    self.birthdaysDateFormat = birthdaysDateFormat
    self.birthdaysTitle = birthdaysTitle
    self.birthdays = birthdays
    self.filters = filters
  }
}

/// Builds stable calendar-agent requests from reusable inputs.
public enum CalendarRequestFactory {
  /// Returns the fetch range required by the upcoming popup.
  public static func requestedUpcomingDateRange(
    now: Date,
    dayCount: Int,
    calendar: Calendar = .current
  ) -> DateInterval {
    let start = calendar.startOfDay(for: now)
    let normalizedDayCount = min(
      max(1, dayCount),
      CalendarAgentRequestLimits.maximumSectionDayCount
    )
    let end =
      calendar.date(byAdding: .day, value: normalizedDayCount, to: start)
      ?? now.addingTimeInterval(TimeInterval(normalizedDayCount * 86_400))

    return DateInterval(start: start, end: end)
  }

  /// Builds one upcoming-calendar subscribe request.
  public static func makeUpcomingSubscribeRequest(
    now: Date,
    options: CalendarUpcomingRequestOptions,
    calendar: Calendar = .current
  ) -> CalendarAgentRequest {
    let requestedRange = requestedUpcomingDateRange(
      now: now,
      dayCount: options.dayCount,
      calendar: calendar
    )

    return CalendarAgentRequest(
      command: .subscribe,
      query: CalendarAgentQuery(
        startDate: requestedRange.start,
        endDate: requestedRange.end,
        sectionStartDate: nil,
        sectionDayCount: nil,
        showBirthdays: options.birthdays.showBirthdays,
        emptyText: options.emptyText,
        allDayLabel: options.allDayLabel,
        birthdaysTitle: options.birthdaysTitle,
        birthdaysDateFormat: options.birthdaysDateFormat,
        birthdaysShowAge: options.birthdays.showAge,
        includedCalendarNames: options.filters.includedCalendarNames,
        excludedCalendarNames: options.filters.excludedCalendarNames,
        includedCalendarSourceNames: options.filters.includedCalendarSourceNames,
        excludedCalendarSourceNames: options.filters.excludedCalendarSourceNames,
        includedCalendarIDs: options.filters.includedCalendarIDs,
        excludedCalendarIDs: options.filters.excludedCalendarIDs,
        includedCalendarSourceIDs: options.filters.includedCalendarSourceIDs,
        excludedCalendarSourceIDs: options.filters.excludedCalendarSourceIDs
      )
    )
  }

  /// Builds one month-calendar subscribe request for an already prepared date range.
  public static func makeMonthSubscribeRequest(
    range: DateInterval,
    options: CalendarMonthRequestOptions
  ) -> CalendarAgentRequest {
    CalendarAgentRequest(
      command: .subscribe,
      query: CalendarAgentQuery(
        startDate: range.start,
        endDate: range.end,
        sectionStartDate: nil,
        sectionDayCount: nil,
        showBirthdays: options.birthdays.showBirthdays,
        emptyText: options.emptyText,
        allDayLabel: options.allDayLabel,
        birthdaysTitle: options.birthdaysTitle,
        birthdaysDateFormat: options.birthdaysDateFormat,
        birthdaysShowAge: options.birthdays.showAge,
        includedCalendarNames: options.filters.includedCalendarNames,
        excludedCalendarNames: options.filters.excludedCalendarNames,
        includedCalendarSourceNames: options.filters.includedCalendarSourceNames,
        excludedCalendarSourceNames: options.filters.excludedCalendarSourceNames,
        includedCalendarIDs: options.filters.includedCalendarIDs,
        excludedCalendarIDs: options.filters.excludedCalendarIDs,
        includedCalendarSourceIDs: options.filters.includedCalendarSourceIDs,
        excludedCalendarSourceIDs: options.filters.excludedCalendarSourceIDs
      )
    )
  }
}
