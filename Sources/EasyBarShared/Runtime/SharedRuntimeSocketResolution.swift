import Foundation

/// Describes where one CLI socket path was resolved from.
public enum SharedRuntimeSocketSource: Equatable, Sendable {
  /// The caller supplied an explicit socket path.
  case explicit
  /// The shared runtime configuration supplied the socket path.
  case sharedConfig(path: String)
}

/// One resolved socket path and its source.
public struct SharedRuntimeSocketResolution: Equatable, Sendable {
  /// The path for this shared runtime socket resolution.
  public let path: String
  /// The source for this shared runtime socket resolution.
  public let source: SharedRuntimeSocketSource

  /// Creates one resolved socket path.
  public init(path: String, source: SharedRuntimeSocketSource) {
    self.path = path
    self.source = source
  }
}

/// Socket paths resolved from the shared runtime configuration.
public struct SharedAgentSocketResolutions: Equatable, Sendable {
  /// The calendar for this shared agent socket resolutions.
  public let calendar: SharedRuntimeSocketResolution
  /// The network for this shared agent socket resolutions.
  public let network: SharedRuntimeSocketResolution

  /// Creates one pair of resolved agent socket paths.
  public init(
    calendar: SharedRuntimeSocketResolution,
    network: SharedRuntimeSocketResolution
  ) {
    self.calendar = calendar
    self.network = network
  }
}

/// Resolves CLI socket paths without hiding shared-config failures.
public enum SharedRuntimeSocketResolver {
  /// Resolves the EasyBar control socket. An explicit path bypasses config loading entirely.
  public static func controlSocket(
    explicitPath: String?,
    loadRuntimeConfig: () throws -> SharedRuntimeConfig = SharedRuntimeConfig.load
  ) throws -> SharedRuntimeSocketResolution {
    if let explicitPath {
      return SharedRuntimeSocketResolution(path: explicitPath, source: .explicit)
    }

    let runtime = try loadRuntimeConfig()
    return SharedRuntimeSocketResolution(
      path: runtime.easyBar.socketPath,
      source: .sharedConfig(path: runtime.configPath)
    )
  }

  /// Resolves one calendar-agent socket. An explicit path bypasses config loading entirely.
  public static func calendarAgentSocket(
    explicitPath: String?,
    loadRuntimeConfig: () throws -> SharedRuntimeConfig = SharedRuntimeConfig.load
  ) throws -> SharedRuntimeSocketResolution {
    if let explicitPath {
      return SharedRuntimeSocketResolution(path: explicitPath, source: .explicit)
    }

    let runtime = try loadRuntimeConfig()
    return SharedRuntimeSocketResolution(
      path: runtime.calendarAgent.socketPath,
      source: .sharedConfig(path: runtime.configPath)
    )
  }

  /// Resolves one network-agent socket. An explicit path bypasses config loading entirely.
  public static func networkAgentSocket(
    explicitPath: String?,
    loadRuntimeConfig: () throws -> SharedRuntimeConfig = SharedRuntimeConfig.load
  ) throws -> SharedRuntimeSocketResolution {
    if let explicitPath {
      return SharedRuntimeSocketResolution(path: explicitPath, source: .explicit)
    }

    let runtime = try loadRuntimeConfig()
    return SharedRuntimeSocketResolution(
      path: runtime.networkAgent.socketPath,
      source: .sharedConfig(path: runtime.configPath)
    )
  }

  /// Resolves both agent sockets from one shared-config load.
  public static func agentSockets(
    loadRuntimeConfig: () throws -> SharedRuntimeConfig = SharedRuntimeConfig.load
  ) throws -> SharedAgentSocketResolutions {
    let runtime = try loadRuntimeConfig()
    let source = SharedRuntimeSocketSource.sharedConfig(path: runtime.configPath)

    return SharedAgentSocketResolutions(
      calendar: SharedRuntimeSocketResolution(
        path: runtime.calendarAgent.socketPath,
        source: source
      ),
      network: SharedRuntimeSocketResolution(
        path: runtime.networkAgent.socketPath,
        source: source
      )
    )
  }
}
