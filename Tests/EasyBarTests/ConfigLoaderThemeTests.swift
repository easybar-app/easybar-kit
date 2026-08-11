import Darwin
import EasyBarShared
import Foundation
import SwiftTOMLEdit
import XCTest

@testable import EasyBarKit

final class ConfigLoaderThemeTests: ConfigLoaderTestCase {
  /// Verifies that bootstrap theme palette stays aligned with bundled default theme.
  func testBootstrapThemePaletteMatchesBundledDefaultTheme() throws {
    let config = Config.makeUnloadedConfig()
    config.resetToDefaults()
    let repoRootURL = repoRootURL()
    let bundledThemeURL =
      repoRootURL
      .appendingPathComponent("themes/default.toml")

    let themeText = try String(contentsOf: bundledThemeURL, encoding: .utf8)
    let expectedColors: [ThemeColorToken: String] = [
      .background: "#111111",
      .surface: "#1a1a1a",
      .surfaceElevated: "#2b2b2b",
      .surfaceHover: "#202020",
      .text: "#ffffff",
      .textSecondary: "#d0d0d0",
      .textTertiary: "#c0c0c0",
      .muted: "#6c7086",
      .mutedSecondary: "#8a8a8a",
      .outsideMonth: "#6e738d",
      .accent: "#91d7e3",
      .accentSecondary: "#89B4FA",
      .accentSoft: "#8bd5ca",
      .success: "#a6e3a1",
      .successSecondary: "#a6da95",
      .warning: "#f9e2af",
      .orange: "#fab387",
      .error: "#f38ba8",
      .danger: "#FF0000",
      .border: "#333333",
      .borderStrong: "#444444",
      .borderSubtle: "#00000000",
      .selectionText: "#0B1020",
      .selectionBackground: "#89B4FA",
      .transparent: "#00000000",
      .overlayOutline: "#000000F0",
      .overlayText: "#FFFFFFFF",
    ]

    XCTAssertEqual(config.themeName, "default")

    for (token, value) in expectedColors {
      XCTAssertTrue(themeText.contains("\(token.rawValue) = \"\(value)\""))
      XCTAssertEqual(config.themeColors[token], value)
    }
  }

  /// Verifies that theme token table stays in sync with theme color accessors.
  func testThemeTokenTableStaysInSyncWithThemeColorAccessors() {
    let config = Config.makeUnloadedConfig()
    config.resetToDefaults()

    let expectedNames = Set(config.themeColors.valuesByName.keys)
    let actualNames = Set(ThemeColorToken.allCases.map(\.rawValue))

    XCTAssertEqual(actualNames, expectedNames)

    for token in ThemeColorToken.allCases {
      XCTAssertEqual(config.themeColorHex(named: token.rawValue), config.themeColors[token])
      XCTAssertEqual(config.resolveThemeColorHex(token.reference), config.themeColors[token])
    }
  }

  /// Verifies that Lua theme environment exports resolved colors without duplicate refs.
  func testLuaThemeEnvironmentExportsResolvedColorsWithoutDuplicateRefs() throws {
    let config = Config.makeUnloadedConfig()
    config.resetToDefaults()

    let environment = config.luaThemeEnvironment()
    let payloadJSON = try XCTUnwrap(environment[SharedEnvironmentKeys.luaThemeJSON])
    let data = try XCTUnwrap(payloadJSON.data(using: .utf8))
    let payload = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    XCTAssertEqual(payload["name"] as? String, config.themeName)
    XCTAssertNil(payload["ref"])

    let colors = try XCTUnwrap(payload["colors"] as? [String: String])

    for token in ThemeColorToken.allCases {
      XCTAssertEqual(colors[token.rawValue], config.themeColors[token])
    }
  }

  /// Verifies that bundled themes define the full rich theme palette.
  func testBundledThemesDefineEveryRichThemeToken() throws {
    let themesDirectoryURL = repoRootURL().appendingPathComponent("themes")
    let bundledThemeNames = ["default", "tokyo-night"]

    for themeName in bundledThemeNames {
      let themeText = try String(
        contentsOf: themesDirectoryURL.appendingPathComponent("\(themeName).toml"),
        encoding: .utf8
      )

      for token in ThemeColorToken.allCases {
        XCTAssertTrue(
          themeText.contains("\(token.rawValue) = \""),
          "missing \(token.rawValue) in \(themeName).toml"
        )
      }
    }
  }

  func testCheckedInThemesValidateAsSelectedTheme() throws {
    let themesDirectoryURL = repoRootURL().appendingPathComponent("themes")
    let themeURLs = try FileManager.default
      .contentsOfDirectory(
        at: themesDirectoryURL,
        includingPropertiesForKeys: nil
      )
      .filter { $0.pathExtension == "toml" }

    XCTAssertFalse(themeURLs.isEmpty)

    for themeURL in themeURLs {
      let themeName = themeURL.deletingPathExtension().lastPathComponent
      let configFileURL = tempDirectoryURL.appendingPathComponent("\(themeName)-theme.toml")
      try writeConfig(
        """
        [theme]
        name = "\(themeName)"
        themes_dir = "\(themesDirectoryURL.path)"
        """,
        to: configFileURL
      )

      let loadedState = try Config.validate(configPathOverride: configFileURL.path)
      XCTAssertEqual(loadedState.warnings, [], themeName)
    }
  }

