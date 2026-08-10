import Darwin
import EasyBarShared
import Foundation
import XCTest

final class SharedRuntimeConfigTests: XCTestCase {
  private let environmentKeys = [
    SharedEnvironmentKeys.configPath,
    SharedEnvironmentKeys.runtimeDirectory,
    SharedEnvironmentKeys.loggingLevel,
    SharedEnvironmentKeys.calendarAgentSocketPath,
    SharedEnvironmentKeys.networkAgentSocketPath,
  ]

  private var originalEnvironment: [String: String?] = [:]
  private var tempDirectoryURL: URL!

  /// Prepares isolated state before each test.
  override func setUpWithError() throws {
    try super.setUpWithError()

    originalEnvironment = environmentKeys.reduce(into: [:]) { result, key in
      result[key] = ProcessInfo.processInfo.environment[key]
    }
    for key in environmentKeys {
      setEnvironmentValue(nil, for: key)
    }
    tempDirectoryURL = try makeTemporaryDirectory()
  }

  /// Restores state mutated by the test fixture.
  override func tearDownWithError() throws {
    restoreEnvironment()

    if let tempDirectoryURL {
      try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    try super.tearDownWithError()
  }

  /// Verifies that load uses the config path environment override and TOML runtime values.
  func testLoadUsesConfigPathEnvironmentOverrideAndTomlValues() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("runtime-config.toml")
    let loggingDirectory = tempDirectoryURL.appendingPathComponent("logs").path
    let runtimeDirectory = tempDirectoryURL.appendingPathComponent("runtime").path
    let luaSocketPath = URL(fileURLWithPath: runtimeDirectory)
      .appendingPathComponent("lua.sock")
      .path
    let calendarSocketPath = URL(fileURLWithPath: runtimeDirectory)
      .appendingPathComponent("calendar.sock")
      .path
    let networkSocketPath = URL(fileURLWithPath: runtimeDirectory)
      .appendingPathComponent("network.sock")
      .path

    try writeConfig(
      """
      [logging]
      level = "trace"
      directory = "\(loggingDirectory)"

      [app]
      runtime_dir = "\(runtimeDirectory)"
      lua_socket_path = "\(luaSocketPath)"

      [agents.calendar]
      socket_path = "\(calendarSocketPath)"

      [agents.network]
      socket_path = "\(networkSocketPath)"
      refresh_interval_seconds = 90
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let runtime = try SharedRuntimeConfig.load()

    XCTAssertEqual(runtime.configPath, configFileURL.path)
    XCTAssertEqual(runtime.logging.level, .trace)
    XCTAssertEqual(runtime.logging.directory, loggingDirectory)
    XCTAssertEqual(runtime.app.runtimeDirectory, runtimeDirectory)
    XCTAssertEqual(
      runtime.easyBar.socketPath, SharedPathDefaults.easyBarSocketPath(in: runtimeDirectory))
    XCTAssertEqual(runtime.app.luaSocketPath, luaSocketPath)
    XCTAssertEqual(runtime.calendarAgent.socketPath, calendarSocketPath)
    XCTAssertEqual(runtime.networkAgent.socketPath, networkSocketPath)
    XCTAssertEqual(runtime.networkAgent.refreshIntervalSeconds, 90)
  }

  /// Verifies that one configured runtime directory drives every derived runtime path.
  func testLoadDerivesRuntimePathsFromConfiguredRuntimeDirectory() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("runtime-directory.toml")
    let runtimeDirectory = tempDirectoryURL.appendingPathComponent("runtime").path

    try writeConfig(
      """
      [app]
      runtime_dir = "\(runtimeDirectory)"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let runtime = try SharedRuntimeConfig.load()

    XCTAssertEqual(runtime.app.runtimeDirectory, runtimeDirectory)
    XCTAssertEqual(runtime.app.lockDirectory, runtimeDirectory)
    XCTAssertEqual(
      runtime.app.luaSocketPath,
      SharedPathDefaults.luaSocketPath(in: runtimeDirectory)
    )
    XCTAssertEqual(
      runtime.easyBar.socketPath,
      SharedPathDefaults.easyBarSocketPath(in: runtimeDirectory)
    )
    XCTAssertEqual(
      runtime.calendarAgent.socketPath,
      SharedPathDefaults.calendarAgentSocketPath(in: runtimeDirectory)
    )
    XCTAssertEqual(
      runtime.networkAgent.socketPath,
      SharedPathDefaults.networkAgentSocketPath(in: runtimeDirectory)
    )
  }

  /// Verifies that EASYBAR_RUNTIME_DIR overrides app.runtime_dir and all derived paths.
  func testLoadPrefersRuntimeDirectoryEnvironmentOverride() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("runtime-directory-env.toml")
    let configuredDirectory = tempDirectoryURL.appendingPathComponent("configured").path
    let environmentDirectory = tempDirectoryURL.appendingPathComponent("environment").path

    try writeConfig(
      """
      [app]
      runtime_dir = "\(configuredDirectory)"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)
    setEnvironmentValue(environmentDirectory, for: SharedEnvironmentKeys.runtimeDirectory)

    let runtime = try SharedRuntimeConfig.load()

    XCTAssertEqual(runtime.app.runtimeDirectory, environmentDirectory)
    XCTAssertEqual(runtime.app.lockDirectory, environmentDirectory)
    XCTAssertEqual(
      runtime.app.luaSocketPath,
      SharedPathDefaults.luaSocketPath(in: environmentDirectory)
    )
    XCTAssertEqual(
      runtime.easyBar.socketPath,
      SharedPathDefaults.easyBarSocketPath(in: environmentDirectory)
    )
    XCTAssertEqual(
      runtime.calendarAgent.socketPath,
      SharedPathDefaults.calendarAgentSocketPath(in: environmentDirectory)
    )
    XCTAssertEqual(
      runtime.networkAgent.socketPath,
      SharedPathDefaults.networkAgentSocketPath(in: environmentDirectory)
    )
  }

  /// Verifies that frontends can share helper agents while isolating their own runtime directory.
  func testLoadPrefersAgentSocketEnvironmentOverrides() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("runtime-agent-env.toml")
    let runtimeDirectory = tempDirectoryURL.appendingPathComponent("native-runtime").path
    let calendarSocketPath = tempDirectoryURL.appendingPathComponent("shared-calendar.sock").path
    let networkSocketPath = tempDirectoryURL.appendingPathComponent("shared-network.sock").path

    try writeConfig(
      """
      [app]
      runtime_dir = "\(runtimeDirectory)"

      [agents.calendar]
      socket_path = "/ignored/calendar.sock"

      [agents.network]
      socket_path = "/ignored/network.sock"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)
    setEnvironmentValue(calendarSocketPath, for: SharedEnvironmentKeys.calendarAgentSocketPath)
    setEnvironmentValue(networkSocketPath, for: SharedEnvironmentKeys.networkAgentSocketPath)

    let runtime = try SharedRuntimeConfig.load()

    XCTAssertEqual(runtime.app.runtimeDirectory, runtimeDirectory)
    XCTAssertEqual(runtime.calendarAgent.socketPath, calendarSocketPath)
    XCTAssertEqual(runtime.networkAgent.socketPath, networkSocketPath)
  }

