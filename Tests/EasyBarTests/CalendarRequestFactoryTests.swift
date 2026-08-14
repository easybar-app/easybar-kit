import EasyBarCalendarPresentation
import EasyBarShared
import XCTest

final class CalendarRequestFactoryTests: XCTestCase {
  func testRequestedUpcomingDateRangeClampsExtremeDayCounts() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    let range = CalendarRequestFactory.requestedUpcomingDateRange(
      now: now,
      dayCount: .max,
      calendar: calendar
    )

    XCTAssertEqual(range.start, calendar.startOfDay(for: now))
    XCTAssertLessThanOrEqual(range.duration, CalendarAgentRequestLimits.maximumDateSpan)
  }
}