  /// Verifies that a menu-style theme edit survives a config reload.
  @MainActor
  func testPersistedThemeSelectionSurvivesReload() async throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("config.toml")
    let themesDirectoryURL = tempDirectoryURL.appendingPathComponent("themes")
    try writeConfig(
      """
      [theme]
      name = "default"
      themes_dir = "\(themesDirectoryURL.path)"
      """,
      to: configFileURL
    )
    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let manager = ConfigManager(config: Config.makeUnloadedConfig())
    let initial = await manager.loadInitialConfig()
    XCTAssertTrue(initial.succeeded)
    XCTAssertEqual(initial.snapshot.theme.name, "default")

    let persistence = ConfigPersistence(
      configPath: configFileURL.path,
      logger: ProcessLogger(label: "theme-persistence-test")
    )
    XCTAssertTrue(
      persistence.apply([
        TOMLEdit(path: ["theme", "name"], value: .string("nord"))
      ])
    )

    let reloaded = await manager.reload()
    XCTAssertTrue(reloaded.succeeded)
    XCTAssertEqual(reloaded.snapshot.theme.name, "nord")
  }

  /// Verifies that Native's primary Inbox palette survives staged startup and reload parsing.
  @MainActor
  func testNativeInboxPaletteSurvivesInitialLoadAndReload() async throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("native-inbox.toml")
    try writeConfig("", to: configFileURL)
    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let manager = ConfigManager(
      config: Config.makeUnloadedConfig(builtInSurfacePolicy: .inboxOnly)
    )
    let initial = await manager.loadInitialConfig()

    XCTAssertTrue(initial.succeeded)
    XCTAssertEqual(
      initial.snapshot.builtins.inbox.style.unreadIconColorHex,
      initial.snapshot.theme.colors.text
    )
    XCTAssertEqual(
      initial.snapshot.builtins.inbox.style.readIconColorHex,
      initial.snapshot.theme.colors.text
    )

    let reloaded = await manager.reload()

    XCTAssertTrue(reloaded.succeeded)
    XCTAssertEqual(
      reloaded.snapshot.builtins.inbox.style.unreadIconColorHex,
      reloaded.snapshot.theme.colors.text
    )
    XCTAssertEqual(
      reloaded.snapshot.builtins.inbox.style.readIconColorHex,
      reloaded.snapshot.theme.colors.text
    )
  }

  /// Verifies that loading bundled themes does not create the custom theme directory.
  func testReloadDoesNotCreateMissingCustomThemesDirectory() throws {
    let config = Config.makeUnloadedConfig()
    let runtimeDirectoryURL = tempDirectoryURL.appendingPathComponent("runtime")
    let themesDirectoryURL = tempDirectoryURL.appendingPathComponent("custom-themes")
    let configFileURL = tempDirectoryURL.appendingPathComponent("missing-themes-dir.toml")

    try writeConfig(
      """
      [app]
      runtime_dir = "\(runtimeDirectoryURL.path)"
      widgets_dir = "\(tempDirectoryURL.appendingPathComponent("widgets").path)"
      lock_dir = "\(tempDirectoryURL.appendingPathComponent("locks").path)"
      widget_editor_stub_path = "\(tempDirectoryURL.appendingPathComponent("editor/easybar_api.lua").path)"

      [logging]
      directory = "\(tempDirectoryURL.appendingPathComponent("logs").path)"

      [theme]
      name = "default"
      themes_dir = "\(themesDirectoryURL.path)"
      """,
      to: configFileURL
    )
    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertNil(config.reload())
    XCTAssertEqual(config.themeName, "default")
    XCTAssertEqual(config.themesDir, themesDirectoryURL.path)
    XCTAssertFalse(FileManager.default.fileExists(atPath: themesDirectoryURL.path))
  }

  /// Verifies that an existing non-directory custom theme path remains invalid.
  func testReloadRejectsCustomThemesPathThatIsAFile() throws {
    let config = Config.makeUnloadedConfig()
    let runtimeDirectoryURL = tempDirectoryURL.appendingPathComponent("runtime-file-check")
    let themesFileURL = tempDirectoryURL.appendingPathComponent("themes-file")
    let configFileURL = tempDirectoryURL.appendingPathComponent("themes-file.toml")

    try "not a directory".write(to: themesFileURL, atomically: true, encoding: .utf8)
    try writeConfig(
      """
      [app]
      runtime_dir = "\(runtimeDirectoryURL.path)"
      widgets_dir = "\(tempDirectoryURL.appendingPathComponent("widgets-file-check").path)"
      lock_dir = "\(tempDirectoryURL.appendingPathComponent("locks-file-check").path)"
      widget_editor_stub_path = "\(tempDirectoryURL.appendingPathComponent("editor-file-check/easybar_api.lua").path)"

      [logging]
      directory = "\(tempDirectoryURL.appendingPathComponent("logs-file-check").path)"

      [theme]
      name = "default"
      themes_dir = "\(themesFileURL.path)"
      """,
      to: configFileURL
    )
    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard let configError = error as? ConfigError else {
      return XCTFail("Expected ConfigError, got \(String(describing: error))")
    }
    XCTAssertEqual(configError.configPath, "theme.themes_dir")
    XCTAssertEqual(
      configError.detail,
      "expected directory path, but found file at \(themesFileURL.path)"
    )
  }

  /// Verifies that invalid config color values fail during validation instead of rendering later.
  func testValidateRejectsUnknownThemeColorReference() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-color-reference.toml")

    try writeConfig(
      """
      [bar.colors]
      background = "theme.not_a_token"
      """,
      to: configFileURL
    )

    XCTAssertThrowsError(try Config.validate(configPathOverride: configFileURL.path)) { error in
      guard case .invalidValue(let path, let message) = error as? ConfigError else {
        return XCTFail("Expected invalidValue ConfigError, got \(error)")
      }

      XCTAssertEqual(path, "bar.colors.background")
      XCTAssertEqual(
        message,
        "expected #RRGGBB, #RRGGBBAA, RRGGBB, RRGGBBAA, or theme.<known_token>"
      )
    }
  }

  /// Verifies that theme color overrides must be concrete hex values.
  func testValidateRejectsInvalidThemeColorOverride() throws {
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-theme-color.toml")

    try writeConfig(
      """
      [theme.colors]
      accent = "blue"
      """,
      to: configFileURL
    )

    XCTAssertThrowsError(try Config.validate(configPathOverride: configFileURL.path)) { error in
      guard case .invalidValue(let path, let message) = error as? ConfigError else {
        return XCTFail("Expected invalidValue ConfigError, got \(error)")
      }

      XCTAssertEqual(path, "theme.colors.accent")
      XCTAssertEqual(message, "expected #RRGGBB, #RRGGBBAA, RRGGBB, or RRGGBBAA")
    }
  }

  /// Verifies that theme TOML syntax errors use the same item and value context as config.toml.
  func testThemeParseFailureIncludesItemAndValueContext() throws {
    let themesDirectoryURL = tempDirectoryURL.appendingPathComponent("themes")
    try FileManager.default.createDirectory(
      at: themesDirectoryURL,
      withIntermediateDirectories: true
    )

    let themeFileURL = themesDirectoryURL.appendingPathComponent("broken.toml")
    try writeConfig(
      """
      [colors]
      background = "#111111" trailing
      """,
      to: themeFileURL
    )

    let configFileURL = tempDirectoryURL.appendingPathComponent("broken-theme-config.toml")
    try writeConfig(
      """
      [theme]
      name = "broken"
      themes_dir = "\(themesDirectoryURL.path)"
      """,
      to: configFileURL
    )

    XCTAssertThrowsError(try Config.validate(configPathOverride: configFileURL.path)) { error in
      guard let configError = error as? ConfigError else {
        return XCTFail("Expected ConfigError, got \(error)")
      }

      XCTAssertTrue(configError.configPath.hasPrefix("theme.themes_dir.broken.toml, line "))
      XCTAssertEqual(configError.problemItem, "[colors].background")
      XCTAssertEqual(configError.problemValue, "\"#111111\" trailing")
    }
  }

  /// Verifies that standalone theme files reject unknown color token typos.
  func testValidateRejectsUnknownThemeColorTokenInThemeFile() throws {
    let themesDirectoryURL = tempDirectoryURL.appendingPathComponent("themes")
    try FileManager.default.createDirectory(
      at: themesDirectoryURL,
      withIntermediateDirectories: true
    )

    let sourceThemeURL = repoRootURL()
      .appendingPathComponent("themes/default.toml")
    let themeText =
      try String(contentsOf: sourceThemeURL, encoding: .utf8)
      + "\nunknwon_token = \"#ffffff\"\n"
    try writeConfig(
      themeText,
      to: themesDirectoryURL.appendingPathComponent("typo.toml")
    )

    let configFileURL = tempDirectoryURL.appendingPathComponent("theme-unknown-token.toml")
    try writeConfig(
      """
      [theme]
      name = "typo"
      themes_dir = "\(themesDirectoryURL.path)"
      """,
      to: configFileURL
    )

    XCTAssertThrowsError(try Config.validate(configPathOverride: configFileURL.path)) { error in
      guard case .invalidValue(let path, let message) = error as? ConfigError else {
        return XCTFail("Expected invalidValue ConfigError, got \(error)")
      }

      XCTAssertEqual(path, "theme.themes_dir.typo.toml.colors.unknwon_token")
      XCTAssertEqual(message, "unknown theme color token 'unknwon_token'")
    }
  }

}