  /// Verifies that load lets the diagnostic log-level environment override TOML.
  func testLoadPrefersEnvironmentLoggingLevelOverTomlValue() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("runtime-logging-env.toml")

    try writeConfig(
      """
      [logging]
      level = "info"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)
    setEnvironmentValue("trace", for: SharedEnvironmentKeys.loggingLevel)

    let runtime = try SharedRuntimeConfig.load()

    XCTAssertEqual(runtime.configPath, configFileURL.path)
    XCTAssertEqual(runtime.logging.level, .trace)
  }

  /// Verifies that invalid shared TOML fails instead of silently falling back to defaults.
  func testLoadThrowsForInvalidToml() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("runtime-invalid.toml")

    try writeConfig(
      """
      [logging
      level = "info"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertThrowsError(try SharedRuntimeConfig.load()) { error in
      guard case SharedRuntimeConfigError.parseFailure(let path, _) = error else {
        return XCTFail("Expected parseFailure, got \(error)")
      }

      XCTAssertEqual(path, configFileURL.path)
    }
  }

  /// Verifies that shared helper config rejects invalid network intervals.
  func testLoadThrowsForNegativeNetworkAgentRefreshInterval() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("runtime-negative-network.toml")

    try writeConfig(
      """
      [agents.network]
      refresh_interval_seconds = -1
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertThrowsError(try SharedRuntimeConfig.load()) { error in
      guard case SharedRuntimeConfigError.invalidValue(let path, _) = error else {
        return XCTFail("Expected invalidValue, got \(error)")
      }

      XCTAssertEqual(path, "agents.network.refresh_interval_seconds")
    }
  }

  /// Verifies that shared runtime config rejects wrong TOML value types.
  func testLoadThrowsForInvalidSharedRuntimeValueType() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("runtime-invalid-type.toml")

    try writeConfig(
      """
      [logging]
      enabled = "yes"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertThrowsError(try SharedRuntimeConfig.load()) { error in
      guard case SharedRuntimeConfigError.invalidType(let path, let expected, _) = error else {
        return XCTFail("Expected invalidType, got \(error)")
      }

      XCTAssertEqual(path, "logging.enabled")
      XCTAssertEqual(expected, "bool")
    }
  }

  /// Verifies that invalid TOML logging levels are rejected instead of ignored.
  func testLoadThrowsForInvalidTomlLoggingLevel() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("runtime-invalid-log-level.toml")

    try writeConfig(
      """
      [logging]
      level = "verbose"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertThrowsError(try SharedRuntimeConfig.load()) { error in
      guard case SharedRuntimeConfigError.invalidValue(let path, _) = error else {
        return XCTFail("Expected invalidValue, got \(error)")
      }

      XCTAssertEqual(path, "logging.level")
    }
  }

  /// Verifies that an explicit CLI socket bypasses malformed shared configuration.
  func testSocketResolverExplicitPathBypassesConfigLoading() throws {
    let explicitPath = tempDirectoryURL.appendingPathComponent("explicit.sock").path
    var loadCount = 0

    let resolution = try SharedRuntimeSocketResolver.controlSocket(
      explicitPath: explicitPath,
      loadRuntimeConfig: {
        loadCount += 1
        throw SharedRuntimeConfigError.parseFailure(path: "bad.toml", message: "invalid")
      }
    )

    XCTAssertEqual(resolution.path, explicitPath)
    XCTAssertEqual(resolution.source, .explicit)
    XCTAssertEqual(loadCount, 0)
  }

  /// Verifies that malformed shared configuration is not hidden by socket defaults.
  func testSocketResolverPropagatesSharedConfigFailure() {
    XCTAssertThrowsError(
      try SharedRuntimeSocketResolver.controlSocket(
        explicitPath: nil,
        loadRuntimeConfig: {
          throw SharedRuntimeConfigError.parseFailure(path: "bad.toml", message: "invalid")
        }
      )
    ) { error in
      XCTAssertEqual(
        error as? SharedRuntimeConfigError,
        .parseFailure(path: "bad.toml", message: "invalid")
      )
    }
  }

  /// Verifies that both agent paths come from one shared runtime config load.
  func testSocketResolverLoadsBothAgentPathsOnce() throws {
    let runtime = SharedRuntimeConfig.environmentDefaults()
    var loadCount = 0

    let resolutions = try SharedRuntimeSocketResolver.agentSockets {
      loadCount += 1
      return runtime
    }

    XCTAssertEqual(loadCount, 1)
    XCTAssertEqual(resolutions.calendar.path, runtime.calendarAgent.socketPath)
    XCTAssertEqual(resolutions.network.path, runtime.networkAgent.socketPath)
    XCTAssertEqual(resolutions.calendar.source, .sharedConfig(path: runtime.configPath))
    XCTAssertEqual(resolutions.network.source, .sharedConfig(path: runtime.configPath))
  }

}

extension SharedRuntimeConfigTests {
  /// Creates an isolated temporary directory for file-system assertions.
  fileprivate func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "easybar-shared-runtime-tests-\(UUID().uuidString)",
        isDirectory: true
      )

    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    return directoryURL
  }

  /// Writes a TOML fixture to the current test config path.
  fileprivate func writeConfig(_ content: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  /// Sets or clears one environment variable while preserving its original value.
  fileprivate func setEnvironmentValue(_ value: String?, for key: String) {
    if let value {
      setenv(key, value, 1)
    } else {
      unsetenv(key)
    }
  }

  /// Restores environment variables captured before the test.
  fileprivate func restoreEnvironment() {
    for key in environmentKeys {
      setEnvironmentValue(originalEnvironment[key] ?? nil, for: key)
    }
  }
}
