import Foundation

enum BatteryContextMenuAction: Equatable {
  case setDisplayMode(Config.BuiltinBatteryDisplayMode)
  case setColorMode(Config.BuiltinBatteryColorMode)
  case refresh

  init?(id: String) {
    if let value = id.removingPrefix("battery.display."),
      let mode = Config.BuiltinBatteryDisplayMode(rawValue: value)
    {
      self = .setDisplayMode(mode)
      return
    }
    if let value = id.removingPrefix("battery.color."),
      let mode = Config.BuiltinBatteryColorMode(rawValue: value)
    {
      self = .setColorMode(mode)
      return
    }
    guard id == "battery.refresh" else { return nil }
    self = .refresh
  }
}

enum BatteryContextMenu {
  static func make(config: Config.BatteryBuiltinConfig) -> [WidgetContextMenuItem] {
    let displayModes = Config.BuiltinBatteryDisplayMode.allCases.map { mode in
      WidgetContextMenuItem(
        id: "battery.display.\(mode.rawValue)",
        title: mode.rawValue.capitalized,
        checked: config.displayMode == mode
      )
    }
    let colorModes = Config.BuiltinBatteryColorMode.allCases.map { mode in
      WidgetContextMenuItem(
        id: "battery.color.\(mode.rawValue)",
        title: mode.rawValue.capitalized,
        checked: config.colorMode == mode
      )
    }
    return [
      WidgetContextMenuItem(title: "Display Mode", submenu: displayModes),
      WidgetContextMenuItem(title: "Color Mode", submenu: colorModes),
      WidgetContextMenuItem(separator: true),
      WidgetContextMenuItem(id: "battery.refresh", title: "Refresh"),
    ]
  }
}

extension String {
  fileprivate func removingPrefix(_ prefix: String) -> String? {
    guard hasPrefix(prefix) else { return nil }
    let suffix = String(dropFirst(prefix.count))
    return suffix.isEmpty ? nil : suffix
  }
}
