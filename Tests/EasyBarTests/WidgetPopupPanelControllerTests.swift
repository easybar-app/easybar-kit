import XCTest

@testable import EasyBarApp

@MainActor
final class WidgetPopupPanelControllerTests: XCTestCase {
  func testTransientInteractionLockIsReferenceCounted() {
    let controller = WidgetPopupPanelController()

    XCTAssertFalse(controller.hasTransientInteraction)

    controller.beginTransientInteraction()
    controller.beginTransientInteraction()
    XCTAssertTrue(controller.hasTransientInteraction)

    controller.endTransientInteraction()
    XCTAssertTrue(controller.hasTransientInteraction)

    controller.endTransientInteraction()
    XCTAssertFalse(controller.hasTransientInteraction)
  }

  func testTransientInteractionLockDoesNotUnderflow() {
    let controller = WidgetPopupPanelController()

    controller.endTransientInteraction()

    XCTAssertFalse(controller.hasTransientInteraction)
  }
}
