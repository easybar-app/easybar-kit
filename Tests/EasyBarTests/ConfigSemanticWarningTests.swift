import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class ConfigSemanticWarningTests: ConfigLoaderTestCase {
  func testReloadWarnsWhenEnabledSpacesHaveNoVisibleContent() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("spaces-without-content.toml")

    try writeConfig(
      """
      [builtins.spaces]
      enabled = true

      [builtins.spaces.layout]
      show_label = false
      show_icons = false
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertNil(config.reload())
    XCTAssertEqual(
      config.configWarnings,
      [ConfigSemanticWarningBuilder.spacesWithoutVisibleContent]
    )
  }

  func testValidateConfigReportsSpacesWithoutVisibleContent() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("validate-spaces.toml")

    try writeConfig(
      """
      [builtins.spaces.layout]
      show_label = false
      show_icons = false
      """,
      to: configFileURL
    )

    let result = try ConfigValidator.validate(configPathOverride: configFileURL.path)

    XCTAssertEqual(
      result.warnings,
      [ConfigSemanticWarningBuilder.spacesWithoutVisibleContent]
    )
  }

  func testDisabledSpacesDoNotWarnAboutMissingContent() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("disabled-spaces.toml")

    try writeConfig(
      """
      [builtins.spaces]
      enabled = false

      [builtins.spaces.layout]
      show_label = false
      show_icons = false
      """,
      to: configFileURL
    )

    let result = try ConfigValidator.validate(configPathOverride: configFileURL.path)

    XCTAssertEqual(result.warnings, [])
  }

  func testSpacesWithAnyVisibleContentDoNotWarn() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("visible-spaces.toml")

    try writeConfig(
      """
      [builtins.spaces.layout]
      show_label = true
      show_icons = false
      """,
      to: configFileURL
    )

    let result = try ConfigValidator.validate(configPathOverride: configFileURL.path)

    XCTAssertEqual(result.warnings, [])
  }
}
