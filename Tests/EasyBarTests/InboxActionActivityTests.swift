import XCTest

@testable import EasyBarKit

final class InboxActionActivityTests: XCTestCase {
  func testActionDefaultsToEnabledAndIdle() {
    let action = InboxAction(id: "refresh", title: "Refresh")

    XCTAssertTrue(action.isEnabled)
    XCTAssertFalse(action.isBusy)
    XCTAssertFalse(action.isIncludedInRefreshAll)
  }

  func testActionDecodesBusyDisabledAndRefreshAllState() throws {
    let data = Data(
      #"{"id":"sync","title":"Refreshing…","enabled":false,"busy":true,"include_in_refresh_all":true}"#.utf8
    )

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let action = try decoder.decode(InboxAction.self, from: data)

    XCTAssertEqual(action.id, "sync")
    XCTAssertEqual(action.title, "Refreshing…")
    XCTAssertFalse(action.isEnabled)
    XCTAssertTrue(action.isBusy)
    XCTAssertTrue(action.isIncludedInRefreshAll)
  }

  func testMatchingBusySourceActionUsesStatusInsteadOfSecondItemSpinner() {
    let presentation = InboxItemActionPresentation(
      action: InboxAction(id: "sync", title: "Sync now"),
      busySourceAction: InboxAction(id: "sync", title: "Refreshing…", busy: true)
    )

    XCTAssertEqual(presentation.title, "Refreshing…")
    XCTAssertEqual(presentation.style, .status)
    XCTAssertFalse(presentation.isEnabled)
  }

  func testItemOperationKeepsItsInlineProgressIndicator() {
    let presentation = InboxItemActionPresentation(
      action: InboxAction(id: "upgrade", title: "Upgrading…", enabled: false, busy: true),
      busySourceAction: nil
    )

    XCTAssertEqual(presentation.title, "Upgrading…")
    XCTAssertEqual(presentation.style, .progress)
    XCTAssertFalse(presentation.isEnabled)
  }

  func testIdleItemActionRemainsAButton() {
    let presentation = InboxItemActionPresentation(
      action: InboxAction(id: "refresh", title: "Refresh"),
      busySourceAction: nil
    )

    XCTAssertEqual(presentation.title, "Refresh")
    XCTAssertEqual(presentation.style, .button)
    XCTAssertTrue(presentation.isEnabled)
  }
}
