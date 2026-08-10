import XCTest

@testable import EasyBarKit

final class ConfigDefaultDriftTests: ConfigLoaderTestCase {
  func testCheckedInExampleConfigsValidateWithoutWarnings() throws {
    for fileName in ["config.defaults.toml", "config.minimal.toml"] {
      let configURL = repoRootURL().appendingPathComponent(fileName)
      let loadedState = try Config.validate(configPathOverride: configURL.path)

      XCTAssertEqual(loadedState.warnings, [], fileName)
    }
  }

  func testGeneratedDefaultsEndWithOneNewline() throws {
    let defaultsFileURL = repoRootURL().appendingPathComponent("config.defaults.toml")
    let defaults = try String(contentsOf: defaultsFileURL, encoding: .utf8)

    XCTAssertTrue(defaults.hasSuffix("\n"))
    XCTAssertFalse(defaults.hasSuffix("\n\n"))
  }

  /// Verifies that the checked-in full defaults file matches the built-in Swift defaults.
  func testConfigDefaultsTomlMatchesBuiltInDefaults() throws {
    let missingConfigURL =
      tempDirectoryURL
      .appendingPathComponent("missing", isDirectory: true)
      .appendingPathComponent("config.toml")
    let defaultSnapshot = try Config.validate(configPathOverride: missingConfigURL.path).snapshot
    let defaultsFileURL = repoRootURL().appendingPathComponent("config.defaults.toml")
    let loadedState = try Config.validate(configPathOverride: defaultsFileURL.path)
    let loadedSnapshot = loadedState.snapshot

    XCTAssertEqual(loadedState.warnings, [])

    assertAppDefaults(loadedSnapshot.app, match: defaultSnapshot.app)
    XCTAssertEqual(loadedSnapshot.logging.level, defaultSnapshot.logging.level)
    XCTAssertEqual(loadedSnapshot.logging.enabled, defaultSnapshot.logging.enabled)
    XCTAssertEqual(loadedSnapshot.logging.directory, defaultSnapshot.logging.directory)
    XCTAssertEqual(
      loadedSnapshot.calendarAgent.socketPath, defaultSnapshot.calendarAgent.socketPath)
    XCTAssertEqual(loadedSnapshot.calendarAgent.enabled, defaultSnapshot.calendarAgent.enabled)
    XCTAssertEqual(loadedSnapshot.networkAgent.socketPath, defaultSnapshot.networkAgent.socketPath)
    XCTAssertEqual(loadedSnapshot.networkAgent.enabled, defaultSnapshot.networkAgent.enabled)
    XCTAssertEqual(
      loadedSnapshot.networkAgent.refreshIntervalSeconds,
      defaultSnapshot.networkAgent.refreshIntervalSeconds
    )
    XCTAssertEqual(
      loadedSnapshot.networkAgent.allowUnauthorizedNonSensitiveFields,
      defaultSnapshot.networkAgent.allowUnauthorizedNonSensitiveFields
    )
    XCTAssertEqual(loadedSnapshot.theme.name, defaultSnapshot.theme.name)
    XCTAssertEqual(loadedSnapshot.theme.colors, defaultSnapshot.theme.colors)
    assertDefaultValue(
      loadedSnapshot.bar, matches: defaultSnapshot.bar, theme: loadedSnapshot.theme.colors)
    assertBuiltinDefaults(
      loadedSnapshot.builtins,
      match: defaultSnapshot.builtins,
      theme: loadedSnapshot.theme.colors
    )
  }

  /// Verifies app defaults except for the config file path itself.
  private func assertAppDefaults(
    _ actual: ConfigSnapshot.App,
    match expected: ConfigSnapshot.App
  ) {
    XCTAssertEqual(actual.runtimeDirectory, expected.runtimeDirectory)
    XCTAssertEqual(actual.widgetsPath, expected.widgetsPath)
    XCTAssertEqual(actual.luaPath, expected.luaPath)
    XCTAssertEqual(actual.luaSocketPath, expected.luaSocketPath)
    XCTAssertEqual(actual.environment, expected.environment)
    XCTAssertEqual(actual.watchConfigFile, expected.watchConfigFile)
    XCTAssertEqual(actual.lockDirectory, expected.lockDirectory)
    XCTAssertEqual(actual.widgetEditorStubPath, expected.widgetEditorStubPath)
    XCTAssertEqual(actual.develop, expected.develop)
    XCTAssertEqual(actual.luaCommandLimits, expected.luaCommandLimits)
  }

