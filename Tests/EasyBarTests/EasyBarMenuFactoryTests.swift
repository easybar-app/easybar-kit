import AppKit
import EasyBarShared
import XCTest

@testable import EasyBarKit

@MainActor
final class EasyBarMenuFactoryTests: XCTestCase {
  func testSharedMenuCompositionHasStableGroupsAndSeparators() {
    let factory = makeFactory(runtimeState: { .running })

    let first = factory.makeMenu()
    let second = factory.makeMenu()

    XCTAssertEqual(menuShape(first), menuShape(second))
    XCTAssertEqual(first.items.first?.title, "EasyBar \(BuildInfo.appVersion)")
    XCTAssertEqual(first.items.last?.title, "Quit Completely")
    XCTAssertFalse(first.items.first?.isSeparatorItem == true)
    XCTAssertFalse(first.items.last?.isSeparatorItem == true)
    XCTAssertFalse(
      zip(first.items, first.items.dropFirst()).contains { left, right in
        left.isSeparatorItem && right.isSeparatorItem
      }
    )
  }

  func testStoppedMenuEnablesStartAndDisablesRuntimeConfigurationGroups() throws {
    let menu = makeFactory(runtimeState: { .stopped }).makeMenu()

    XCTAssertNotNil(menu.item(withTitle: "Start EasyBar"))
    XCTAssertNil(menu.item(withTitle: "Stop EasyBar"))
    XCTAssertFalse(try XCTUnwrap(menu.item(withTitle: "Refresh")).isEnabled)
    XCTAssertFalse(try XCTUnwrap(menu.item(withTitle: "Native Widgets")).isEnabled)
    XCTAssertFalse(try XCTUnwrap(menu.item(withTitle: "Theme")).isEnabled)
  }

  func testSelectedGroupsComposeWithoutExtraSeparators() {
    let menu = makeFactory(runtimeState: { .running }).makeMenu(
      groups: [.runtime, .files]
    )

    XCTAssertEqual(
      menu.items.map { $0.isSeparatorItem ? "-" : $0.title },
      [
        "Refresh", "Reload Config", "Restart Lua Runtime", "-", "Open Config",
        "Open Widgets Folder", "Open Log Folder",
      ]
    )
  }

  func testBarContextExcludesApplicationAndAgentControls() {
    let menu = makeFactory(runtimeState: { .running }).makeMenu(
      groups: EasyBarMenuGroup.barContext
    )

    XCTAssertNotNil(menu.item(withTitle: "Refresh"))
    XCTAssertNotNil(menu.item(withTitle: "Native Widgets"))
    XCTAssertNotNil(menu.item(withTitle: "Theme"))
    XCTAssertNotNil(menu.item(withTitle: "Open Config"))
    XCTAssertNil(menu.item(withTitle: "Stop EasyBar"))
    XCTAssertNil(menu.item(withTitle: "Restart EasyBar"))
    XCTAssertNil(menu.item(withTitle: "Calendar Agent"))
    XCTAssertNil(menu.item(withTitle: "Network Agent"))
    XCTAssertNil(menu.item(withTitle: "Quit Completely"))
  }

  func testInboxOnlyFrontendUsesItsIdentityAndOmitsUnsupportedControls() throws {
    let menu = makeFactory(
      runtimeState: { .running },
      frontendDisplayName: "EasyBar Native",
      builtInSurfacePolicy: .inboxOnly
    ).makeMenu()

    XCTAssertEqual(menu.items.first?.title, "EasyBar Native \(BuildInfo.appVersion)")
    XCTAssertNotNil(menu.item(withTitle: "Stop EasyBar Native"))
    XCTAssertNil(menu.item(withTitle: "Calendar Agent"))
    XCTAssertNil(menu.item(withTitle: "Network Agent"))
    let nativeWidgets = try XCTUnwrap(menu.item(withTitle: "Native Widgets")?.submenu)
    XCTAssertEqual(nativeWidgets.items.map(\.title), ["Inbox"])
  }

  func testLogLevelSelectionUsesConfiguredAction() throws {
    var selectedLevel: ProcessLogLevel?
    let factory = makeFactory(
      runtimeState: { .running },
      setLogLevel: { selectedLevel = $0 }
    )
    let menu = factory.makeMenu(groups: [.developer], showDeveloperSection: true)
    let logLevelItem = try XCTUnwrap(menu.item(withTitle: "Log Level"))
    let debugItem = try XCTUnwrap(logLevelItem.submenu?.item(withTitle: "Debug"))

    XCTAssertTrue(
      NSApplication.shared.sendAction(
        try XCTUnwrap(debugItem.action),
        to: debugItem.target,
        from: debugItem
      )
    )
    XCTAssertEqual(selectedLevel, .debug)
  }

  private func makeFactory(
    runtimeState: @escaping () -> EasyBarRuntimeState,
    frontendDisplayName: String = "EasyBar",
    builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy = .all,
    setLogLevel: @escaping (ProcessLogLevel) -> Void = { _ in }
  ) -> EasyBarMenuFactory {
    let logger = ProcessLogger(label: "menu.factory.test", minimumLevel: .error)
    let services = AppServices.bootstrap(logger: logger)
    let stateProvider = BarContextMenuStateProvider(
      nativeWiFiStore: services.nativeWiFiStore,
      nativeMonthCalendarStore: services.nativeMonthCalendarStore,
      nativeUpcomingCalendarStore: services.nativeUpcomingCalendarStore,
      monthCalendarAgentClient: services.monthCalendarAgentClient,
      upcomingCalendarAgentClient: services.upcomingCalendarAgentClient,
      networkAgentClient: services.networkAgentClient
    )
    return EasyBarMenuFactory(
      logger: logger,
      configStore: services.configSnapshotStore,
      actions: EasyBarMenuActions(
        start: {},
        stop: {},
        restart: {},
        refresh: {},
        reloadConfig: {},
        restartLuaRuntime: {},
        restartCalendarAgent: {},
        restartNetworkAgent: {},
        selectTheme: { _ in },
        setNativeWidgetEnabled: { _, _ in },
        setLogLevel: setLogLevel,
        quit: {}
      ),
      stateProvider: stateProvider,
      frontendDisplayName: frontendDisplayName,
      builtInSurfacePolicy: builtInSurfacePolicy,
      runtimeState: runtimeState
    )
  }

  private func menuShape(_ menu: NSMenu) -> [String] {
    menu.items.map { item in
      let children = item.submenu.map(menuShape) ?? []
      return ([item.isSeparatorItem ? "-" : item.title] + children).joined(separator: "/")
    }
  }
}
