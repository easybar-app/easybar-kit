import EasyBarShared
import Foundation

/// Shared helpers for month-calendar date windows used by hosts and stores.
public enum CalendarMonthRangeBuilder {
  /// Returns the first day of the month containing the provided date.
  public static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
    let components = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: components) ?? calendar.startOfDay(for: date)
  }

  /// Returns the exact visible grid range for one displayed month.
  public static func visibleGridRange(for visibleMonth: Date, calendar: Calendar) -> DateInterval? {
    let monthStart = startOfMonth(visibleMonth, calendar: calendar)

    guard
      let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart),
      let monthInterval = calendar.dateInterval(of: .month, for: monthStart),
      let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start),
      let lastVisibleDay = calendar.date(byAdding: .day, value: -1, to: monthEnd),
      let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastVisibleDay)
    else {
      return nil
    }

    return DateInterval(
      start: calendar.startOfDay(for: firstWeek.start),
      end: calendar.startOfDay(for: lastWeek.end)
    )
  }

  /// Returns the largest whole-month preload radius accepted by the calendar agent.
  public static func maximumSafeSubscriptionRadius(
    for visibleMonth: Date,
    calendar: Calendar,
    maximumSpan: TimeInterval = CalendarAgentRequestLimits.maximumDateSpan
  ) -> Int {
    guard maximumSpan.isFinite, maximumSpan > 0 else { return 0 }

    var radius = 0

    while true {
      let (nextRadius, overflow) = radius.addingReportingOverflow(1)
      guard !overflow,
        let candidate = subscriptionRange(
          for: visibleMonth,
          radius: nextRadius,
          calendar: calendar
        ),
        candidate.duration <= maximumSpan
      else {
        break
      }
      radius = nextRadius
    }

    return radius
  }

  /// Returns the requested subscription range for one visible month and preload radius.
  public static func subscriptionRange(
    for visibleMonth: Date,
    radius: Int,
    calendar: Calendar
  ) -> DateInterval? {
    let monthStart = startOfMonth(visibleMonth, calendar: calendar)
    let normalizedRadius = max(radius, 0)

    if normalizedRadius == 0 {
      return visibleGridRange(for: monthStart, calendar: calendar)
    }

    let (afterEndOffset, overflow) = normalizedRadius.addingReportingOverflow(1)
    guard !overflow,
      let start = calendar.date(
        byAdding: .month,
        value: -normalizedRadius,
        to: monthStart
      ),
      let afterEndMonth = calendar.date(
        byAdding: .month,
        value: afterEndOffset,
        to: monthStart
      )
    else {
      return nil
    }

    return DateInterval(
      start: calendar.startOfDay(for: start),
      end: calendar.startOfDay(for: afterEndMonth)
    )
  }
}
