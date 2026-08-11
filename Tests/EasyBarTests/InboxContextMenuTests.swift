import XCTest

@testable import EasyBarKit

final class InboxContextMenuTests: XCTestCase {
  func testMenuReflectsConfiguration() throws {
    var config = Config.InboxBuiltinConfig.default
    config.groupBy = .severity
    config.sortBy = .title
    config.showUnreadCount = false

    let menu = try XCTUnwrap(WidgetContextMenuItem.validated(InboxContextMenu.make(config: config)))
    XCTAssertEqual(menu[0].submenu?.first(where: { $0.id == "inbox.group.severity" })?.checked, true)
    XCTAssertEqual(menu[1].submenu?.first(where: { $0.id == "inbox.sort.title" })?.checked, true)
    XCTAssertEqual(menu.first(where: { $0.id == "inbox.show_unread_count" })?.checked, false)
  }

  func testActionIdentifiersDecodeOnlySupportedValues() {
    XCTAssertEqual(InboxContextMenuAction(id: "inbox.group.date"), .setGroup(.date))
    XCTAssertEqual(InboxContextMenuAction(id: "inbox.sort.source"), .setSort(.source))
    XCTAssertEqual(InboxContextMenuAction(id: "inbox.sort_descending"), .toggleDescending)
    XCTAssertEqual(InboxContextMenuAction(id: "inbox.show_unread_count"), .toggleUnreadCount)
    XCTAssertNil(InboxContextMenuAction(id: "inbox.group.unknown"))
    XCTAssertNil(InboxContextMenuAction(id: "inbox.unknown"))
  }

  /// Verifies that the shared default retains EasyBar's secondary and muted Inbox colors.
  func testDefaultInboxIconsUseTheBarPalette() {
    let config = Config.InboxBuiltinConfig.default

    XCTAssertEqual(config.style.unreadIconColorHex, "theme.text_secondary")
    XCTAssertEqual(config.style.readIconColorHex, "theme.muted")
  }

  /// Verifies that the Native surface policy promotes both Inbox states to primary text.
  func testNativeInboxIconsUseThePrimaryMenuBarColor() {
    let config = Config.makeUnloadedConfig(builtInSurfacePolicy: .inboxOnly)

    config.applyThemeDefaults()

    XCTAssertEqual(config.builtinInbox.style.unreadIconColorHex, config.themeTextColorHex)
    XCTAssertEqual(config.builtinInbox.style.readIconColorHex, config.themeTextColorHex)
  }

  func testUnreadPresentationUsesUnreadIconAndColors() {
    var config = Config.InboxBuiltinConfig.default
    config.style.unreadIcon = "UNREAD"
    config.style.unreadIconColorHex = "#111111"
    config.style.unreadCountColorHex = "#222222"

    XCTAssertEqual(
      InboxAnchorPresentation.resolve(config: config, hasUnread: true),
      InboxAnchorPresentation(
        icon: "UNREAD",
        iconColorHex: "#111111",
        countColorHex: "#222222"
      )
    )
  }

  func testReadPresentationUsesReadIconAndColor() {
    var config = Config.InboxBuiltinConfig.default
    config.style.readIcon = "READ"
    config.style.readIconColorHex = "#333333"
    config.useInactiveStyleWhenRead = true

    XCTAssertEqual(
      InboxAnchorPresentation.resolve(config: config, hasUnread: false),
      InboxAnchorPresentation(
        icon: "READ",
        iconColorHex: "#333333",
        countColorHex: "#333333"
      )
    )
  }

  func testReadPresentationKeepsUnreadStyleWhenInactiveStyleIsDisabled() {
    var config = Config.InboxBuiltinConfig.default
    config.style.unreadIcon = "UNREAD"
    config.style.unreadIconColorHex = "#111111"
    config.style.unreadCountColorHex = "#222222"
    config.useInactiveStyleWhenRead = false

    XCTAssertEqual(
      InboxAnchorPresentation.resolve(config: config, hasUnread: false),
      InboxAnchorPresentation(
        icon: "UNREAD",
        iconColorHex: "#111111",
        countColorHex: "#222222"
      )
    )
  }
}
