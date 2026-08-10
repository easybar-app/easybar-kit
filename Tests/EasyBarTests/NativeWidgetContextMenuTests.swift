import EasyBarShared
import XCTest

@testable import EasyBarKit

final class NativeWidgetContextMenuTests: XCTestCase {
  func testCommonActionsCreateAContextMenuForWidgetsWithoutSpecificActions() {
    let menu = NativeWidgetContextMenu.appendingCommonActions(to: nil)

    XCTAssertEqual(
      menu.map(\.id),
      ["native_widget.reload", "native_widget.disable"]
    )
  }

  func testCommonActionsFollowWidgetSpecificActionsWithOneSeparator() {
    let menu = NativeWidgetContextMenu.appendingCommonActions(
      to: [WidgetContextMenuItem(id: "widget.refresh", title: "Refresh")]
    )

    XCTAssertEqual(menu.count, 4)
    XCTAssertEqual(menu[0].id, "widget.refresh")
    XCTAssertTrue(menu[1].separator)
    XCTAssertEqual(menu[2].id, "native_widget.reload")
    XCTAssertEqual(menu[3].id, "native_widget.disable")
  }

  @MainActor
  func testEnabledOverrideUpdatesOnlySelectedWidget() {
    let logger = ProcessLogger(label: "native.context.test", minimumLevel: .error)
    let store = AppServices.bootstrap(logger: logger).configSnapshotStore
    let original = store.snapshot

    store.applyNativeWidgetEnabledOverride("front_app", enabled: false)

    XCTAssertFalse(store.snapshot.builtins.frontApp.enabled)
    XCTAssertEqual(store.snapshot.builtins.spaces.enabled, original.builtins.spaces.enabled)
    XCTAssertEqual(store.snapshot.builtins.battery.enabled, original.builtins.battery.enabled)
  }
}
