import AppKit
import EasyBarShared
import Foundation

/// Logs one-time startup diagnostics for support and troubleshooting.
@MainActor
struct AppStartupDiagnostics {
  private let logger: ProcessLogger
  private let processName: String

  init(logger: ProcessLogger, processName: String) {
    self.logger = logger
    self.processName = processName
  }

  /// Logs one startup snapshot so service-vs-local differences are visible.
  func logStartup(services: AppServices) {
    logProcessStartup(
      processName: processName,
      configPath: services.config.configPath,
      socketPath: services.config.easyBarSocketPath,
      logger: logger
    )

    logConfigDetails(services: services)
    logScreenDetails()
    logEnvironmentDetails()
    logConfiguredEnvironment(services: services)
  }

  /// Logs whether required custom fonts are available at runtime.
  func validateRequiredFonts() {
    validateFont(named: "Symbols Nerd Font Mono")
  }

  /// Logs config-derived startup details.
  private func logConfigDetails(services: AppServices) {
    logger.debug("config details", .field("runtime_dir", services.config.runtimeDirectory))
    logger.debug("config details", .field("widgets_path", services.config.widgetsPath))
    logger.debug("config details", .field("lua_path", services.config.luaPath))
    logger.debug("config details", .field("lua_socket_path", services.config.luaSocketPath))
    logger.debug("config details", .field("watch_config", services.config.watchConfigFile))
    logger.debug(
      "config details",
      .field("calendar_agent_enabled", services.config.calendarAgentEnabled),
      .field("socket", services.config.calendarAgentSocketPath)
    )
    logger.debug(
      "config details",
      .field("network_agent_enabled", services.config.networkAgentEnabled),
      .field("socket", services.config.networkAgentSocketPath),
      .field("refresh_interval_seconds", services.config.networkAgentRefreshIntervalSeconds)
    )
    logger.debug(
      "config details",
      .field("calendar_builtin_enabled", services.config.builtinCalendar.enabled),
      .field("popup_mode", services.config.builtinCalendar.popupMode.rawValue),
      .field("anchor_layout", services.config.builtinCalendar.anchor.layout.rawValue),
      .field("position", services.config.builtinCalendar.position.rawValue)
    )
    logger.debug(
      "config details",
      .field("wifi_builtin_enabled", services.config.builtinWiFi.enabled),
      .field("position", services.config.builtinWiFi.position.rawValue)
    )
    logger.debug(
      "config details",
      .field("bar_height", services.config.barHeight),
      .field("padding_x", services.config.barPaddingX),
      .field("extend_behind_notch", services.config.barExtendBehindNotch)
    )
  }

  /// Logs screen geometry visible at startup.
  private func logScreenDetails() {
    if let screen = NSScreen.main ?? NSScreen.screens.first {
      logger.debug(
        "screen details",
        .field("screen_frame", NSStringFromRect(screen.frame)),
        .field("visible", NSStringFromRect(screen.visibleFrame))
      )
    } else {
      logger.warn("no screen available during startup logging")
    }
  }

  /// Logs relevant process environment override keys without exposing values.
  private func logEnvironmentDetails() {
    let env = ProcessInfo.processInfo.environment
    let configOverride = env[SharedEnvironmentKeys.configPath] ?? ""
    let runtimeDirectoryOverride = env[SharedEnvironmentKeys.runtimeDirectory] ?? ""
    let logLevelOverride = env[SharedEnvironmentKeys.loggingLevel] ?? ""
    let calendarAgentSocketOverride = env[SharedEnvironmentKeys.calendarAgentSocketPath] ?? ""
    let networkAgentSocketOverride = env[SharedEnvironmentKeys.networkAgentSocketPath] ?? ""

    logger.debug(
      "environment override",
      .field("key", SharedEnvironmentKeys.configPath),
      .field("value_set", !configOverride.isEmpty)
    )
    logger.debug(
      "environment override",
      .field("key", SharedEnvironmentKeys.runtimeDirectory),
      .field("value_set", !runtimeDirectoryOverride.isEmpty)
    )
    logger.debug(
      "environment override",
      .field("key", SharedEnvironmentKeys.loggingLevel),
      .field("value_set", !logLevelOverride.isEmpty)
    )
    logger.debug(
      "environment override",
      .field("key", SharedEnvironmentKeys.calendarAgentSocketPath),
      .field("value_set", !calendarAgentSocketOverride.isEmpty)
    )
    logger.debug(
      "environment override",
      .field("key", SharedEnvironmentKeys.networkAgentSocketPath),
      .field("value_set", !networkAgentSocketOverride.isEmpty)
    )
  }

  /// Logs the configured environment keys passed to the Lua runtime.
  private func logConfiguredEnvironment(services: AppServices) {
    let environment = services.config.appSection.environment

    guard !environment.isEmpty else {
      logger.debug("app env", .field("key", "<empty>"), .field("value_set", false))
      return
    }

    for key in environment.keys.sorted() {
      let value = environment[key] ?? ""
      logger.debug("app env", .field("key", key), .field("value_set", !value.isEmpty))
    }
  }

  /// Logs one warning when a required font is missing.
  private func validateFont(named fontName: String) {
    if NSFont(name: fontName, size: 12) != nil {
      logger.debug("font available", .field("name", fontName))
      return
    }

    logger.warn(
      "font missing; Nerd Font icons may render incorrectly or be clipped",
      .field("name", fontName)
    )
  }
}
