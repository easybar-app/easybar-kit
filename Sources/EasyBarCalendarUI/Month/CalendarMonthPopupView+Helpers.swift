import EasyBarCalendarPresentation
import EasyBarShared
import SwiftUI

// MARK: - Logging And Helpers

extension CalendarMonthPopupView {
  /// Returns the calendar resolved for month popup rendering.
  var resolvedCalendar: Calendar {
    var resolved = calendar

    if let firstWeekday = config.firstWeekday {
      resolved.firstWeekday = firstWeekday
    }

    return resolved
  }

  /// Keeps the selection inside the current visible month on first show.
  func syncSelectionIntoVisibleMonth() {
    if !resolvedCalendar.isDate(selectedStartDate, equalTo: visibleMonth, toGranularity: .month) {
      selectedStartDate = visibleMonth
      selectedEndDate = visibleMonth
    }
  }

  /// Opens the host-provided event composer for a new appointment.
  func openComposer() {
    openComposer(on: min(selectedStartDate, selectedEndDate))
  }

  /// Opens the host-provided event composer for a new appointment on one date.
  func openComposer(on date: Date) {
    let defaultDate = resolvedCalendar.startOfDay(for: date)
    onCreateEvent(defaultDate) {
      refreshCalendarViews()
    }
  }

  /// Opens the host-provided event composer for one existing appointment.
  func openComposer(for event: CalendarAgentEvent) {
    onEditEvent(event) {
      refreshCalendarViews()
    }
  }

  /// Refreshes calendar-backed views after a create, update, or delete.
  func refreshCalendarViews() {
    onRefreshRequested()
  }

  /// Returns the best matching selection date inside one target month.
  func matchingSelectionDate(in targetMonth: Date) -> Date {
    let targetMonthStart = Self.startOfMonth(targetMonth, calendar: resolvedCalendar)
    let selectedDay = resolvedCalendar.component(.day, from: selectedStartDate)

    guard
      let dayRange = resolvedCalendar.range(of: .day, in: .month, for: targetMonthStart),
      let matchedDate = resolvedCalendar.date(
        byAdding: .day,
        value: max(0, min(selectedDay, dayRange.count) - 1),
        to: targetMonthStart
      )
    else {
      return targetMonthStart
    }

    return matchedDate
  }

  /// Opens the year picker around the current visible year.
  func openYearPicker() {
    yearPickerPageStart = centeredYearPageStart(for: visibleYear)
    isYearPickerPresented = true
  }

  /// Returns the visible month year.
  var visibleYear: Int {
    return resolvedCalendar.component(.year, from: visibleMonth)
  }

  /// Returns the visible month title including year.
  var visibleMonthTitle: String {
    return Self.formatVisibleMonthTitle(
      visibleMonth,
      calendar: resolvedCalendar,
      locale: .autoupdatingCurrent
    )
  }

  /// Moves the year picker one page backward.
  func showPreviousYearPage() {
    yearPickerPageStart -= 12
  }

  /// Moves the year picker one page forward.
  func showNextYearPage() {
    yearPickerPageStart += 12
  }

  /// Selects one year while keeping the current visible month when possible.
  func selectYear(_ year: Int) {
    let month = resolvedCalendar.component(.month, from: visibleMonth)
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1

    let targetMonth =
      resolvedCalendar.date(from: components)
      ?? Self.startOfMonth(visibleMonth, calendar: resolvedCalendar)
    let targetSelectionDate = matchingSelectionDate(in: targetMonth)

    visibleMonth = targetMonth
    selectedStartDate = targetSelectionDate
    selectedEndDate = targetSelectionDate
    shouldAutoSelectVisibleMonthEvent = true
    isYearPickerPresented = false

    logger.debug(
      "month calendar popup select_year",
      .field("year", "\(year)"),
      .field("visible_month", "\(debugDate(visibleMonth))"),
    )
  }

  /// Returns the centered twelve-year page start for one year.
  func centeredYearPageStart(for year: Int) -> Int {
    return max(year - 5, 1)
  }

  /// Selects the first visible event day after a month jump when the current day is empty.
  func resolveVisibleMonthAutoSelection() {
    guard shouldAutoSelectVisibleMonthEvent else { return }
    defer { shouldAutoSelectVisibleMonthEvent = false }

    if !selectedEvents.isEmpty {
      return
    }

    guard
      let visibleMonthRange = resolvedCalendar.dateInterval(of: .month, for: visibleMonth)
    else {
      return
    }

    let visibleMonthEvents = store.events.filter { event in
      event.startDate < visibleMonthRange.end && event.endDate > visibleMonthRange.start
    }
    .sorted { lhs, rhs in
      if lhs.startDate != rhs.startDate {
        return lhs.startDate < rhs.startDate
      }

      return lhs.endDate < rhs.endDate
    }

    guard let firstEvent = visibleMonthEvents.first else { return }

    let eventDay = resolvedCalendar.startOfDay(for: firstEvent.startDate)
    selectedStartDate = eventDay
    selectedEndDate = eventDay
  }

  /// Resolves one normalized day from the recorded day-cell frames.
  func resolvedDay(at location: CGPoint) -> Date? {
    for (date, frame) in dayCellFrames {
      if frame.contains(location) {
        return resolvedCalendar.startOfDay(for: date)
      }
    }

    return nil
  }

  /// Logs the current selection.
  func logSelection(_ reason: String) {
    logger.debug(
      "month calendar popup selection",
      .field("reason", "\(reason)"),
      .field("start", "\(debugDate(selectedStartDate))"),
      .field("end", "\(debugDate(selectedEndDate))"),
    )
  }

  /// Logs the appointments resolved for the current selection.
  func logResolvedAppointments(_ reason: String) {
    logger.debug(
      "month calendar popup appointments",
      .field("reason", "\(reason)"),
      .field("count", "\(selectedEvents.count)"),
    )
  }

  /// Returns the first day of one month.
  static func startOfMonth(_ date: Date, calendar: Calendar = Calendar.current) -> Date {
    CalendarMonthRangeBuilder.startOfMonth(date, calendar: calendar)
  }

  /// Formats one visible month title using the provided locale.
  static func formatVisibleMonthTitle(
    _ date: Date,
    calendar: Calendar,
    locale: Locale
  ) -> String {
    CalendarDateFormatter.localizedString(
      from: date,
      calendar: calendar,
      locale: locale,
      template: "LLLL yyyy"
    )
  }

  /// Formats one debug date.
  func debugDate(_ date: Date) -> String {
    CalendarDateFormatter.iso8601String(from: date)
  }
}
