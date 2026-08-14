import Foundation

/// Builds warnings for valid but surprising configuration combinations.
enum ConfigSemanticWarningBuilder {
  /// Warning shown when the enabled spaces widget has no content to render.
  static let spacesWithoutVisibleContent =
    "builtins.spaces is enabled, but both builtins.spaces.layout.show_label and "
    + "builtins.spaces.layout.show_icons are false; the spaces widget will not be rendered. "
    + "Enable either option or set builtins.spaces.enabled = false."

  /// Returns semantic warnings for one fully parsed config snapshot.
  static func warnings(for snapshot: ConfigSnapshot) -> [String] {
    var warnings: [String] = []

    if calendarDependsOnDisabledAgent(snapshot) {
      warnings.append(
        "builtins.calendar is enabled, but agents.calendar.enabled is false; the calendar widget will not receive calendar data."
      )
    }

    if wifiDependsOnDisabledAgent(snapshot) {
      warnings.append(
        "builtins.wifi is enabled, but agents.network.enabled is false; the Wi-Fi widget will not receive network data."
      )
    }

    let wifi = snapshot.builtins.wifi
    if wifiHasNoConfiguredContent(wifi) {
      warnings.append(
        "builtins.wifi.content.mode is \"\(wifi.mode.rawValue)\", but no builtins.wifi.fields entries are enabled."
      )
    }

    let spaces = snapshot.builtins.spaces
    if spacesHasNoVisibleContent(spaces) {
      warnings.append(spacesWithoutVisibleContent)
    }

    return warnings
  }

  private static func calendarDependsOnDisabledAgent(_ snapshot: ConfigSnapshot) -> Bool {
    snapshot.builtins.calendar.placement.enabled && !snapshot.calendarAgent.enabled
  }

  private static func wifiDependsOnDisabledAgent(_ snapshot: ConfigSnapshot) -> Bool {
    snapshot.builtins.wifi.enabled && !snapshot.networkAgent.enabled
  }

  private static func wifiHasNoConfiguredContent(_ wifi: Config.WiFiBuiltinConfig) -> Bool {
    wifi.enabled && wifi.mode != .icon && !wifi.fields.hasEnabledField
  }

  private static func spacesHasNoVisibleContent(_ spaces: Config.SpacesBuiltinConfig) -> Bool {
    spaces.enabled && !spaces.layout.showLabel && !spaces.layout.showIcons
  }
}
