import AppKit
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

  func testPopupIsRepromotedAfterJoiningStatusBarWindow() {
    let parent = NSWindow(
      contentRect: .zero,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    parent.level = .statusBar

    let popup = NSPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    parent.addChildWindow(popup, ordered: .above)

    WidgetPopupPanelController.orderPopupFront(popup)

    XCTAssertEqual(popup.level, .popUpMenu)
    XCTAssertGreaterThan(popup.level.rawValue, parent.level.rawValue)

    popup.orderOut(nil)
    parent.removeChildWindow(popup)
  }
}
