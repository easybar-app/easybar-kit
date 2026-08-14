import EasyBarShared
import EventKit
import Foundation

// MARK: - Event Building

extension CalendarSnapshotProvider {
  /// Builds normalized events for the requested fetch range.
  func makeNormalizedEvents(
    query: CalendarAgentQuery,
    fetchStart: Date,
    fetchEndExclusive: Date
  ) -> [CalendarAgentEvent] {
    var result: [CalendarAgentEvent] = []

    result.append(
      contentsOf: makeBirthdayEvents(
        query: query,
        start: fetchStart,
        end: fetchEndExclusive
      )
    )

    result.append(
      contentsOf: makeRegularEvents(
        query: query,
        start: fetchStart,
        end: fetchEndExclusive
      )
    )

    return result.sorted { lhs, rhs in
      if lhs.startDate != rhs.startDate {
        return lhs.startDate < rhs.startDate
      }

      if lhs.endDate != rhs.endDate {
        return lhs.endDate < rhs.endDate
      }

      return lhs.id < rhs.id
    }
  }

  /// Builds normalized regular calendar events.
  private func makeRegularEvents(
    query: CalendarAgentQuery,
    start: Date,
    end: Date
  ) -> [CalendarAgentEvent] {
    let normalCalendars = filteredRegularCalendars(query: query)
    let predicate = eventStore.predicateForEvents(
      withStart: start,
      end: end,
      calendars: normalCalendars
    )

    return eventStore.events(matching: predicate)
      .sorted { lhs, rhs in
        if lhs.startDate != rhs.startDate {
          return lhs.startDate < rhs.startDate
        }

        if lhs.endDate != rhs.endDate {
          return lhs.endDate < rhs.endDate
        }

        return (lhs.eventIdentifier ?? "") < (rhs.eventIdentifier ?? "")
      }
      .map { event in
        let eventIdentifier = normalizedOptionalText(event.eventIdentifier)
        let title = normalizedTitle(event.title)
        let location = normalizedOptionalText(event.location)
        let stableID = CalendarEventIdentity.makeID(
          prefix: "event-",
          eventIdentifier: eventIdentifier,
          calendarID: event.calendar.calendarIdentifier,
          sourceID: event.calendar.source.sourceIdentifier,
          title: title,
          startDate: event.startDate,
          endDate: event.endDate,
          isAllDay: event.isAllDay,
          location: location
        )
        let travelTimeSeconds = resolvedTravelTimeSeconds(for: event)
        let alertOffsetsSeconds = visibleAlertOffsetsSeconds(
          for: event,
          travelTimeSeconds: travelTimeSeconds
        )

        return CalendarAgentEvent(
          id: stableID,
          eventIdentifier: eventIdentifier,
          title: title,
          startDate: event.startDate,
          endDate: event.endDate,
          isAllDay: event.isAllDay,
          calendarID: event.calendar.calendarIdentifier,
          calendarName: normalizedTitle(event.calendar.title),
          calendarColorHex: colorHex(for: event.calendar.cgColor),
          location: location,
          url: normalizedEventURLText(for: event),
          alertOffsetsSeconds: alertOffsetsSeconds,
          isHoliday: isHolidayCalendar(event.calendar),
          hasAlert: hasVisibleAlert(alertOffsetsSeconds: alertOffsetsSeconds),
          travelTimeSeconds: travelTimeSeconds
        )
      }
  }

  /// Builds normalized birthday events when enabled.
  private func makeBirthdayEvents(
    query: CalendarAgentQuery,
    start: Date,
    end: Date
  ) -> [CalendarAgentEvent] {
    guard query.showBirthdays else { return [] }

    let birthdayCalendars = filteredCalendars(query: query, birthdayOnly: true)
    guard !birthdayCalendars.isEmpty else { return [] }

    let predicate = eventStore.predicateForEvents(
      withStart: start,
      end: end,
      calendars: birthdayCalendars
    )

    return eventStore.events(matching: predicate)
      .sorted { lhs, rhs in
        if lhs.startDate != rhs.startDate {
          return lhs.startDate < rhs.startDate
        }

        if lhs.endDate != rhs.endDate {
          return lhs.endDate < rhs.endDate
        }

        return (lhs.eventIdentifier ?? "") < (rhs.eventIdentifier ?? "")
      }
      .map { event in
        let eventIdentifier = normalizedOptionalText(event.eventIdentifier)
        let title = CalendarEventNormalization.birthdayTitle(
          normalizedTitle(event.title),
          showAge: query.birthdaysShowAge
        )
        let location = normalizedOptionalText(event.location)
        let stableID = CalendarEventIdentity.makeID(
          prefix: "birthday-",
          eventIdentifier: eventIdentifier,
          calendarID: event.calendar.calendarIdentifier,
          sourceID: event.calendar.source.sourceIdentifier,
          title: title,
          startDate: event.startDate,
          endDate: event.endDate,
          isAllDay: true,
          location: location
        )
        let travelTimeSeconds = resolvedTravelTimeSeconds(for: event)
        let alertOffsetsSeconds = visibleAlertOffsetsSeconds(
          for: event,
          travelTimeSeconds: travelTimeSeconds
        )

        return CalendarAgentEvent(
          id: stableID,
          eventIdentifier: eventIdentifier,
          title: title,
          startDate: event.startDate,
          endDate: event.endDate,
          isAllDay: true,
          calendarID: event.calendar.calendarIdentifier,
          calendarName: normalizedTitle(event.calendar.title),
          calendarColorHex: colorHex(for: event.calendar.cgColor),
          location: location,
          url: normalizedEventURLText(for: event),
          alertOffsetsSeconds: alertOffsetsSeconds,
          isHoliday: isHolidayCalendar(event.calendar),
          hasAlert: hasVisibleAlert(alertOffsetsSeconds: alertOffsetsSeconds),
          travelTimeSeconds: travelTimeSeconds
        )
      }
  }

