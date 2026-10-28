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
    let birthdayEvents = makeBirthdayEvents(
      query: query,
      start: fetchStart,
      end: fetchEndExclusive
    )
    let regularEvents = makeRegularEvents(
      query: query,
      start: fetchStart,
      end: fetchEndExclusive
    )
    let result = birthdayEvents + regularEvents

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

  /// Builds regular event rows using the calendars allowed by the current query.
  private func makeRegularEvents(
    query: CalendarAgentQuery,
    start: Date,
    end: Date
  ) -> [CalendarAgentEvent] {
    makeEvents(query: query, start: start, end: end, birthdayOnly: false)
  }

  /// Builds birthday rows only when birthdays are enabled for the current query.
  private func makeBirthdayEvents(
    query: CalendarAgentQuery,
    start: Date,
    end: Date
  ) -> [CalendarAgentEvent] {
    guard query.showBirthdays else { return [] }
    return makeEvents(query: query, start: start, end: end, birthdayOnly: true)
  }

  /// Fetches events only when at least one eligible calendar remains after filtering.
  private func makeEvents(
    query: CalendarAgentQuery,
    start: Date,
    end: Date,
    birthdayOnly: Bool
  ) -> [CalendarAgentEvent] {
    let calendars = filteredCalendars(query: query, birthdayOnly: birthdayOnly)
    guard !calendars.isEmpty else { return [] }

    let predicate = eventStore.predicateForEvents(
      withStart: start,
      end: end,
      calendars: calendars
    )

    return eventStore.events(matching: predicate).map { event in
      makeNormalizedEvent(event, birthdayOnly: birthdayOnly, showBirthdayAge: query.birthdaysShowAge)
    }
  }

  /// Converts one EventKit event into the shared transport model with consistent metadata.
  private func makeNormalizedEvent(
    _ event: EKEvent,
    birthdayOnly: Bool,
    showBirthdayAge: Bool
  ) -> CalendarAgentEvent {
    let eventIdentifier = normalizedOptionalText(event.eventIdentifier)
    let location = normalizedOptionalText(event.location)
    let title = normalizedTitle(event.title)
    let displayTitle =
      birthdayOnly
      ? CalendarEventNormalization.birthdayTitle(title, showAge: showBirthdayAge)
      : title
    let isAllDay = birthdayOnly || event.isAllDay
    let prefix = birthdayOnly ? "birthday-" : "event-"

    let stableID = CalendarEventIdentity.makeID(
      prefix: prefix,
      eventIdentifier: eventIdentifier,
      calendarID: event.calendar.calendarIdentifier,
      sourceID: event.calendar.source.sourceIdentifier,
      title: displayTitle,
      startDate: event.startDate,
      endDate: event.endDate,
      isAllDay: isAllDay,
      location: location
    )
    let travelTimeSeconds = EventKitTravelTimeAdapter.read(from: event)
    let alertOffsetsSeconds = visibleAlertOffsetsSeconds(for: event)

    return CalendarAgentEvent(
      id: stableID,
      eventIdentifier: eventIdentifier,
      title: displayTitle,
      startDate: event.startDate,
      endDate: event.endDate,
      isAllDay: isAllDay,
      calendarID: event.calendar.calendarIdentifier,
      calendarName: normalizedTitle(event.calendar.title),
      calendarColorHex: colorHex(for: event.calendar.cgColor),
      location: location,
      url: normalizedEventURLText(for: event),
      alertOffsetsSeconds: alertOffsetsSeconds,
      isHoliday: isHolidayCalendar(event.calendar),
      hasAlert: !alertOffsetsSeconds.isEmpty,
      travelTimeSeconds: travelTimeSeconds
    )
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
            sourceTitle: calendar.source.title,
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
      includedSourceTitleTokens: query.includedCalendarSourceNames,
      excludedSourceTitleTokens: query.excludedCalendarSourceNames,
      includedCalendarIDTokens: query.includedCalendarIDs,
      excludedCalendarIDTokens: query.excludedCalendarIDs,
      includedSourceIDTokens: query.includedCalendarSourceIDs,
      excludedSourceIDTokens: query.excludedCalendarSourceIDs
    )
  }

  /// Resolves a writable calendar without silently replacing an explicit user selection.
  func resolvedCalendar(id: String?) throws -> EKCalendar {
    let writableCalendars = eventStore.calendars(for: .event).filter { calendar in
      calendar.allowsContentModifications && calendar.type != .birthday
    }

    return try Self.selectWritableCalendar(
      requestedID: normalizedOptionalText(id),
      available: writableCalendars,
      preferred: eventStore.defaultCalendarForNewEvents
    )
  }

  /// Chooses the requested calendar or uses defaults only when no calendar was selected.
  static func selectWritableCalendar(
    requestedID: String?,
    available: [EKCalendar],
    preferred: EKCalendar?
  ) throws -> EKCalendar {
    if let requestedID {
      guard let selected = available.first(where: { $0.calendarIdentifier == requestedID }) else {
        throw CalendarAgentMutationError.calendarNotFound
      }
      return selected
    }

    if let preferred, preferred.allowsContentModifications, preferred.type != .birthday {
      return preferred
    }

    guard let firstWritable = available.first else {
      throw CalendarAgentMutationError.noWritableCalendar
    }
    return firstWritable
  }

  /// Resolves one event by EventKit identifier.
  func resolvedEvent(id: String) -> EKEvent? {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    return eventStore.event(withIdentifier: trimmed)
  }

  /// Returns visible non-travel alert lead times.
  private func visibleAlertOffsetsSeconds(for event: EKEvent) -> [TimeInterval] {
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

  /// Returns the formatted end time.
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
