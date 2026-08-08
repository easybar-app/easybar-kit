import Foundation

/// Shared filesystem and runtime defaults used across EasyBar targets.
public enum SharedPathDefaults {
  static let defaultConfigRelativePath = ".config/easybar/config.toml"
  static let defaultWidgetsRelativePath = ".config/easybar/widgets"
  static let defaultRuntimeDirectoryRelativePath = ".local/state/easybar/runtime"
  static let defaultLoggingDirectoryRelativePath = ".local/state/easybar"
  static let defaultWidgetEditorStubRelativePath = ".local/share/easybar/easybar_api.lua"
  static let defaultWidgetPackagesRelativePath = ".local/share/easybar/packages"

  public static let defaultLuaPath = "lua"
  public static let defaultLuaEnvironment: [String: String] = [
    SharedEnvironmentKeys.path: "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  ]

  /// Returns the user-scoped default runtime directory for sockets and locks.
  public static func defaultRuntimeDirectory() -> URL {
    homeRelativePath(defaultRuntimeDirectoryRelativePath)
  }

  /// Returns the EasyBar control socket path derived from one runtime directory.
  public static func easyBarSocketPath(in runtimeDirectory: String) -> String {
    runtimePath("easybar.sock", in: runtimeDirectory)
  }

  /// Returns the Lua transport socket path derived from one runtime directory.
  public static func luaSocketPath(in runtimeDirectory: String) -> String {
    runtimePath("lua-runtime.sock", in: runtimeDirectory)
  }

  /// Returns the calendar-agent socket path derived from one runtime directory.
  public static func calendarAgentSocketPath(in runtimeDirectory: String) -> String {
    runtimePath("calendar-agent.sock", in: runtimeDirectory)
  }

  /// Returns the network-agent socket path derived from one runtime directory.
  public static func networkAgentSocketPath(in runtimeDirectory: String) -> String {
    runtimePath("network-agent.sock", in: runtimeDirectory)
  }

  /// Returns an absolute path by resolving one home-relative path.
  public static func homeRelativePath(_ relativePath: String) -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(relativePath)
  }

  /// Returns the default config path in the current user's home directory.
  public static func defaultConfigPath() -> URL {
    homeRelativePath(defaultConfigRelativePath)
  }

  /// Returns the default widgets path in the current user's home directory.
  public static func defaultWidgetsPath() -> URL {
    homeRelativePath(defaultWidgetsRelativePath)
  }

  /// Returns the default logging directory in the current user's home directory.
  public static func defaultLoggingDirectory() -> URL {
    homeRelativePath(defaultLoggingDirectoryRelativePath)
  }

  /// Returns the default widget editor stub path in the current user's home directory.
  public static func defaultWidgetEditorStubPath() -> URL {
    homeRelativePath(defaultWidgetEditorStubRelativePath)
  }

  /// Returns the managed widget package root in the current user's data directory.
  public static func defaultWidgetPackagesPath() -> URL {
    homeRelativePath(defaultWidgetPackagesRelativePath)
  }

  /// Returns one child path within the provided runtime directory.
  private static func runtimePath(_ component: String, in runtimeDirectory: String) -> String {
    URL(fileURLWithPath: runtimeDirectory, isDirectory: true)
      .appendingPathComponent(component)
      .path
  }
}
