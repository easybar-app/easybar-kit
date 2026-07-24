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
    let configPath: String
    let runtimeDirectory: String
    let widgetsPath: String
    let luaPath: String
    let luaSocketPath: String
    let environment: [String: String]
    let watchConfigFile: Bool
    let lockDirectory: String
    let widgetEditorStubPath: String
    let develop: Bool
    let showMenuBarIcon: Bool
    let luaCommandLimits: Config.AppSection.LuaCommandLimits
  }

  /// Logging config snapshot.
  struct Logging {
    let enabled: Bool
    let level: ProcessLogLevel
    let directory: String
  }

  /// Calendar agent config snapshot.
  struct CalendarAgent {
    let enabled: Bool
    let socketPath: String
  }

  /// Network agent config snapshot.
  struct NetworkAgent {
    let enabled: Bool
    let socketPath: String
    let refreshIntervalSeconds: Double
    let allowUnauthorizedNonSensitiveFields: Bool
  }

  /// Theme config snapshot.
  struct Theme {
    /// Theme currently applied to the UI.
    let name: String
    let themesDir: String
    let colors: Config.ThemeColors
  }

  /// Built-in widget config snapshot.
  struct Builtins {
    var inbox: Config.InboxBuiltinConfig
    var privacySpacer: Config.SpacerBuiltinConfig = .privacyDefault
    var spacers: [Config.NamedSpacerBuiltinConfig] = []
    var cpu: Config.CPUBuiltinConfig
    var battery: Config.BatteryBuiltinConfig
    var groups: [Config.BuiltinGroupConfig]
    var spaces: Config.SpacesBuiltinConfig
    var frontApp: Config.FrontAppBuiltinConfig
    var aerospaceMode: Config.AeroSpaceModeBuiltinConfig
    var volume: Config.VolumeBuiltinConfig
    var wifi: Config.WiFiBuiltinConfig
    var calendar: Config.CalendarBuiltinConfig
    var time: Config.FormattedBuiltinConfig
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
