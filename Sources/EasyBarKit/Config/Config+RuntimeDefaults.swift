import EasyBarShared
import Foundation

extension Config {
  /// Restores defaults derived from the current runtime environment.
  func resetDerivedDefaults() {
    let runtime = SharedRuntimeConfig.environmentDefaults()

    appSection.runtimeDirectory = runtime.app.runtimeDirectory
    appSection.widgetsPath = runtime.app.widgetsPath
    appSection.lockDirectory = runtime.app.lockDirectory
    appSection.luaSocketPath = runtime.app.luaSocketPath
    appSection.widgetEditorStubPath = runtime.app.widgetEditorStubPath

    loggingSection.directory = runtime.logging.directory
    loggingSection.level = runtime.logging.level

    calendarAgentSection.socketPath = runtime.calendarAgent.socketPath

    networkAgentSection.socketPath = runtime.networkAgent.socketPath
    networkAgentSection.refreshIntervalSeconds = runtime.networkAgent.refreshIntervalSeconds
    networkAgentSection.allowUnauthorizedNonSensitiveFields =
      runtime.networkAgent.allowUnauthorizedFieldsWithoutLocation

    themeSection.themesDir = defaultThemesDir()
  }

  /// Restores all static defaults before parsing again.
  func resetStaticDefaults() {
    resetAppDefaults()
    resetLoggingDefaults()
    resetAgentDefaults()
    resetThemeDefaults()
    resetBarDefaults()
    resetBuiltinDefaults()
  }

  /// Restores app-level defaults.
  func resetAppDefaults() {
    appSection.luaPath = SharedPathDefaults.defaultLuaPath
    appSection.environment = SharedPathDefaults.defaultLuaEnvironment
    appSection.watchConfigFile = true
    appSection.develop = false
    appSection.showMenuBarIcon = true
    appSection.luaCommandLimits = .init(
      timeoutSeconds: 5,
      maxOutputBytes: 64 * 1024,
      maxAsyncJobs: 8
    )
  }

  /// Returns configured app environment overrides with PATH's three-state semantics.
  static func mergedAppEnvironment(with configured: [String: String]) -> [String: String] {
    var environment = SharedPathDefaults.defaultLuaEnvironment

    for (key, value) in configured {
      if key == SharedEnvironmentKeys.path, value.isEmpty {
        environment.removeValue(forKey: key)
      } else {
        environment[key] = value
      }
    }

    return environment
  }

  /// Restores logging defaults.
  func resetLoggingDefaults() {
    loggingSection.enabled = false
    loggingSection.level = .info
  }

  /// Restores agent defaults.
  func resetAgentDefaults() {
    calendarAgentSection.enabled = true

    networkAgentSection.enabled = true
    networkAgentSection.refreshIntervalSeconds = 60
    networkAgentSection.allowUnauthorizedNonSensitiveFields = false
  }

  /// Returns the default user theme directory next to the active config file.
  private func defaultThemesDir() -> String {
    URL(fileURLWithPath: configPath)
      .deletingLastPathComponent()
      .appendingPathComponent("themes", isDirectory: true)
      .path
  }
}
