import XCTest

@testable import EasyBarKit

final class BatteryContextMenuTests: XCTestCase {
  func testMenuReflectsConfiguration() throws {
    var config = Config.BatteryBuiltinConfig.default
    config.displayMode = .always
    config.colorMode = .dynamic
    let menu = try XCTUnwrap(WidgetContextMenuItem.validated(BatteryContextMenu.make(config: config)))
    XCTAssertEqual(menu[0].submenu?.first(where: { $0.id == "battery.display.always" })?.checked, true)
    XCTAssertEqual(menu[1].submenu?.first(where: { $0.id == "battery.color.dynamic" })?.checked, true)
  }

  func testActionsDecodeOnlySupportedValues() {
    XCTAssertEqual(BatteryContextMenuAction(id: "battery.display.tooltip"), .setDisplayMode(.tooltip))
    XCTAssertEqual(BatteryContextMenuAction(id: "battery.color.fixed"), .setColorMode(.fixed))
    XCTAssertEqual(BatteryContextMenuAction(id: "battery.refresh"), .refresh)
    XCTAssertNil(BatteryContextMenuAction(id: "battery.display.unknown"))
  }
}
