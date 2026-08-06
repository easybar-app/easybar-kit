import AppKit
import SwiftUI
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

  func testScheduledContentLayoutRefreshResizesPresentedPanel() async {
    let parent = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let anchor = NSView(frame: NSRect(x: 280, y: 40, width: 24, height: 24))
    parent.contentView?.addSubview(anchor)

    let model = PopupSizingModel()
    let controller = WidgetPopupPanelController()
    controller.updateAnchorView(anchor)
    controller.update(
      isPresented: true,
      content: AnyView(PopupSizingView(model: model))
    )

    guard let popup = parent.childWindows?.first else {
      XCTFail("Expected the popup panel to be attached")
      return
    }
    let collapsedHeight = popup.frame.height

    model.isExpanded = true
    try? await Task.sleep(for: .milliseconds(20))
    controller.scheduleContentLayoutRefresh()
    try? await Task.sleep(for: .milliseconds(20))

    XCTAssertGreaterThan(popup.frame.height, collapsedHeight)

    controller.close()
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

@MainActor
private final class PopupSizingModel: ObservableObject {
  @Published var isExpanded = false
}

private struct PopupSizingView: View {
  @ObservedObject var model: PopupSizingModel

  var body: some View {
    VStack(alignment: .leading) {
      Text("Popup")
      if model.isExpanded {
        ForEach(0..<8, id: \.self) { index in
          Text("Row \(index)")
        }
      }
    }
    .frame(width: 160, alignment: .leading)
    .padding(8)
  }
}
