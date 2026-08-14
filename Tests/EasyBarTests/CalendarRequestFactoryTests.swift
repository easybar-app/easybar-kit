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

  func testMonthRequestCarriesCalendarAndSourceFilters() throws {
    let filters = CalendarRequestFilters(
      includedCalendarNames: ["Work"],
      excludedCalendarNames: ["Holidays"],
      includedCalendarSourceNames: ["iCloud"],
      excludedCalendarSourceNames: ["Exchange"],
      includedCalendarIDs: ["calendar-1"],
      excludedCalendarIDs: ["calendar-2"],
      includedCalendarSourceIDs: ["source-1"],
      excludedCalendarSourceIDs: ["source-2"]
    )
    let options = CalendarMonthRequestOptions(
      emptyText: "No appointments",
      birthdays: CalendarBirthdayRequestOptions(showBirthdays: true, showAge: true),
      filters: filters
    )
    let range = DateInterval(
      start: Date(timeIntervalSinceReferenceDate: 1_000_000),
      duration: 86_400
    )

    let query = try XCTUnwrap(
      CalendarRequestFactory.makeMonthSubscribeRequest(range: range, options: options).query
    )

    XCTAssertEqual(query.includedCalendarNames, ["Work"])
    XCTAssertEqual(query.excludedCalendarNames, ["Holidays"])
    XCTAssertEqual(query.includedCalendarSourceNames, ["iCloud"])
    XCTAssertEqual(query.excludedCalendarSourceNames, ["Exchange"])
    XCTAssertEqual(query.includedCalendarIDs, ["calendar-1"])
    XCTAssertEqual(query.excludedCalendarIDs, ["calendar-2"])
    XCTAssertEqual(query.includedCalendarSourceIDs, ["source-1"])
    XCTAssertEqual(query.excludedCalendarSourceIDs, ["source-2"])
  }

  func testCalendarAgentQueryRoundTripPreservesSourceNameFilters() throws {
    let query = CalendarAgentQuery(
      startDate: Date(timeIntervalSinceReferenceDate: 1_000_000),
      endDate: Date(timeIntervalSinceReferenceDate: 1_086_400),
      showBirthdays: true,
      emptyText: "No appointments",
      birthdaysTitle: "Birthdays",
      birthdaysDateFormat: "dd.MM.yyyy",
      birthdaysShowAge: true,
      includedCalendarSourceNames: ["iCloud"],
      excludedCalendarSourceNames: ["Exchange"]
    )

    let encoded = try JSONEncoder().encode(query)
    let decoded = try JSONDecoder().decode(CalendarAgentQuery.self, from: encoded)

    XCTAssertEqual(decoded.includedCalendarSourceNames, ["iCloud"])
    XCTAssertEqual(decoded.excludedCalendarSourceNames, ["Exchange"])
  }
}
