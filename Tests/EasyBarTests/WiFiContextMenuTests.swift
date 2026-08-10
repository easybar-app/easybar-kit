import XCTest

@testable import EasyBarKit

final class WiFiContextMenuTests: XCTestCase {
  func testMenuReflectsEffectiveModeAndFields() throws {
    var config = Config.WiFiBuiltinConfig.default
    config.mode = .details
    config.fields.ssid = true

    let menu = WiFiContextMenu.make(config: config)
    let validated = try XCTUnwrap(WidgetContextMenuItem.validated(menu))
    let modeItems = try XCTUnwrap(validated.first?.submenu)
    let fieldItems = try XCTUnwrap(validated.dropFirst().first?.submenu)

    XCTAssertEqual(modeItems.first(where: { $0.id == "wifi.mode.details" })?.checked, true)
    XCTAssertEqual(modeItems.first(where: { $0.id == "wifi.mode.icon" })?.checked, false)
    XCTAssertEqual(fieldItems.first(where: { $0.id == "wifi.field.ssid" })?.checked, true)
  }

  func testActionIdentifiersDecodeOnlySupportedValues() {
    XCTAssertEqual(WiFiContextMenuAction(id: "wifi.mode.inline"), .setMode(.inline))
    XCTAssertEqual(WiFiContextMenuAction(id: "wifi.field.ssid"), .toggleField("ssid"))
    XCTAssertEqual(WiFiContextMenuAction(id: "wifi.refresh"), .refresh)
    XCTAssertEqual(
      WiFiContextMenuAction(id: "wifi.open_network_settings"),
      .openNetworkSettings
    )
    XCTAssertNil(WiFiContextMenuAction(id: "wifi.save_to_config"))
    XCTAssertNil(WiFiContextMenuAction(id: "wifi.reset_to_config"))
    XCTAssertNil(WiFiContextMenuAction(id: "wifi.field.unknown"))
    XCTAssertNil(WiFiContextMenuAction(id: "wifi.unknown"))
  }
}
