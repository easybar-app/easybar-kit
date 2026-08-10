import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class ConfigLoaderSpacerTests: ConfigLoaderTestCase {
  func testReloadParsesPredefinedAndMultipleNamedSpacers() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("spacers.toml")

    try writeConfig(
      """
      [builtins.groups.system]
      position = "right"
      order = 40

      [builtins.privacy_spacer]
      enabled = true
      position = "right"
      order = 1000
      group = "system"
      width = 24

      [builtins.spacers.before_clock]
      position = "right"
      order = 55
      width = 8

      [builtins.spacers.center_gap]
      enabled = false
      position = "center"
      order = 3
      group = "system"
      width = 12
      """,
      to: configFileURL
    )
    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertNil(config.reload())
    XCTAssertTrue(config.builtinPrivacySpacer.enabled)
    XCTAssertEqual(config.builtinPrivacySpacer.placement.groupID, "system")
    XCTAssertEqual(config.builtinPrivacySpacer.width, 24)
    XCTAssertEqual(config.builtinSpacers.map(\.id), ["before_clock", "center_gap"])

    let beforeClock = try XCTUnwrap(
      config.builtinSpacers.first { $0.id == "before_clock" }
    )
    XCTAssertTrue(beforeClock.config.enabled)
    XCTAssertEqual(beforeClock.config.position, .right)
    XCTAssertEqual(beforeClock.config.order, 55)
    XCTAssertEqual(beforeClock.config.width, 8)

    let centerGap = try XCTUnwrap(
      config.builtinSpacers.first { $0.id == "center_gap" }
    )
    XCTAssertFalse(centerGap.config.enabled)
    XCTAssertEqual(centerGap.config.position, .center)
    XCTAssertEqual(centerGap.config.order, 3)
    XCTAssertEqual(centerGap.config.placement.groupID, "system")
    XCTAssertEqual(centerGap.config.width, 12)
  }

  func testPrivacySpacerDefaultsToEnabledAndTwelvePoints() {
    let config = Config.makeUnloadedConfig()

    XCTAssertTrue(config.builtinPrivacySpacer.enabled)
    XCTAssertEqual(config.builtinPrivacySpacer.width, 12)
  }

  func testRemovedAutomaticSettingsAreReportedAsUnknown() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("removed-automatic-settings.toml")

    try writeConfig(
      """
      [builtins.privacy_spacer]
      mode = "automatic"
      collapse_delay_seconds = 2
      width = 12
      """,
      to: configFileURL
    )

    let result = try ConfigValidator.validate(configPathOverride: configFileURL.path)
    XCTAssertEqual(
      result.warnings,
      [
        "unknown config key builtins.privacy_spacer.collapse_delay_seconds",
        "unknown config key builtins.privacy_spacer.mode",
      ]
    )
  }

  func testNamedSpacerSectionsAreRecognizedByUnknownKeyValidation() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("spacer-validation.toml")

    try writeConfig(
      """
      [builtins.spacers.before_clock]
      enabled = true
      position = "right"
      order = 55
      width = 8
      """,
      to: configFileURL
    )

    let validResult = try ConfigValidator.validate(configPathOverride: configFileURL.path)
    XCTAssertEqual(validResult.warnings, [])

    try writeConfig(
      """
      [builtins.spacers.before_clock]
      widht = 8
      """,
      to: configFileURL
    )

    let invalidResult = try ConfigValidator.validate(configPathOverride: configFileURL.path)
    XCTAssertEqual(
      invalidResult.warnings,
      ["unknown config key builtins.spacers.before_clock.widht"]
    )
  }
}
