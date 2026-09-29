import EasyBarShared
import Foundation
import SwiftUI

/// Complete in-memory config snapshot used for rollback.
///
/// This is sendable as an immutable value snapshot; mutable app configuration is
/// copied into an immutable top-level value before the snapshot crosses task boundaries.
struct ConfigSnapshot: @unchecked Sendable {
  /// App-level config snapshot.
  struct App {
    /// The config path for this app.
    let configPath: String
    /// The runtime directory for this app.
    let runtimeDirectory: String
    /// The widgets path for this app.
    let widgetsPath: String
    /// The Lua path for this app.
    let luaPath: String
    /// The Lua socket path for this app.
    let luaSocketPath: String
    /// The environment for this app.
    let environment: [String: String]
    /// Whether the watch config file option is enabled for this app.
    let watchConfigFile: Bool
    /// The lock directory for this app.
    let lockDirectory: String
    /// The widget editor stub path for this app.
    let widgetEditorStubPath: String
    /// Whether the develop option is enabled for this app.
    let develop: Bool
    /// Whether this app shows menu bar icon.
    let showMenuBarIcon: Bool
    /// The Lua command limits for this app.
    let luaCommandLimits: Config.AppSection.LuaCommandLimits
  }

  /// Logging config snapshot.
  struct Logging {
    /// Whether this logging is enabled.
    let enabled: Bool
    /// The level for this logging.
    let level: ProcessLogLevel
    /// The directory for this logging.
    let directory: String
  }

  /// Calendar agent config snapshot.
  struct CalendarAgent {
    /// Whether this calendar agent is enabled.
    let enabled: Bool
    /// The socket path for this calendar agent.
    let socketPath: String
  }

  /// Network agent config snapshot.
  struct NetworkAgent {
    /// Whether this network agent is enabled.
    let enabled: Bool
    /// The socket path for this network agent.
    let socketPath: String
    /// The refresh interval seconds for this network agent.
    let refreshIntervalSeconds: Double
    /// Whether the allow unauthorized non sensitive fields option is enabled for this network agent.
    let allowUnauthorizedNonSensitiveFields: Bool
  }

  /// Theme config snapshot.
  struct Theme {
    /// Theme currently applied to the UI.
    let name: String
    /// The themes dir for this theme.
    let themesDir: String
    /// The colors for this theme.
    let colors: Config.ThemeColors
  }

  /// Built-in widget config snapshot.
  struct Builtins {
    /// The inbox for this builtins.
    var inbox: Config.InboxBuiltinConfig
    /// The privacy spacer for this builtins.
    var privacySpacer: Config.SpacerBuiltinConfig = .privacyDefault
    /// The spacers for this builtins.
    var spacers: [Config.NamedSpacerBuiltinConfig] = []
    /// The CPU for this builtins.
    var cpu: Config.CPUBuiltinConfig
    /// The battery for this builtins.
    var battery: Config.BatteryBuiltinConfig
    /// The groups for this builtins.
    var groups: [Config.BuiltinGroupConfig]
    /// The spaces for this builtins.
    var spaces: Config.SpacesBuiltinConfig
    /// The front app for this builtins.
    var frontApp: Config.FrontAppBuiltinConfig
    /// The aerospace mode for this builtins.
    var aerospaceMode: Config.AeroSpaceModeBuiltinConfig
    /// The volume for this builtins.
    var volume: Config.VolumeBuiltinConfig
    /// The Wi-Fi for this builtins.
    var wifi: Config.WiFiBuiltinConfig
    /// The calendar for this builtins.
    var calendar: Config.CalendarBuiltinConfig
    /// The time for this builtins.
    var time: Config.FormattedBuiltinConfig
    /// The date for this builtins.
    var date: Config.FormattedBuiltinConfig
  }

  /// App-level config values.
  let app: App
  /// Logging config values.
  let logging: Logging
  /// Calendar agent config values.
  let calendarAgent: CalendarAgent
  /// Network agent config values.
  let networkAgent: NetworkAgent
  /// Theme config values.
  let theme: Theme
  /// Bar config values.
  let bar: Config.BarSection
  /// Built-in widget config values.
  let builtins: Builtins
}

extension ConfigSnapshot {

  /// Returns a copy with updated logging settings.
  func replacing(logging: Logging) -> ConfigSnapshot {
    ConfigSnapshot(
      app: app,
      logging: logging,
      calendarAgent: calendarAgent,
      networkAgent: networkAgent,
      theme: theme,
      bar: bar,
      builtins: builtins
    )
  }

  /// Returns a copy with one updated built-in widget snapshot.
  func replacing(builtins: Builtins) -> ConfigSnapshot {
    ConfigSnapshot(
      app: app,
      logging: logging,
      calendarAgent: calendarAgent,
      networkAgent: networkAgent,
      theme: theme,
      bar: bar,
      builtins: builtins
    )
  }
  /// Resolves a color reference such as `theme.text` against this snapshot.
  func resolveThemeColorHex(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "theme."

    guard trimmed.lowercased().hasPrefix(prefix) else {
      return nil
    }

    let token = String(trimmed.dropFirst(prefix.count))
    return themeColorHex(named: token)
  }

  /// Resolves a theme token without the `theme.` prefix against this snapshot.
  func themeColorHex(named token: String) -> String? {
    guard let themeToken = ThemeColorToken(normalizedToken: token) else {
      return nil
    }

    return theme.colors[themeToken]
  }

  /// Resolves `theme.*` references or returns the input value unchanged.
  func resolvedColorHex(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return resolveThemeColorHex(trimmed) ?? trimmed
  }
}
