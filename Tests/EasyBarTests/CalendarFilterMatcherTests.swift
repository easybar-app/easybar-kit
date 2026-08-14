import EasyBarCalendarCore
import XCTest

final class CalendarFilterMatcherTests: XCTestCase {
  func testSplitFiltersMatchVisibleCalendarTitle() {
    let target = CalendarFilterTarget(
      title: "  Feriés  ",
      identifier: "calendar-123",
      sourceIdentifier: "source-456"
    )

    XCTAssertTrue(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: ["feries"],
        excludedTitleTokens: [],
        includedCalendarIDTokens: [],
        excludedCalendarIDTokens: [],
        includedSourceIDTokens: [],
        excludedSourceIDTokens: []
      )
    )
  }

  func testSplitFiltersDoNotUseSourceTitle() {
    let target = CalendarFilterTarget(
      title: "Work",
      identifier: "calendar-123",
      sourceIdentifier: "source-456"
    )

    XCTAssertFalse(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: ["icloud"],
        excludedTitleTokens: [],
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
      sourceIdentifier: "source-456"
    )

    XCTAssertTrue(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
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
      sourceIdentifier: "source-456"
    )

    XCTAssertTrue(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
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
      sourceIdentifier: "Source-XYZ"
    )

    XCTAssertFalse(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
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
      sourceIdentifier: "Source-XYZ"
    )

    XCTAssertFalse(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
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
      sourceIdentifier: "Source-XYZ"
    )

    XCTAssertTrue(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: [],
        excludedTitleTokens: [],
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
      sourceIdentifier: "source-456"
    )

    XCTAssertFalse(
      CalendarFilterMatcher.matches(
        target,
        includedTitleTokens: ["work"],
        excludedTitleTokens: [],
        includedCalendarIDTokens: [],
        excludedCalendarIDTokens: ["calendar-123"],
        includedSourceIDTokens: [],
        excludedSourceIDTokens: []
      )
    )
  }
}
