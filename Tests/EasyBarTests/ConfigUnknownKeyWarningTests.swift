import EasyBarConfigSchema
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class ConfigUnknownKeyWarningTests: ConfigLoaderTestCase {
  /// Verifies that validate-config reports typoed keys without rejecting the config.
  func testValidateConfigWarnsAboutUnknownScalarKey() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("unknown-key.toml")

    try writeConfig(
      """
      [builtins.cpu.content]
      histroy_size = 10
      """,
      to: configFileURL
    )

    let result = try ConfigValidator.validate(configPathOverride: configFileURL.path)

    XCTAssertEqual(result.configPath, configFileURL.path)
    XCTAssertEqual(result.warnings, ["unknown config key builtins.cpu.content.histroy_size"])
  }

  /// Verifies that validate-config reports unknown sections once without noisy child warnings.
  func testValidateConfigWarnsAboutUnknownSection() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("unknown-section.toml")

    try writeConfig(
      """
      [builtins.cpu.contnet]
      history_size = 10
      """,
      to: configFileURL
    )

    let result = try ConfigValidator.validate(configPathOverride: configFileURL.path)

    XCTAssertEqual(result.warnings, ["unknown config section builtins.cpu.contnet"])
  }

  /// Verifies that removed calendar keys are reported as unknown.
  func testValidateConfigWarnsAboutRemovedMonthAnchorKeys() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("removed-anchor-key.toml")

    try writeConfig(
      """
      [builtins.calendar.month.popup.anchor]
      anchor_date_format = "EEE d MMM"
      """,
      to: configFileURL
    )

    let result = try ConfigValidator.validate(configPathOverride: configFileURL.path)

    XCTAssertEqual(
      result.warnings,
      ["unknown config key builtins.calendar.month.popup.anchor.anchor_date_format"]
    )
  }

  /// Verifies that removed inbox icon keys remain unsupported instead of being migrated.
  func testRemovedInboxIconKeysAreUnknownAndDoNotChangeStateStyle() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("removed-inbox-icon-keys.toml")

    try writeConfig(
      """
      [builtins.inbox.style]
      icon = "OLD_UNREAD"
      icon_color = "#111111"
      text_color = "#333333"

      [builtins.inbox.content]
      inactive_icon = "OLD_READ"
      inactive_color = "#222222"
      """,
      to: configFileURL
    )

    let result = try ConfigValidator.validate(configPathOverride: configFileURL.path)

    XCTAssertEqual(
      result.warnings,
      [
        "unknown config key builtins.inbox.content.inactive_color",
        "unknown config key builtins.inbox.content.inactive_icon",
        "unknown config key builtins.inbox.style.icon",
        "unknown config key builtins.inbox.style.icon_color",
        "unknown config key builtins.inbox.style.text_color",
      ]
    )

    let config = Config.makeUnloadedConfig()
    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)
    XCTAssertNil(config.reload())
    XCTAssertEqual(
      config.builtinInbox.style.unreadIcon,
      Config.InboxBuiltinConfig.default.style.unreadIcon
    )
    XCTAssertEqual(
      config.builtinInbox.style.readIcon,
      Config.InboxBuiltinConfig.default.style.readIcon
    )
    XCTAssertEqual(
      config.builtinInbox.style.unreadIconColorHex,
      config.themeTextSecondaryColorHex
    )
    XCTAssertEqual(
      config.builtinInbox.style.readIconColorHex,
      config.themeMutedColorHex
    )
  }

  /// Verifies that custom-rendered built-ins reject generic content style keys they cannot use.
  func testCustomRenderedBuiltinsRejectUnusedContentStyleKeys() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("unused-content-style-keys.toml")

    try writeConfig(
      """
      [builtins.spaces]
      icon = "UNUSED"
      text_color = "#111111"

      [builtins.aerospace_mode.style]
      icon = "UNUSED"

      [builtins.volume.style]
      icon = "UNUSED"

      [builtins.wifi.style]
      icon = "UNUSED"
      text_color = "#222222"
      """,
      to: configFileURL
    )

    let result = try ConfigValidator.validate(configPathOverride: configFileURL.path)

    XCTAssertEqual(
      result.warnings,
      [
        "unknown config key builtins.aerospace_mode.style.icon",
        "unknown config key builtins.spaces.icon",
        "unknown config key builtins.spaces.text_color",
        "unknown config key builtins.volume.style.icon",
        "unknown config key builtins.wifi.style.icon",
        "unknown config key builtins.wifi.style.text_color",
      ]
    )
  }

  /// Verifies that intentionally dynamic config tables do not produce unknown-key warnings.
  func testValidateConfigDoesNotWarnForDynamicTables() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("dynamic-tables.toml")

    try writeConfig(
      """
      [app.env]
      CUSTOM_TOOL = "/usr/local/bin/tool"

      [builtins.groups.status]
      position = "right"
      order = 30

      [builtins.groups.status.style]
      background_color = "theme.surface"

      [builtins.calendar.composer.alert_labels]
      tomorrow_morning = "Tomorrow morning"

      [widgets.github-inbox]
      merge_method = "squash"
      arbitrary_flag = true
      """,
      to: configFileURL
    )

    let result = try ConfigValidator.validate(configPathOverride: configFileURL.path)

    XCTAssertEqual(result.warnings, [])
  }

  /// Verifies that the checked-in default config stays covered by the known-key schema.
  func testDefaultConfigContainsOnlyKnownKeys() throws {
    let defaultConfigURL = repoRootURL().appendingPathComponent("config.defaults.toml")

    let result = try ConfigValidator.validate(configPathOverride: defaultConfigURL.path)

    XCTAssertEqual(result.warnings, [])
  }

  /// Verifies that active and commented keys documented in config.defaults.toml stay covered.
  func testDocumentedDefaultConfigKeysAreCoveredByKnownKeySchema() throws {
    let defaultConfigURL = repoRootURL().appendingPathComponent("config.defaults.toml")
    let text = try String(contentsOf: defaultConfigURL, encoding: .utf8)
    let documentedKeys = documentedConfigKeys(from: text)

    XCTAssertFalse(documentedKeys.isEmpty)

    for documentedKey in documentedKeys {
      XCTAssertTrue(
        ConfigSchemaRegistry.isKnownSection(documentedKey.section),
        "Unknown documented config section \(documentedKey.section)"
      )

      guard !ConfigSchemaRegistry.isFreeFormSection(documentedKey.section) else {
        continue
      }

      XCTAssertTrue(
        ConfigSchemaRegistry.knownKeys(for: documentedKey.section).contains(documentedKey.key),
        "Unknown documented config key \(documentedKey.section).\(documentedKey.key)"
      )
    }
  }
}

