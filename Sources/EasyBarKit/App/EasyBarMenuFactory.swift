import AppKit
import EasyBarShared

enum EasyBarRuntimeState: Equatable {
  case running
  case stopped
  case transitioning
}

enum EasyBarMenuGroup: CaseIterable {
  case version
  case lifecycle
  case runtime
  case nativeWidgets
  case theme
  case agents
  case files
  case developer
  case quit

  /// Groups appropriate for an empty-area right-click on the bar.
  static let barContext: [Self] = [
    .version,
    .runtime,
    .nativeWidgets,
    .theme,
    .files,
    .developer,
  ]
}

@MainActor
struct EasyBarMenuActions {
  let start: () -> Void
  let stop: () -> Void
  let restart: () -> Void
  let refresh: () -> Void
  let reloadConfig: () -> Void
  let restartLuaRuntime: () -> Void
  let restartCalendarAgent: () -> Void
  let restartNetworkAgent: () -> Void
  let selectTheme: (String?) -> Void
  let setNativeWidgetEnabled: (String, Bool) -> Void
  let setLogLevel: (ProcessLogLevel) -> Void
  let quit: () -> Void
}

/// Builds reusable native menu groups for the bar and menu-bar controller.
@MainActor
final class EasyBarMenuFactory: NSObject {
  private let logger: ProcessLogger
  private let configStore: ConfigSnapshotStore
  private let actions: EasyBarMenuActions
  private let stateProvider: BarContextMenuStateProvider
  private let runtimeState: () -> EasyBarRuntimeState
  private let frontendDisplayName: String
  private let builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy

  /// Creates a menu builder configured for one frontend identity and built-in policy.
  init(
    logger: ProcessLogger,
    configStore: ConfigSnapshotStore,
    actions: EasyBarMenuActions,
    stateProvider: BarContextMenuStateProvider,
    frontendDisplayName: String,
    builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy,
    runtimeState: @escaping () -> EasyBarRuntimeState
  ) {
    self.logger = logger
    self.configStore = configStore
    self.actions = actions
    self.stateProvider = stateProvider
    self.runtimeState = runtimeState
    self.frontendDisplayName = frontendDisplayName
    self.builtInSurfacePolicy = builtInSurfacePolicy
    super.init()
  }

  /// Builds the shared menu, optionally exposing developer controls requested by Shift.
  func makeMenu(
    groups: [EasyBarMenuGroup] = EasyBarMenuGroup.allCases,
    showDeveloperSection: Bool = false
  ) -> NSMenu {
    let menu = NSMenu()
    let visibleGroups = groups.compactMap { group -> [NSMenuItem]? in
      let items = items(for: group, showDeveloperSection: showDeveloperSection)
      return items.isEmpty ? nil : items
    }

    for (index, items) in visibleGroups.enumerated() {
      if index > 0 { menu.addItem(.separator()) }
      for item in items { menu.addItem(item) }
    }
    return menu
  }

