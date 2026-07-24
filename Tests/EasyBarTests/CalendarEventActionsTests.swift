import EasyBarCalendarUI
import EasyBarShared
import Foundation
import XCTest

final class CalendarEventActionsTests: XCTestCase {
  func testBuiltInPatternsPreserveLegacyProviderList() {
    XCTAssertEqual(
      CalendarMeetingURLMatcher.defaultPatterns,
      [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "webex.com",
        "whereby.com",
        "jitsi",
        "gotomeeting.com",
        "bluejeans.com",
      ]
    )
  }

  func testDefaultPatternsRecognizeMeetingURL() {
    let actions = CalendarEventActions()

    XCTAssertEqual(
      actions.urlActionTitle(for: event(url: "https://meet.google.com/eas-ybar-demo")),
      "Join Meeting"
    )
  }

  func testCustomPatternsReplaceDefaultsAndNormalizeValues() {
    let actions = CalendarEventActions(
      meetingURLPatterns: [" Video.Example.com ", "video.example.com", ""]
    )

    XCTAssertEqual(
      actions.urlActionTitle(for: event(url: "https://video.example.com/room/42")),
      "Join Meeting"
    )
    XCTAssertEqual(
      actions.urlActionTitle(for: event(url: "https://zoom.us/j/42")),
      "Open URL"
    )
    XCTAssertEqual(actions.meetingURLPatterns, ["video.example.com"])
  }

  func testEmptyPatternListDisablesMeetingTitle() {
    let actions = CalendarEventActions(meetingURLPatterns: [])

    XCTAssertEqual(
      actions.urlActionTitle(for: event(url: "https://meet.google.com/eas-ybar-demo")),
      "Open URL"
    )
  }

  private func event(url: String?) -> CalendarAgentEvent {
    CalendarAgentEvent(
      id: "event-1",
      title: "Meeting",
      startDate: Date(timeIntervalSince1970: 0),
      endDate: Date(timeIntervalSince1970: 3_600),
      isAllDay: false,
      url: url
    )
  }
}
