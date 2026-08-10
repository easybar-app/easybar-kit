import Darwin
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class ConfigLoaderLoggingTests: ConfigLoaderTestCase {
  /// Verifies that reload returns config error for invalid logging level.
  func testReloadReturnsConfigErrorForInvalidLoggingLevel() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid.toml")

    try writeConfig(
      """
      [logging]
      level = "verbose"
      """,
      to: configFileURL
    )

    config.loggingLevel = .warn
    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard let configError = error as? ConfigError else {
      return XCTFail("Expected ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(configError.configPath, "logging.level")
    XCTAssertEqual(configError.detail, "expected one of debug, error, info, trace, warn")
    XCTAssertEqual(config.loggingLevel, .warn)
  }

  /// Verifies that reload returns invalid type for logging enabled string value.
  func testReloadReturnsInvalidTypeForLoggingEnabledStringValue() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-logging-type.toml")

    try writeConfig(
      """
      [logging]
      enabled = "yes"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard case .invalidType(let path, let expected, let actual)? = error as? ConfigError else {
      return XCTFail("Expected invalidType ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(path, "logging.enabled")
    XCTAssertEqual(expected, "bool")
    XCTAssertEqual(actual, "string(yes)")
  }

  /// Verifies that reload applies logging level from TOML.
  func testReloadAppliesLoggingLevelFromToml() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("logging-level.toml")

    try writeConfig(
      """
      [logging]
      level = "trace"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    XCTAssertNil(error)
    XCTAssertEqual(config.loggingLevel, .trace)
  }

  /// Verifies that reload prefers the diagnostic log-level environment override over TOML.
  func testReloadPrefersEnvironmentLoggingLevelOverTomlValue() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("env-logging-level.toml")

    try writeConfig(
      """
      [logging]
      level = "info"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)
    setEnvironmentValue("debug", for: SharedEnvironmentKeys.loggingLevel)

    let error = config.reload()

    XCTAssertNil(error)
    XCTAssertEqual(config.loggingLevel, .debug)
  }

}