  /// Returns writable non-birthday calendars for the composer.
  func writableCalendars() -> [CalendarAgentWritableCalendar] {
    eventStore.calendars(for: .event)
      .filter { $0.type != .birthday && $0.allowsContentModifications }
      .sorted { lhs, rhs in
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
      }
      .map { calendar in
        CalendarAgentWritableCalendar(
          id: calendar.calendarIdentifier,
          title: calendar.title
        )
      }
  }

  /// Returns the filtered non-birthday calendars for the query.
  private func filteredRegularCalendars(query: CalendarAgentQuery) -> [EKCalendar] {
    filteredCalendars(query: query, birthdayOnly: false)
  }

  /// Applies the same include/exclude contract to regular and birthday calendars.
  private func filteredCalendars(
    query: CalendarAgentQuery,
    birthdayOnly: Bool
  ) -> [EKCalendar] {
    eventStore.calendars(for: .event)
      .filter { birthdayOnly ? $0.type == .birthday : $0.type != .birthday }
      .filter { calendar in
        Self.calendarMatchesQuery(
          CalendarFilterTarget(
            title: calendar.title,
            identifier: calendar.calendarIdentifier,
            sourceIdentifier: calendar.source.sourceIdentifier
          ),
          query: query
        )
      }
  }

  /// Applies the query's include/exclude policy independently of calendar type.
  static func calendarMatchesQuery(
    _ target: CalendarFilterTarget,
    query: CalendarAgentQuery
  ) -> Bool {
    CalendarFilterMatcher.matches(
      target,
      includedTitleTokens: query.includedCalendarNames,
      excludedTitleTokens: query.excludedCalendarNames,
      includedCalendarIDTokens: query.includedCalendarIDs,
      excludedCalendarIDTokens: query.excludedCalendarIDs,
      includedSourceIDTokens: query.includedCalendarSourceIDs,
      excludedSourceIDTokens: query.excludedCalendarSourceIDs
    )
  }

  /// Resolves one writable calendar for creation or update.
  func resolvedCalendar(id: String?) throws -> EKCalendar {
    let writableCalendars = eventStore.calendars(for: .event).filter { calendar in
      calendar.allowsContentModifications && calendar.type != .birthday
    }

    if let id = normalizedOptionalText(id) {
      if let match = writableCalendars.first(where: {
        $0.calendarIdentifier == id
      }) {
        return match
      }
    }

    if let defaultCalendar = eventStore.defaultCalendarForNewEvents,
      defaultCalendar.allowsContentModifications,
      defaultCalendar.type != .birthday
    {
      return defaultCalendar
    }

    if let firstWritable = writableCalendars.first {
      return firstWritable
    }

    throw CalendarAgentMutationError.noWritableCalendar
  }

  /// Resolves one event by EventKit identifier.
  func resolvedEvent(id: String) -> EKEvent? {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    return eventStore.event(withIdentifier: trimmed)
  }

  /// Resolves travel time from the best available source.
  private func resolvedTravelTimeSeconds(for event: EKEvent) -> TimeInterval? {
    return EventKitTravelTimeAdapter.read(from: event)
  }

  /// Returns whether the event has at least one visible non-travel alert.
  private func hasVisibleAlert(alertOffsetsSeconds: [TimeInterval]) -> Bool {
    return !alertOffsetsSeconds.isEmpty
  }

