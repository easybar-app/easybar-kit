import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarApp

final class ConfigEnvironmentValidationTests: ConfigLoaderTestCase {
  func testPathConfigurationPreservesMissingEmptyAndExplicitStates() {
    let defaultEnvironment = Config.mergedAppEnvironment(with: [:])
    XCTAssertEqual(
      defaultEnvironment[SharedEnvironmentKeys.path],
      SharedPathDefaults.defaultLuaEnvironment[SharedEnvironmentKeys.path]
    )

    let inheritedEnvironment = Config.mergedAppEnvironment(with: [
      SharedEnvironmentKeys.path: "",
      "EMPTY_VALUE": "",
    ])
    XCTAssertNil(inheritedEnvironment[SharedEnvironmentKeys.path])
    XCTAssertEqual(inheritedEnvironment["EMPTY_VALUE"], "")

    let explicitEnvironment = Config.mergedAppEnvironment(with: [
      SharedEnvironmentKeys.path: "/custom/bin"
    ])
    XCTAssertEqual(explicitEnvironment[SharedEnvironmentKeys.path], "/custom/bin")
  }

  func testReloadTreatsEmptyPathAsNoConfiguredOverride() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("empty-path.toml")
    try writeConfig(
      """
      [app.env]
      PATH = ""
      FOO = "bar"
      """,
      to: configFileURL
    )
    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertNil(config.reload())
    XCTAssertNil(config.appSection.environment[SharedEnvironmentKeys.path])
    XCTAssertEqual(config.appSection.environment["FOO"], "bar")
  }

  func testReloadRejectsEnvironmentKeyThatCannotBeEncodedInEnvp() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-environment.toml")
    try writeConfig(
      """
      [app.env]
      "BAD=KEY" = "value"
      """,
      to: configFileURL
    )
    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = try XCTUnwrap(config.reload())
    let configError = try XCTUnwrap(error as? ConfigError)

    XCTAssertEqual(configError.configPath, "app.env")
    XCTAssertTrue(configError.localizedDescription.contains("invalid process environment key"))
  }
}
