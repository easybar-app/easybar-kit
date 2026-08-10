import Combine
import EasyBarCalendarPresentation
import EasyBarCalendarUI
import EasyBarShared
import Foundation

/// Shared month-calendar snapshot store used by the native month popup.
@MainActor
final class NativeMonthCalendarStore: CalendarMonthPopupStore {
  @Published private(set) var snapshot: EasyBarShared.CalendarAgentSnapshot?
  @Published private(set) var events: [EasyBarShared.CalendarAgentEvent] = []

  private var subscribedMonthRangeStart: Date?
  private var subscribedMonthRangeEnd: Date?
  private var focusedVisibleMonth: Date?
  private var subscribedMonthRadius: Int?
  private let debugDateFormatter = ISO8601DateFormatter()

  let logger: ProcessLogger

  init(
    logger: ProcessLogger
  ) {
    self.logger = logger
  }

  /// Applies one calendar snapshot to the shared store.
  func apply(snapshot: EasyBarShared.CalendarAgentSnapshot) {
    logger.debug(
      "month calendar popup applied snapshot",
      .field("access_granted", "\(snapshot.accessGranted)"),
      .field("permission_state", "\(snapshot.permissionState)"),
      .field("events", "\(snapshot.events.count)"),
      .field("sections", "\(snapshot.sections.count)"),
    )
    publish(snapshot: snapshot)
  }

  /// Clears the current calendar snapshot.
  func clear() {
    logger.debug("month calendar popup cleared")
    publish(snapshot: nil)
  }

  /// Returns all events overlapping the inclusive day range.
  func eventsInRange(from startDate: Date, to endDate: Date) -> [EasyBarShared.CalendarAgentEvent] {
    let calendar = Calendar.current
    let startOfRange = calendar.startOfDay(for: startDate)
    let endDayStart = calendar.startOfDay(for: endDate)

    guard let endOfRange = calendar.date(byAdding: .day, value: 1, to: endDayStart) else {
      return []
    }

    return events.filter { event in
      event.startDate < endOfRange && event.endDate > startOfRange
    }
  }

  /// Returns whether one day has at least one event.
  func hasEvents(on date: Date) -> Bool {
    return !eventsForDay(date).isEmpty
  }

  /// Prepares the subscribed month preload range for one visible month and radius.
  func prepareMonthSubscriptionRange(for visibleMonth: Date, radius: Int, calendar: Calendar)
    -> Bool
  {
    let startOfVisibleMonth = CalendarMonthRangeBuilder.startOfMonth(
      visibleMonth, calendar: calendar)
    let maximumSafeRadius = CalendarMonthRangeBuilder.maximumSafeSubscriptionRadius(
      for: startOfVisibleMonth,
      calendar: calendar
    )
    let normalizedRadius = min(max(radius, 0), maximumSafeRadius)
    let preparedRange = CalendarMonthRangeBuilder.subscriptionRange(
      for: startOfVisibleMonth,
      radius: normalizedRadius,
      calendar: calendar
    )

    guard let preparedRange else { return false }

    let changed =
      subscribedMonthRangeStart != preparedRange.start
      || subscribedMonthRangeEnd != preparedRange.end
      || focusedVisibleMonth != startOfVisibleMonth
      || subscribedMonthRadius != normalizedRadius

    if changed {
      subscribedMonthRangeStart = preparedRange.start
      subscribedMonthRangeEnd = preparedRange.end
      focusedVisibleMonth = startOfVisibleMonth
      subscribedMonthRadius = normalizedRadius

      logger.debug(
        "month calendar store prepared subscription range",
        .field("month", "\(debugDate(startOfVisibleMonth))"),
        .field("radius", "\(normalizedRadius)"),
        .field("start", "\(debugDate(preparedRange.start))"),
        .field("end", "\(debugDate(preparedRange.end))"),
      )
    }

    return changed
  }

  /// Returns the currently prepared month preload range.
  func monthSubscriptionRange() -> (start: Date, end: Date)? {
    guard let subscribedMonthRangeStart, let subscribedMonthRangeEnd else { return nil }
    return (start: subscribedMonthRangeStart, end: subscribedMonthRangeEnd)
  }

  /// Publishes one calendar snapshot update.
  private func publish(snapshot: EasyBarShared.CalendarAgentSnapshot?) {
    self.snapshot = snapshot
    events = snapshot?.events ?? []

    logger.debug(
      "month calendar store published",
      .field("snapshot_present", "\(snapshot != nil)"),
      .field("events", "\(events.count)"),
    )
  }

  /// Formats one debug date string.
  private func debugDate(_ date: Date) -> String {
    return debugDateFormatter.string(from: date)
  }
}