  /// Verifies all built-in widget defaults using stable reflected value snapshots.
  private func assertBuiltinDefaults(
    _ actual: ConfigSnapshot.Builtins,
    match expected: ConfigSnapshot.Builtins,
    theme: Config.ThemeColors
  ) {
    assertDefaultValue(actual.cpu, matches: expected.cpu, theme: theme)
    assertDefaultValue(actual.battery, matches: expected.battery, theme: theme)
    assertDefaultValue(actual.groups, matches: expected.groups, theme: theme)
    assertDefaultValue(actual.spaces, matches: expected.spaces, theme: theme)
    assertDefaultValue(actual.frontApp, matches: expected.frontApp, theme: theme)
    assertDefaultValue(actual.aerospaceMode, matches: expected.aerospaceMode, theme: theme)
    assertDefaultValue(actual.volume, matches: expected.volume, theme: theme)
    assertDefaultValue(actual.wifi, matches: expected.wifi, theme: theme)
    assertDefaultValue(actual.calendar, matches: expected.calendar, theme: theme)
    assertDefaultValue(actual.time, matches: expected.time, theme: theme)
    assertDefaultValue(actual.date, matches: expected.date, theme: theme)
  }

  /// Compares values after converting them into stable structural snapshots.
  private func assertDefaultValue(
    _ actual: Any,
    matches expected: Any,
    theme: Config.ThemeColors,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      normalizedDefaultValue(actual, theme: theme),
      normalizedDefaultValue(expected, theme: theme),
      file: file,
      line: line
    )
  }

  /// Normalizes semantically equivalent values used by the defaults reference file.
  private func normalizedDefaultValue(_ value: Any, theme: Config.ThemeColors)
    -> DefaultSnapshotValue
  {
    if let string = value as? String {
      return .scalar(resolveThemeReference(string, theme: theme))
    }

    let mirror = Mirror(reflecting: value)

    switch mirror.displayStyle {
    case .optional:
      guard let child = mirror.children.first else { return .scalar("nil") }
      return normalizedDefaultValue(child.value, theme: theme)

    case .collection, .set:
      return .array(mirror.children.map { normalizedDefaultValue($0.value, theme: theme) })

    case .dictionary:
      let entries = mirror.children.map { child -> (String, DefaultSnapshotValue) in
        let pair = Mirror(reflecting: child.value).children.map(\.value)
        let key = pair.first.map { String(describing: $0) } ?? ""
        let value =
          pair.dropFirst().first.map { normalizedDefaultValue($0, theme: theme) }
          ?? .scalar("nil")
        return (key, value)
      }
      return .object(entries.sorted { $0.0 < $1.0 })

    case .struct, .class, .tuple:
      let fields = mirror.children.compactMap { child -> (String, DefaultSnapshotValue)? in
        guard let label = child.label else { return nil }
        return (label, normalizedDefaultValue(child.value, theme: theme))
      }
      guard !fields.isEmpty else { return .scalar(String(describing: value)) }
      return .object(fields)

    case .enum:
      guard !mirror.children.isEmpty else { return .scalar(String(describing: value)) }
      let fields = mirror.children.compactMap { child -> (String, DefaultSnapshotValue)? in
        guard let label = child.label else { return nil }
        return (label, normalizedDefaultValue(child.value, theme: theme))
      }
      return .object(fields)

    case .foreignReference, .none:
      return .scalar(String(describing: value))

    @unknown default:
      return .scalar(String(describing: value))
    }
  }

  /// Resolves theme token references to their concrete default color values.
  private func resolveThemeReference(_ value: String, theme: Config.ThemeColors) -> String {
    guard
      let token = ThemeColorToken(
        normalizedToken: value.replacingOccurrences(of: "theme.", with: "")),
      value == token.reference
    else {
      return value
    }

    return theme[token]
  }
}

private enum DefaultSnapshotValue: Equatable, CustomStringConvertible {
  case scalar(String)
  case array([DefaultSnapshotValue])
  case object([(String, DefaultSnapshotValue)])

  static func == (lhs: DefaultSnapshotValue, rhs: DefaultSnapshotValue) -> Bool {
    switch (lhs, rhs) {
    case (.scalar(let left), .scalar(let right)):
      return left == right
    case (.array(let left), .array(let right)):
      return left == right
    case (.object(let left), .object(let right)):
      guard left.count == right.count else { return false }
      return zip(left, right).allSatisfy { leftField, rightField in
        leftField.0 == rightField.0 && leftField.1 == rightField.1
      }
    default:
      return false
    }
  }

  var description: String {
    switch self {
    case .scalar(let value):
      return value
    case .array(let values):
      return "[" + values.map(\.description).joined(separator: ", ") + "]"
    case .object(let fields):
      return "{" + fields.map { "\($0.0): \($0.1.description)" }.joined(separator: ", ") + "}"
    }
  }
}
