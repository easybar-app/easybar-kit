import Darwin
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class ConfigLoaderLuaCommandTests: ConfigLoaderTestCase {
  func testReloadAppliesLuaCommandLimits() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("lua-command-limits.toml")

    try """
    [app.lua_commands]
    timeout_seconds = 2.5
    max_output_bytes = 2048
    max_async_jobs = 3
    """.write(to: configFileURL, atomically: true, encoding: .utf8)

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    XCTAssertNil(error)
    XCTAssertEqual(config.luaCommandTimeoutSeconds, 2.5)
    XCTAssertEqual(config.luaCommandMaxOutputBytes, 2048)
    XCTAssertEqual(config.luaCommandMaxAsyncJobs, 3)
  }

  func testReloadRejectsNonPositiveLuaCommandTimeout() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-lua-command-timeout.toml")

    try """
    [app.lua_commands]
    timeout_seconds = 0
    """.write(to: configFileURL, atomically: true, encoding: .utf8)

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard case .invalidValue(let path, let message)? = error as? ConfigError else {
      return XCTFail("Expected invalidValue ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(path, "app.lua_commands.timeout_seconds")
    XCTAssertEqual(message, "expected a value greater than 0")
  }

  func testReloadRejectsNonFiniteLuaCommandTimeout() throws {
    for rawValue in ["nan", "inf", "-inf"] {
      let config = Config.makeUnloadedConfig()
      let configFileURL = tempDirectoryURL.appendingPathComponent(
        "invalid-lua-command-timeout-\(rawValue).toml"
      )

      try """
      [app.lua_commands]
      timeout_seconds = \(rawValue)
      """.write(to: configFileURL, atomically: true, encoding: .utf8)

      setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

      let error = config.reload()

      guard case .invalidValue(let path, let message)? = error as? ConfigError else {
        return XCTFail("Expected invalidValue ConfigError, got \(String(describing: error))")
      }

      XCTAssertEqual(path, "app.lua_commands.timeout_seconds")
      XCTAssertEqual(message, "expected a finite number")
    }
  }

}
