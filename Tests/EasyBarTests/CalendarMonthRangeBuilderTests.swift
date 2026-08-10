import EasyBarShared
import XCTest

@testable import EasyBarCalendarPresentation
@testable import EasyBarKit

final class CalendarMonthRangeBuilderTests: XCTestCase {
  func testVisibleGridRangeStartsAtWeekBoundaryAndEndsAfterLastVisibleWeek() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    calendar.firstWeekday = 2

    let visibleMonth = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
    let range = CalendarMonthRangeBuilder.visibleGridRange(for: visibleMonth, calendar: calendar)

    XCTAssertEqual(
      range?.start,
      calendar.date(from: DateComponents(year: 2026, month: 4, day: 27))
    )
    XCTAssertEqual(
      range?.end,
      calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))
    )
  }

  func testSubscriptionRangeExpandsWholeMonthsForRadius() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

    let visibleMonth = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15))!
    let range = CalendarMonthRangeBuilder.subscriptionRange(
      for: visibleMonth,
      radius: 2,
      calendar: calendar
    )

    XCTAssertEqual(
      range?.start,
      calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))
    )
    XCTAssertEqual(
      range?.end,
      calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))
    )
  }

  func testMaximumSafeSubscriptionRadiusUsesSharedAgentLimit() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

    let visibleMonth = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15))!
    let radius = CalendarMonthRangeBuilder.maximumSafeSubscriptionRadius(
      for: visibleMonth,
      calendar: calendar
    )
    let safeRange = try XCTUnwrap(
      CalendarMonthRangeBuilder.subscriptionRange(
        for: visibleMonth,
        radius: radius,
        calendar: calendar
      )
    )
    let nextRange = try XCTUnwrap(
      CalendarMonthRangeBuilder.subscriptionRange(
        for: visibleMonth,
        radius: radius + 1,
        calendar: calendar
      )
    )

    XCTAssertLessThanOrEqual(
      safeRange.duration,
      CalendarAgentRequestLimits.maximumDateSpan
    )
    XCTAssertGreaterThan(
      nextRange.duration,
      CalendarAgentRequestLimits.maximumDateSpan
    )
  }

  @MainActor
  func testMonthStoreClampsRequestedRadiusToSharedAgentLimit() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

    let visibleMonth = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15))!
    let store = NativeMonthCalendarStore(
      logger: ProcessLogger(
        label: "calendar.month-range.tests",
        minimumLevel: .error,
        outputStream: nil,
        errorStream: nil
      )
    )

    XCTAssertTrue(
      store.prepareMonthSubscriptionRange(
        for: visibleMonth,
        radius: 100,
        calendar: calendar
      )
    )

    let range = try XCTUnwrap(store.monthSubscriptionRange())
    XCTAssertLessThanOrEqual(
      range.end.timeIntervalSince(range.start),
      CalendarAgentRequestLimits.maximumDateSpan
    )
  }

}
