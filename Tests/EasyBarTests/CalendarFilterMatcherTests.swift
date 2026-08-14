import EasyBarCalendarCore
import XCTest

final class CalendarFilterMatcherTests: XCTestCase {
  func testSplitFiltersMatchVisibleCalendarTitle() {
    let target = CalendarFilterTarget(
      title: "  Feriés  ",
      identifier: "calendar-123",
      sourceTitle: "iCloud",
      sourceIdentifier: "source-456"
    )

    XCTAssertTrue(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: ["feries"],
        excludedTitleTokens: [],
        includedSourceTitleTokens: [],
        excludedSourceTitleTokens: [],
        includedCalendarIDTokens: [],
        excludedCalendarIDTokens: [],
        includedSourceIDTokens: [],
        excludedSourceIDTokens: []
      )
    )
  }

  func testSplitFiltersMatchVisibleSourceTitle() {
    let target = CalendarFilterTarget(
      title: "Work",
      identifier: "calendar-123",
      sourceTitle: "  iClöud  ",
      sourceIdentifier: "source-456"
    )

    XCTAssertTrue(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
        includedSourceTitleTokens: ["icloud"],
        excludedSourceTitleTokens: [],
        includedCalendarIDTokens: [],
        excludedCalendarIDTokens: [],
        includedSourceIDTokens: [],
        excludedSourceIDTokens: []
      )
    )
  }

  func testSplitFiltersSupportAdvancedIdentifierSelectors() {
    let target = CalendarFilterTarget(
      title: "Work",
      identifier: "calendar-123",
      sourceTitle: "iCloud",
      sourceIdentifier: "source-456"
    )

    XCTAssertTrue(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
        includedSourceTitleTokens: [],
        excludedSourceTitleTokens: [],
        includedCalendarIDTokens: ["calendar-123"],
        excludedCalendarIDTokens: [],
        includedSourceIDTokens: [],
        excludedSourceIDTokens: []
      )
    )
    XCTAssertTrue(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
        includedSourceTitleTokens: [],
        excludedSourceTitleTokens: [],
        includedCalendarIDTokens: [],
        excludedCalendarIDTokens: [],
        includedSourceIDTokens: ["source-456"],
        excludedSourceIDTokens: []
      )
    )
  }

  func testSplitFiltersTrimIdentifierSelectors() {
    let target = CalendarFilterTarget(
      title: "Work",
      identifier: "calendar-123",
      sourceTitle: "iCloud",
      sourceIdentifier: "source-456"
    )

    XCTAssertTrue(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
        includedSourceTitleTokens: [],
        excludedSourceTitleTokens: [],
        includedCalendarIDTokens: ["  calendar-123  "],
        excludedCalendarIDTokens: [],
        includedSourceIDTokens: [],
        excludedSourceIDTokens: []
      )
    )
  }

  func testCalendarIdentifierMatchingIsCaseSensitive() {
    let target = CalendarFilterTarget(
      title: "Work",
      identifier: "Calendar-ABC",
      sourceTitle: "iCloud",
      sourceIdentifier: "Source-XYZ"
    )

    XCTAssertFalse(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
        includedSourceTitleTokens: [],
        excludedSourceTitleTokens: [],
        includedCalendarIDTokens: ["calendar-abc"],
        excludedCalendarIDTokens: [],
        includedSourceIDTokens: [],
        excludedSourceIDTokens: []
      )
    )
  }

  func testSourceIdentifierMatchingIsCaseSensitive() {
    let target = CalendarFilterTarget(
      title: "Work",
      identifier: "Calendar-ABC",
      sourceTitle: "iCloud",
      sourceIdentifier: "Source-XYZ"
    )

    XCTAssertFalse(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
        includedSourceTitleTokens: [],
        excludedSourceTitleTokens: [],
        includedCalendarIDTokens: [],
        excludedCalendarIDTokens: [],
        includedSourceIDTokens: ["source-xyz"],
        excludedSourceIDTokens: []
      )
    )
  }

  func testCaseMismatchedIdentifierDoesNotExcludeTarget() {
    let target = CalendarFilterTarget(
      title: "Work",
      identifier: "Calendar-ABC",
      sourceTitle: "iCloud",
      sourceIdentifier: "Source-XYZ"
    )

    XCTAssertTrue(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
        includedSourceTitleTokens: [],
        excludedSourceTitleTokens: [],
        includedCalendarIDTokens: [],
        excludedCalendarIDTokens: ["calendar-abc"],
        includedSourceIDTokens: [],
        excludedSourceIDTokens: []
      )
    )
  }

  func testSplitExcludesOverrideIncludedSelectorsAcrossFields() {
    let target = CalendarFilterTarget(
      title: "Work",
      identifier: "calendar-123",
      sourceTitle: "iCloud",
      sourceIdentifier: "source-456"
    )

    XCTAssertFalse(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: ["work"],
        excludedTitleTokens: [],
        includedSourceTitleTokens: [],
        excludedSourceTitleTokens: ["icloud"],
        includedCalendarIDTokens: [],
        excludedCalendarIDTokens: [],
        includedSourceIDTokens: [],
        excludedSourceIDTokens: []
      )
    )
  }
}
