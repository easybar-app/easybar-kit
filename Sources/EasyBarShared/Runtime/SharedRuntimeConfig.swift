import Foundation

/// Resolved runtime config shared by helper processes and the CLI.
public struct SharedRuntimeConfig {
  /// The config path for this shared runtime config.
  public let configPath: String
  /// The app for this shared runtime config.
  public let app: SharedAppRuntimeConfig
  /// The logging for this shared runtime config.
  public let logging: SharedLoggingRuntimeConfig
  /// The EasyBar for this shared runtime config.
  public let easyBar: SharedEasyBarRuntimeConfig
  /// The calendar agent for this shared runtime config.
  public let calendarAgent: SharedCalendarAgentRuntimeConfig
  /// The network agent for this shared runtime config.
  public let networkAgent: SharedNetworkAgentRuntimeConfig

  /// Loads the shared runtime config once from env, defaults, and config.toml.
  public static func load() throws -> SharedRuntimeConfig {
    let configPath = resolvedConfigPath()
    let toml = try parsedConfig(at: configPath)
    let reader = sharedRuntimeConfigReader(for: toml)

    let app = try resolvedAppConfig(from: reader)
    let logging = try resolvedLoggingConfig(from: reader)
    let easyBar = resolvedEasyBarConfig(runtimeDirectory: app.runtimeDirectory)
    let calendarAgent = try resolvedCalendarAgentConfig(
      from: reader,
      runtimeDirectory: app.runtimeDirectory
    )
    let networkAgent = try resolvedNetworkAgentConfig(
      from: reader,
      runtimeDirectory: app.runtimeDirectory
    )

    return SharedRuntimeConfig(
      configPath: configPath,
      app: app,
      logging: logging,
      easyBar: easyBar,
      calendarAgent: calendarAgent,
      networkAgent: networkAgent
    )
  }

  /// Resolves runtime defaults from environment overrides and built-in fallbacks only.
  public static func environmentDefaults() -> SharedRuntimeConfig {
    let app = resolvedAppEnvironmentDefaults()

    return SharedRuntimeConfig(
      configPath: resolvedConfigPath(),
      app: app,
      logging: resolvedLoggingEnvironmentDefaults(),
      easyBar: resolvedEasyBarConfig(runtimeDirectory: app.runtimeDirectory),
      calendarAgent: resolvedCalendarAgentEnvironmentDefaults(
        runtimeDirectory: app.runtimeDirectory
      ),
      networkAgent: resolvedNetworkAgentEnvironmentDefaults(
        runtimeDirectory: app.runtimeDirectory
      )
    )
  }
}

/// Resolved app-level values shared by helper processes.
public struct SharedAppRuntimeConfig {
  /// The runtime directory for this shared app runtime config.
  public let runtimeDirectory: String
  /// The widgets path for this shared app runtime config.
  public let widgetsPath: String
  /// The lock directory for this shared app runtime config.
  public let lockDirectory: String
  /// The Lua socket path for this shared app runtime config.
  public let luaSocketPath: String
  /// The widget editor stub path for this shared app runtime config.
  public let widgetEditorStubPath: String

  /// Creates one app runtime config.
  public init(
    runtimeDirectory: String,
    widgetsPath: String,
    lockDirectory: String,
    luaSocketPath: String,
    widgetEditorStubPath: String
  ) {
    self.runtimeDirectory = runtimeDirectory
    self.widgetsPath = widgetsPath
    self.lockDirectory = lockDirectory
    self.luaSocketPath = luaSocketPath
    self.widgetEditorStubPath = widgetEditorStubPath
  }
}

/// Resolved logging values shared by helper processes.
public struct SharedLoggingRuntimeConfig {
  /// Whether this shared logging runtime config is enabled.
  public let enabled: Bool
  /// The level for this shared logging runtime config.
  public let level: ProcessLogLevel
  /// The directory for this shared logging runtime config.
  public let directory: String

  /// Creates one logging runtime config.
  public init(
    enabled: Bool,
    level: ProcessLogLevel,
    directory: String
  ) {
    self.enabled = enabled
    self.level = level
    self.directory = directory
  }
}

/// Resolved EasyBar socket values shared by helper processes.
public struct SharedEasyBarRuntimeConfig {
  /// The socket path for this shared EasyBar runtime config.
  public let socketPath: String

  /// Creates one EasyBar socket config.
  public init(socketPath: String) {
    self.socketPath = socketPath
  }
}

/// Resolved calendar-agent values shared by helper processes.
public struct SharedCalendarAgentRuntimeConfig {
  /// Whether this shared calendar agent runtime config is enabled.
  public let enabled: Bool
  /// The socket path for this shared calendar agent runtime config.
  public let socketPath: String

  /// Creates one calendar-agent runtime config.
  public init(
    enabled: Bool,
    socketPath: String
  ) {
    self.enabled = enabled
    self.socketPath = socketPath
  }
}

/// Resolved network-agent values shared by helper processes.
public struct SharedNetworkAgentRuntimeConfig {
  /// Whether this shared network agent runtime config is enabled.
  public let enabled: Bool
  /// The socket path for this shared network agent runtime config.
  public let socketPath: String
  /// The refresh interval seconds for this shared network agent runtime config.
  public let refreshIntervalSeconds: TimeInterval
  /// Whether the allow unauthorized fields without location option is enabled for this shared network agent runtime config.
  public let allowUnauthorizedFieldsWithoutLocation: Bool

  /// Creates one network-agent runtime config.
  public init(
    enabled: Bool,
    socketPath: String,
    refreshIntervalSeconds: TimeInterval,
    allowUnauthorizedFieldsWithoutLocation: Bool
  ) {
    self.enabled = enabled
    self.socketPath = socketPath
    self.refreshIntervalSeconds = refreshIntervalSeconds
    self.allowUnauthorizedFieldsWithoutLocation = allowUnauthorizedFieldsWithoutLocation
  }
}