  /// Builds the items belonging to one logical menu group.
  private func items(
    for group: EasyBarMenuGroup,
    showDeveloperSection: Bool
  ) -> [NSMenuItem] {
    switch group {
    case .version:
      return [readOnlyItem("\(frontendDisplayName) \(BuildInfo.appVersion)", tertiary: true)]
    case .lifecycle:
      return lifecycleItems
    case .runtime:
      return runtimeItems
    case .nativeWidgets:
      guard let item = nativeWidgetsMenuItem() else { return [] }
      return [item]
    case .theme:
      return [themeMenuItem()]
    case .agents:
      guard builtInSurfacePolicy == .all else { return [] }
      return [calendarAgentMenuItem, networkAgentMenuItem]
    case .files:
      return fileItems
    case .developer:
      return configStore.snapshot.app.develop || showDeveloperSection ? [logLevelMenuItem()] : []
    case .quit:
      return [actionItem(title: "Quit Completely", action: #selector(quitCompletely(_:)))]
    }
  }

  private var lifecycleItems: [NSMenuItem] {
    switch runtimeState() {
    case .running:
      return [
        actionItem(title: "Stop \(frontendDisplayName)", action: #selector(stopEasyBar(_:))),
        actionItem(title: "Restart \(frontendDisplayName)", action: #selector(restartEasyBar(_:))),
      ]
    case .stopped:
      return [
        actionItem(title: "Start \(frontendDisplayName)", action: #selector(startEasyBar(_:)))
      ]
    case .transitioning:
      return [readOnlyItem("Updating \(frontendDisplayName)…")]
    }
  }

  private var runtimeItems: [NSMenuItem] {
    let enabled = runtimeState() == .running
    return [
      actionItem(
        title: "Refresh",
        action: #selector(refresh(_:)),
        enabled: enabled,
        toolTip:
          "Refreshes visible widgets and runtime data without reloading configuration or restarting Lua."
      ),
      actionItem(
        title: "Reload Config",
        action: #selector(reloadConfig(_:)),
        enabled: enabled,
        toolTip: "Reloads config.toml, rebuilds runtime state, and reconnects active subscriptions."
      ),
      actionItem(
        title: "Restart Lua Runtime",
        action: #selector(restartLuaRuntime(_:)),
        enabled: enabled,
        toolTip:
          "Stops and starts the Lua widget runtime, reloads all Lua widget files, and resets Lua widget state."
      ),
    ]
  }

  /// Builds the built-in surface submenu allowed by the active frontend policy.
  private func nativeWidgetsMenuItem() -> NSMenuItem? {
    let builtins = configStore.snapshot.builtins
    let widgets: [(String, String, Bool)]

    switch builtInSurfacePolicy {
    case .all:
      widgets = [
        ("spaces", "Spaces", builtins.spaces.enabled),
        ("inbox", "Inbox", builtins.inbox.enabled),
        ("privacy_spacer", "Privacy Spacer", builtins.privacySpacer.enabled),
        ("battery", "Battery", builtins.battery.enabled),
        ("wifi", "Wi-Fi", builtins.wifi.enabled),
        ("calendar", "Calendar", builtins.calendar.enabled),
        ("volume", "Volume", builtins.volume.enabled),
        ("front_app", "Front App", builtins.frontApp.enabled),
        ("aerospace_mode", "AeroSpace Mode", builtins.aerospaceMode.enabled),
        ("cpu", "CPU", builtins.cpu.enabled),
        ("time", "Time", builtins.time.placement.enabled),
        ("date", "Date", builtins.date.placement.enabled),
      ]
    case .inboxOnly:
      widgets = [("inbox", "Inbox", builtins.inbox.enabled)]
    case .none:
      widgets = []
    }

    guard !widgets.isEmpty else { return nil }

    let item = submenuItem(title: "Native Widgets")
    item.isEnabled = runtimeState() == .running
    for (key, title, enabled) in widgets {
      let toggle = actionItem(title: title, action: #selector(toggleNativeWidget(_:)))
      toggle.representedObject = key
      toggle.state = enabled ? .on : .off
      item.submenu?.addItem(toggle)
    }
    return item
  }

  /// Builds the theme-selection submenu from the current config snapshot.
  private func themeMenuItem() -> NSMenuItem {
    let snapshot = configStore.snapshot
    let item = submenuItem(title: "Theme")
    item.isEnabled = runtimeState() == .running
    for name in ThemeCatalog.availableThemeNames(for: snapshot, logger: logger) {
      let theme = actionItem(title: name, action: #selector(selectTheme(_:)))
      theme.representedObject = name
      theme.state = snapshot.theme.name == name ? .on : .off
      item.submenu?.addItem(theme)
    }
    return item
  }

  private var calendarAgentMenuItem: NSMenuItem {
    agentMenuItem(
      title: "Calendar Agent",
      connected: stateProvider.calendarAgentConnected,
      permission: stateProvider.calendarPermissionLabel,
      restartAction: #selector(restartCalendarAgent(_:)),
      settingsAction: #selector(openCalendarSettings(_:)),
      settingsTitle: "Open Calendar Settings"
    )
  }

  private var networkAgentMenuItem: NSMenuItem {
    agentMenuItem(
      title: "Network Agent",
      connected: stateProvider.networkAgentConnected,
      permission: stateProvider.wifiPermissionLabel,
      restartAction: #selector(restartNetworkAgent(_:)),
      settingsAction: #selector(openLocationSettings(_:)),
      settingsTitle: "Open Location/Wi-Fi Settings"
    )
  }

  /// Builds one helper-agent status submenu with restart and permission controls.
  private func agentMenuItem(
    title: String,
    connected: Bool,
    permission: String,
    restartAction: Selector,
    settingsAction: Selector,
    settingsTitle: String
  ) -> NSMenuItem {
    let item = submenuItem(title: title)
    let submenu = item.submenu!
    submenu.addItem(readOnlyItem("Status: \(connected ? "Connected" : "Disconnected")"))
    submenu.addItem(readOnlyItem("Permission: \(permission)"))
    submenu.addItem(.separator())
    submenu.addItem(
      actionItem(title: "Restart Agent", action: restartAction, enabled: connected)
    )
    submenu.addItem(actionItem(title: settingsTitle, action: settingsAction))
    return item
  }

  private var fileItems: [NSMenuItem] {
    [
      actionItem(title: "Open Config", action: #selector(openConfig(_:))),
      actionItem(title: "Open Widgets Folder", action: #selector(openWidgetsFolder(_:))),
      actionItem(title: "Open Log Folder", action: #selector(openLogFolder(_:))),
    ]
  }

  /// Builds the runtime log-level selection submenu.
  private func logLevelMenuItem() -> NSMenuItem {
    let item = submenuItem(title: "Log Level")
    for level in ProcessLogLevel.allCases {
      let levelItem = actionItem(
        title: level.rawValue.capitalized, action: #selector(setLogLevel(_:)))
      levelItem.representedObject = level.rawValue
      levelItem.state = logger.minimumLevel == level ? .on : .off
      item.submenu?.addItem(levelItem)
    }
    return item
  }

  /// Creates a standard actionable menu item owned by this factory.
  private func actionItem(
    title: String,
    action: Selector,
    enabled: Bool = true,
    toolTip: String? = nil
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = enabled
    item.toolTip = toolTip
    return item
  }

  /// Creates an empty submenu container with the supplied title.
  private func submenuItem(title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = NSMenu(title: title)
    return item
  }

  /// Creates a disabled informational item with optional tertiary styling.
  private func readOnlyItem(_ title: String, tertiary: Bool = false) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    item.attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .foregroundColor: tertiary ? NSColor.tertiaryLabelColor : NSColor.secondaryLabelColor
      ]
    )
    return item
  }

  @objc private func startEasyBar(_ sender: Any?) { actions.start() }
  @objc private func stopEasyBar(_ sender: Any?) { actions.stop() }
  @objc private func restartEasyBar(_ sender: Any?) { actions.restart() }
  @objc private func refresh(_ sender: Any?) { actions.refresh() }
  @objc private func reloadConfig(_ sender: Any?) { actions.reloadConfig() }
  @objc private func restartLuaRuntime(_ sender: Any?) { actions.restartLuaRuntime() }
  @objc private func restartCalendarAgent(_ sender: Any?) { actions.restartCalendarAgent() }
  @objc private func restartNetworkAgent(_ sender: Any?) { actions.restartNetworkAgent() }
  @objc private func quitCompletely(_ sender: Any?) { actions.quit() }

  @objc private func selectTheme(_ sender: NSMenuItem) {
    guard let name = sender.representedObject as? String else { return }
    actions.selectTheme(name)
  }

  @objc private func toggleNativeWidget(_ sender: NSMenuItem) {
    guard let key = sender.representedObject as? String else { return }
    actions.setNativeWidgetEnabled(key, sender.state != .on)
  }

  @objc private func setLogLevel(_ sender: NSMenuItem) {
    guard let value = sender.representedObject as? String,
      let level = ProcessLogLevel(rawValue: value)
    else { return }
    actions.setLogLevel(level)
  }

  @objc private func openConfig(_ sender: Any?) {
    NSWorkspace.shared.open(URL(fileURLWithPath: configStore.snapshot.app.configPath))
  }

  @objc private func openWidgetsFolder(_ sender: Any?) {
    NSWorkspace.shared.open(
      URL(fileURLWithPath: configStore.snapshot.app.widgetsPath, isDirectory: true)
    )
  }

  @objc private func openLogFolder(_ sender: Any?) {
    NSWorkspace.shared.open(
      URL(fileURLWithPath: configStore.snapshot.logging.directory, isDirectory: true)
    )
  }

  @objc private func openCalendarSettings(_ sender: Any?) {
    openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
  }

  @objc private func openLocationSettings(_ sender: Any?) {
    openSettingsURL(
      "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
    )
  }

  /// Opens one validated macOS Settings URL, logging failures without terminating the app.
  private func openSettingsURL(_ value: String) {
    guard let url = URL(string: value) else { return }
    NSWorkspace.shared.open(url)
  }
}
