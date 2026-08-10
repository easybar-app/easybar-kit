import Foundation

/// Returns the resolved EasyBar socket config derived from the runtime directory.
func resolvedEasyBarConfig(runtimeDirectory: String) -> SharedEasyBarRuntimeConfig {
  SharedEasyBarRuntimeConfig(
    socketPath: SharedPathDefaults.easyBarSocketPath(in: runtimeDirectory)
  )
}

/// Returns the resolved calendar-agent config from TOML and defaults.
func resolvedCalendarAgentConfig(
  from reader: SharedRuntimeConfigReader,
  runtimeDirectory: String
) throws -> SharedCalendarAgentRuntimeConfig {
  let calendar = try reader.section("agents.calendar")

  return SharedCalendarAgentRuntimeConfig(
    enabled: try calendar.bool("enabled", fallback: true),
    socketPath: try
      (expandedEnvironmentPath(named: SharedEnvironmentKeys.calendarAgentSocketPath)
      ?? calendar.expandedPath(
        "socket_path",
        fallback: SharedPathDefaults.calendarAgentSocketPath(in: runtimeDirectory)
      )),
  )
}

/// Returns the resolved calendar-agent defaults.
func resolvedCalendarAgentEnvironmentDefaults(
  runtimeDirectory: String
) -> SharedCalendarAgentRuntimeConfig {
  SharedCalendarAgentRuntimeConfig(
    enabled: true,
    socketPath:
      expandedEnvironmentPath(named: SharedEnvironmentKeys.calendarAgentSocketPath)
      ?? SharedPathDefaults.calendarAgentSocketPath(in: runtimeDirectory)
  )
}

/// Returns the resolved network-agent config from TOML and defaults.
func resolvedNetworkAgentConfig(
  from reader: SharedRuntimeConfigReader,
  runtimeDirectory: String
) throws -> SharedNetworkAgentRuntimeConfig {
  let network = try reader.section("agents.network")

  return SharedNetworkAgentRuntimeConfig(
    enabled: try network.bool("enabled", fallback: true),
    socketPath: try
      (expandedEnvironmentPath(named: SharedEnvironmentKeys.networkAgentSocketPath)
      ?? network.expandedPath(
        "socket_path",
        fallback: SharedPathDefaults.networkAgentSocketPath(in: runtimeDirectory)
      )),
    refreshIntervalSeconds: try network.double(
      "refresh_interval_seconds",
      fallback: 60,
      minimum: 0
    ),
    allowUnauthorizedFieldsWithoutLocation: try network.bool(
      "allow_unauthorized_non_sensitive_fields",
      fallback: false
    )
  )
}

/// Returns the resolved network-agent defaults.
func resolvedNetworkAgentEnvironmentDefaults(
  runtimeDirectory: String
) -> SharedNetworkAgentRuntimeConfig {
  SharedNetworkAgentRuntimeConfig(
    enabled: true,
    socketPath:
      expandedEnvironmentPath(named: SharedEnvironmentKeys.networkAgentSocketPath)
      ?? SharedPathDefaults.networkAgentSocketPath(in: runtimeDirectory),
    refreshIntervalSeconds: 60,
    allowUnauthorizedFieldsWithoutLocation: false
  )
}
