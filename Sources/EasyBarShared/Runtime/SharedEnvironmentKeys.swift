import Foundation

/// Central registry of environment variable names used by EasyBar's Swift targets.
///
/// Normal runtime behavior should be configured in `config.toml`. Public
/// overrides are limited to values needed before or around config loading.
/// Internal keys are reserved for passing resolved runtime state to child
/// processes owned by EasyBar.
public enum SharedEnvironmentKeys {
  /// Standard executable search path inherited by launched processes.
  public static let path = "PATH"

  /// Public bootstrap override for the runtime config path.
  public static let configPath = "EASYBAR_CONFIG_PATH"

  /// Public override for the directory containing runtime sockets and lock files.
  public static let runtimeDirectory = "EASYBAR_RUNTIME_DIR"

  /// Optional diagnostic override for the configured logging level.
  public static let loggingLevel = "EASYBAR_LOG_LEVEL"

  /// Optional bootstrap override for the calendar-agent socket.
  public static let calendarAgentSocketPath = "EASYBAR_CALENDAR_AGENT_SOCKET_PATH"

  /// Optional bootstrap override for the network-agent socket.
  public static let networkAgentSocketPath = "EASYBAR_NETWORK_AGENT_SOCKET_PATH"

  /// Internal key used to pass the resolved active theme to the Lua runtime.
  public static let luaThemeJSON = "EASYBAR_INTERNAL_THEME_JSON"

  /// Internal key used to expose the resolved logging directory to Lua widgets.
  public static let luaLoggingDirectory = "EASYBAR_INTERNAL_LOGGING_DIRECTORY"

  /// Internal key used to expose activated package entrypoints and modules to the Lua runtime.
  public static let luaWidgetPackagesDirectory = "EASYBAR_INTERNAL_WIDGET_PACKAGES_DIRECTORY"
}
