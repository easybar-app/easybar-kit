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

  func testSourceRefreshUsesStatusInsteadOfSecondItemSpinner() {
    let presentation = InboxItemActionPresentation(
      action: InboxAction(id: "refresh", title: "Refresh", busy: true),
      sourceIsBusy: true
    )

    XCTAssertEqual(presentation.title, "Refreshing…")
    XCTAssertEqual(presentation.style, .status)
    XCTAssertFalse(presentation.isEnabled)
  }

  func testItemOperationKeepsItsInlineProgressIndicator() {
    let presentation = InboxItemActionPresentation(
      action: InboxAction(id: "upgrade", title: "Upgrading…", enabled: false, busy: true),
      sourceIsBusy: false
    )

    XCTAssertEqual(presentation.title, "Upgrading…")
    XCTAssertEqual(presentation.style, .progress)
    XCTAssertFalse(presentation.isEnabled)
  }

  func testIdleItemActionRemainsAButton() {
    let presentation = InboxItemActionPresentation(
      action: InboxAction(id: "refresh", title: "Refresh"),
      sourceIsBusy: false
    )

    XCTAssertEqual(presentation.title, "Refresh")
    XCTAssertEqual(presentation.style, .button)
    XCTAssertTrue(presentation.isEnabled)
  }
}
