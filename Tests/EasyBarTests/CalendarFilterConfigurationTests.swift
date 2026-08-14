import EasyBarCalendarConfig
import SwiftTOMLEdit
import XCTest

final class CalendarFilterConfigurationTests: XCTestCase {
  func testParsesCalendarAndSourceFilters() throws {
    let table = try TOMLTable(
      string: """
        [filters]
        included_calendar_names = ["Work"]
        excluded_calendar_names = ["Holidays"]
        included_calendar_source_names = ["iCloud"]
        excluded_calendar_source_names = ["Exchange"]
        included_calendar_ids = ["calendar-1"]
        excluded_calendar_ids = ["calendar-2"]
        included_calendar_source_ids = ["source-1"]
        excluded_calendar_source_ids = ["source-2"]
        """
    )

    let filters = try CalendarBuiltinConfig.parse(from: table).filters

    XCTAssertEqual(filters.includedCalendarNames, ["Work"])
    XCTAssertEqual(filters.excludedCalendarNames, ["Holidays"])
    XCTAssertEqual(filters.includedCalendarSourceNames, ["iCloud"])
    XCTAssertEqual(filters.excludedCalendarSourceNames, ["Exchange"])
    XCTAssertEqual(filters.includedCalendarIDs, ["calendar-1"])
    XCTAssertEqual(filters.excludedCalendarIDs, ["calendar-2"])
    XCTAssertEqual(filters.includedCalendarSourceIDs, ["source-1"])
    XCTAssertEqual(filters.excludedCalendarSourceIDs, ["source-2"])
  }
}
