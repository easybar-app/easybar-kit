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

  /// Public bootstrap override for the directory containing hand-written Lua widgets.
  public static let widgetsDirectory = "EASYBAR_WIDGETS_DIR"

  /// Public bootstrap override for the managed widget package root.
  public static let widgetPackagesDirectory = "EASYBAR_WIDGET_PACKAGES_DIR"

  /// Public bootstrap override for the process log directory.
  public static let loggingDirectory = "EASYBAR_LOGGING_DIR"

  /// Public bootstrap override for the generated Lua editor stub path.
  public static let widgetEditorStubPath = "EASYBAR_WIDGET_EDITOR_STUB_PATH"

  /// Optional diagnostic override for the configured logging level.
  public static let loggingLevel = "EASYBAR_LOG_LEVEL"

  /// Optional bootstrap override for the calendar-agent socket.
  public static let calendarAgentSocketPath = "EASYBAR_CALENDAR_AGENT_SOCKET_PATH"

  /// Optional bootstrap override for the network-agent socket.
  public static let networkAgentSocketPath = "EASYBAR_NETWORK_AGENT_SOCKET_PATH"

  /// Internal key used to customize the shared CLI command name for one frontend.
  public static let cliName = "EASYBAR_INTERNAL_CLI_NAME"

  /// Internal key used to customize the shared CLI display name for one frontend.
  public static let cliDisplayName = "EASYBAR_INTERNAL_CLI_DISPLAY_NAME"

  /// Internal key used to hide helper-agent commands from frontends that do not own them.
  public static let cliSupportsHelperAgents = "EASYBAR_INTERNAL_CLI_SUPPORTS_HELPER_AGENTS"

  /// Internal key used to expose the active frontend display name to shared native menus.
  public static let frontendDisplayName = "EASYBAR_INTERNAL_FRONTEND_DISPLAY_NAME"

  /// Internal key used to expose the active frontend built-in surface policy to shared menus.
  public static let frontendBuiltInSurfacePolicy =
    "EASYBAR_INTERNAL_FRONTEND_BUILTIN_SURFACE_POLICY"

  /// Internal key used to pass the resolved active theme to the Lua runtime.
  public static let luaThemeJSON = "EASYBAR_INTERNAL_THEME_JSON"

  /// Internal key used to expose the resolved logging directory to Lua widgets.
  public static let luaLoggingDirectory = "EASYBAR_INTERNAL_LOGGING_DIRECTORY"

  /// Internal key used to expose activated package entrypoints and modules to the Lua runtime.
  public static let luaWidgetPackagesDirectory = "EASYBAR_INTERNAL_WIDGET_PACKAGES_DIRECTORY"
}
