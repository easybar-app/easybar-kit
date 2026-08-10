import AppKit
import EasyBarShared
import XCTest

@testable import EasyBarKit

@MainActor
final class WidgetContextMenuTests: XCTestCase {
  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  func testDecodesActionsSeparatorsDefaultsAndRecursiveSubmenus() throws {
    let node = try decodeNode(
      menuJSON: """
        [
          {"id":"refresh","title":"Refresh"},
          {"separator":true},
          {"title":"Filter","submenu":[{"id":"all","title":"All","checked":true}]}
        ]
        """
    )

    let menu = try XCTUnwrap(node.validatedContextMenu)
    XCTAssertEqual(menu[0].id, "refresh")
    XCTAssertTrue(menu[0].enabled)
    XCTAssertFalse(menu[0].checked)
    XCTAssertTrue(menu[1].separator)
    XCTAssertEqual(menu[2].submenu?.first?.id, "all")
    XCTAssertTrue(menu[2].submenu?.first?.checked == true)
  }

  func testInvalidAndDuplicateActionsAreDroppedSafely() {
    let menu = WidgetContextMenuItem.validated([
      .init(id: "refresh", title: "Refresh"),
      .init(id: "refresh", title: "Duplicate"),
      .init(id: "", title: "Invalid"),
      .init(title: "Filter", submenu: []),
    ])

    XCTAssertEqual(menu?.map(\.id), ["refresh"])
  }

  func testSeparatorOnlyMenuIsTreatedAsAbsent() {
    XCTAssertNil(WidgetContextMenuItem.validated([.init(separator: true)]))
  }

  func testNativeMenuBuildsCheckedDisabledAndSubmenuItems() throws {
    let view = MouseTrackingNSView(logger: testLogger)
    view.contextMenuItems = [
      .init(id: "refresh", title: "Refresh", enabled: false, checked: true),
      .init(separator: true),
      .init(title: "Filter", submenu: [.init(id: "all", title: "All")]),
    ]

    let menu = try XCTUnwrap(view.makeContextMenu())
    XCTAssertEqual(menu.items.count, 3)
    XCTAssertFalse(menu.items[0].isEnabled)
    XCTAssertEqual(menu.items[0].state, .on)
    XCTAssertTrue(menu.items[1].isSeparatorItem)
    XCTAssertEqual(menu.items[2].submenu?.items.first?.representedObject as? String, "all")
  }

  func testSelectingEnabledItemEmitsActionAndDisabledItemDoesNot() throws {
    let view = MouseTrackingNSView(logger: testLogger)
    var selected: [String] = []
    view.onContextMenuAction = { selected.append($0) }
    view.contextMenuItems = [
      .init(id: "refresh", title: "Refresh"),
      .init(id: "disabled", title: "Disabled", enabled: false),
    ]

    let items = try XCTUnwrap(view.makeContextMenu()).items
    view.handleContextMenuItemSelection(items[0])
    view.handleContextMenuItemSelection(items[1])

    XCTAssertEqual(selected, ["refresh"])
  }

  func testReplacingAndRemovingMenuLeavesNoStaleActions() throws {
    let view = MouseTrackingNSView(logger: testLogger)
    view.contextMenuItems = [.init(id: "old", title: "Old")]
    XCTAssertEqual(try XCTUnwrap(view.makeContextMenu()).items.first?.representedObject as? String, "old")

    view.contextMenuItems = [.init(id: "new", title: "New")]
    XCTAssertEqual(try XCTUnwrap(view.makeContextMenu()).items.first?.representedObject as? String, "new")

    view.contextMenuItems = nil
    XCTAssertNil(view.makeContextMenu())
    XCTAssertFalse(view.consumesRightClickWithContextMenu)
  }

  func testContextMenuEventCarriesExistingWidgetIdentityAndActionID() {
    let payload = EasyBarEventPayload.widget(
      .contextMenuClicked,
      widgetID: "github",
      targetWidgetID: "github_filter",
      actionID: "filter_all"
    )

    XCTAssertEqual(payload.eventName, "context_menu.clicked")
    XCTAssertEqual(payload.luaPayload.widgetID, "github")
    XCTAssertEqual(payload.luaPayload.targetWidgetID, "github_filter")
    XCTAssertEqual(payload.luaPayload.actionID, "filter_all")
  }

  func testMenuPresenceControlsRightClickConsumption() {
    let view = MouseTrackingNSView(logger: testLogger)
    view.contextMenuItems = nil
    XCTAssertFalse(view.consumesRightClickWithContextMenu)

    view.contextMenuItems = [.init(id: "refresh", title: "Refresh")]
    XCTAssertTrue(view.consumesRightClickWithContextMenu)
  }

  private var testLogger: ProcessLogger {
    ProcessLogger(label: "widget-context-menu.test", minimumLevel: .error)
  }

  private func decodeNode(menuJSON: String) throws -> WidgetNodeState {
    let data = Data(
      """
      {"id":"github","root":"github","kind":"item","position":"right","order":0,"icon":"","text":"","visible":true,"context_menu":\(menuJSON)}
      """.utf8
    )
    return try decoder.decode(WidgetNodeState.self, from: data)
  }
}