private struct DocumentedConfigKey {
  let section: String
  let key: String
}

private func documentedConfigKeys(from text: String) -> [DocumentedConfigKey] {
  var section = ""
  var keys: [DocumentedConfigKey] = []

  for rawLine in text.components(separatedBy: .newlines) {
    guard let line = normalizedConfigLine(rawLine) else { continue }

    if line.hasPrefix("[") && line.hasSuffix("]") {
      section = String(line.dropFirst().dropLast())
        .trimmingCharacters(in: .whitespacesAndNewlines)
      continue
    }

    guard let equalsIndex = line.firstIndex(of: "=") else { continue }

    let key = line[..<equalsIndex]
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !key.isEmpty else { continue }
    keys.append(DocumentedConfigKey(section: section, key: key))
  }

  return keys
}

private func normalizedConfigLine(_ rawLine: String) -> String? {
  let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }

  if trimmed.hasPrefix("#") {
    let uncommented = trimmed.dropFirst()
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if uncommented.hasPrefix("[") {
      return uncommented
    }

    guard let equalsIndex = uncommented.firstIndex(of: "=") else {
      return nil
    }

    let key = uncommented[..<equalsIndex]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard isBareConfigKey(key) else { return nil }

    return uncommented
  }

  return trimmed
}

private func isBareConfigKey(_ key: String) -> Bool {
  key.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil
}
