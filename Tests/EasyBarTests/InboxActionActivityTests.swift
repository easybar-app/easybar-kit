import XCTest

@testable import EasyBarApp

final class InboxActionActivityTests: XCTestCase {
  func testActionDefaultsToEnabledAndIdle() {
    let action = InboxAction(id: "refresh", title: "Refresh")

    XCTAssertTrue(action.isEnabled)
    XCTAssertFalse(action.isBusy)
  }

  func testActionDecodesBusyAndDisabledState() throws {
    let data = Data(
      #"{"id":"activity","title":"Refreshing…","enabled":false,"busy":true}"#.utf8
    )

    let action = try JSONDecoder().decode(InboxAction.self, from: data)

    XCTAssertEqual(action.id, "activity")
    XCTAssertEqual(action.title, "Refreshing…")
    XCTAssertFalse(action.isEnabled)
    XCTAssertTrue(action.isBusy)
  }
}