  /// Returns visible non-travel alert lead times.
  private func visibleAlertOffsetsSeconds(
    for event: EKEvent,
    travelTimeSeconds _: TimeInterval?
  ) -> [TimeInterval] {
    guard let alarms = event.alarms, !alarms.isEmpty else { return [] }

    var relativeOffsets: [TimeInterval] = []
    var absoluteDates: [Date] = []
    for alarm in alarms {
      if let absoluteDate = alarm.absoluteDate {
        absoluteDates.append(absoluteDate)
      } else {
        relativeOffsets.append(alarm.relativeOffset)
      }
    }

    return CalendarEventNormalization.visibleAlertOffsetsSeconds(
      eventStartDate: event.startDate,
      relativeOffsets: relativeOffsets,
      absoluteDates: absoluteDates
    )
  }

  /// Returns whether one calendar should be treated as a holiday calendar.
  private func isHolidayCalendar(_ calendar: EKCalendar) -> Bool {
    CalendarEventNormalization.isHolidayCalendar(
      isSubscription: calendar.type == .subscription,
      titles: [calendar.title, calendar.source.title]
    )
  }
}

// MARK: - Formatting

extension CalendarSnapshotProvider {
  /// Normalizes one optional title into display text.
  func normalizedTitle(_ value: String?) -> String {
    guard let value else { return "Untitled" }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Untitled" : trimmed
  }

  /// Normalizes optional text and drops empty strings.
  func normalizedOptionalText(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Normalizes an optional URL into transport-safe text.
  func normalizedOptionalURLText(_ value: URL?) -> String? {
    normalizedOptionalText(value?.absoluteString)
  }

  /// Returns the best URL attached to one event.
  func normalizedEventURLText(for event: EKEvent) -> String? {
    if let directURL = normalizedOptionalURLText(event.url) {
      return directURL
    }

    return firstURLText(in: [event.location, event.notes])
  }

  /// Extracts the first URL from one of the provided text fields.
  func firstURLText(in values: [String?]) -> String? {
    guard let detector = Self.linkDetector else { return nil }

    for value in values {
      guard let text = normalizedOptionalText(value) else { continue }
      let range = NSRange(text.startIndex..<text.endIndex, in: text)
      let matches = Self.linkDetectorLock.withLock {
        detector.matches(in: text, options: [], range: range)
      }

      if let url = matches.first?.url?.absoluteString {
        return url
      }
    }

    return nil
  }

  /// Formats one event time for popup display.
  func formatEventTime(_ date: Date) -> String {
    Self.formatterLock.withLock { Self.eventTimeFormatter.string(from: date) }
  }

  /// Returns one rendered end time for timed events when it differs from the start.
  func formattedEndTime(
    startDate: Date,
    endDate: Date,
    isAllDay: Bool
  ) -> String? {
    guard
      CalendarEventNormalization.shouldShowEndTime(
        startDate: startDate,
        endDate: endDate,
        isAllDay: isAllDay,
        calendar: .current
      )
    else {
      return nil
    }
    return formatEventTime(endDate)
  }

  func formattedEndTime(for event: CalendarAgentEvent) -> String? {
    formattedEndTime(
      startDate: event.startDate,
      endDate: event.endDate,
      isAllDay: event.isAllDay
    )
  }

  /// Formats one day header for popup display.
  func formatDayTitle(_ date: Date) -> String {
    Self.formatterLock.withLock { Self.dayTitleFormatter.string(from: date) }
  }

  /// Formats one birthday date using the configured format.
  func formatBirthdayDate(_ date: Date, format: String) -> String {
    Self.birthdayFormatters.withLock { formatters in
      let formatter: DateFormatter
      if let cached = formatters[format] {
        formatter = cached
      } else {
        let created = Self.makeFormatter(format: format)
        formatters[format] = created
        formatter = created
      }
      return formatter.string(from: date)
    }
  }
}

// MARK: - Color Conversion

extension CalendarSnapshotProvider {
  /// Converts one calendar color into a hex string.
  private func colorHex(for cgColor: CGColor?) -> String? {
    guard let cgColor else { return nil }
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let color = cgColor.converted(
        to: colorSpace,
        intent: .defaultIntent,
        options: nil
      )
    else {
      return nil
    }

    guard let components = color.components else { return nil }
    let values: [CGFloat]

    if components.count >= 3 {
      values = components
    } else if components.count == 2 {
      values = [components[0], components[0], components[0], components[1]]
    } else {
      return nil
    }

    let red = Int(max(0, min(255, round(values[0] * 255))))
    let green = Int(max(0, min(255, round(values[1] * 255))))
    let blue = Int(max(0, min(255, round(values[2] * 255))))

    return String(format: "#%02X%02X%02X", red, green, blue)
  }
}
