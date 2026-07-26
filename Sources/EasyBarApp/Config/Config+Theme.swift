import EasyBarCalendarConfig
import Foundation
import SwiftTOMLEdit

extension Config {

  /// Parses the selected theme, loads its TOML file, and applies inline color overrides.
  func parseTheme(from toml: TOMLTable) throws {
    let currentTheme = themeSection
    let theme = try configReader(table: toml, path: "").section("theme")
    let colorsReader = try theme.section("colors")

    let selectedName = try theme.string("name", fallback: currentTheme.name)
    let configuredThemesDir = try theme.optionalExpandedPath("themes_dir")
    let resolvedThemesDir = configuredThemesDir ?? currentTheme.themesDir
    let fileColors = try loadThemeColors(
      named: selectedName,
      themesDir: resolvedThemesDir
    )

    let colors = try parseThemeColorOverrides(
      reader: colorsReader,
      fallback: fileColors
    )

    themeSection = ThemeSection(
      name: normalizedThemeName(selectedName),
      themesDir: resolvedThemesDir,
      colors: colors
    )

    registerDirectoryRequirement(
      for: "theme.themes_dir",
      path: resolvedThemesDir,
      kind: .directory
    )
  }

  /// Resolves a color reference such as `theme.text`.
  func resolveThemeColorHex(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "theme."

    guard trimmed.lowercased().hasPrefix(prefix) else {
      return nil
    }

    let token = String(trimmed.dropFirst(prefix.count))
    return themeColorHex(named: token)
  }

  /// Resolves a theme token without the `theme.` prefix.
  func themeColorHex(named token: String) -> String? {
    guard let themeToken = ThemeColorToken(normalizedToken: normalizedThemeToken(token)) else {
      return nil
    }

    return themeColors[themeToken]
  }

  /// Returns the default native group style derived from the active theme.
  func defaultBuiltinGroupStyle() -> BuiltinWidgetChromeStyle {
    BuiltinWidgetChromeStyle(
      backgroundColorHex: themeSurfaceHex,
      borderColorHex: themeBorderColorHex,
      borderWidth: 1,
      cornerRadius: 8,
      marginX: 0,
      marginY: 0,
      paddingX: 8,
      paddingY: 4,
      spacing: 6,
      opacity: 1
    )
  }
}

extension Config {

  /// Loads theme colors from the user themes directory or bundled resources.
  private func loadThemeColors(
    named name: String,
    themesDir: String
  ) throws -> ThemeColors {
    let fileName = try themeFileName(for: name)
    let fileManager = FileManager.default

    if let userThemeURL = userThemeURL(fileName: fileName, themesDir: themesDir),
      fileManager.fileExists(atPath: userThemeURL.path)
    {
      return try loadThemeFile(
        at: userThemeURL,
        path: "theme.themes_dir.\(fileName).toml"
      )
    }

    for bundledThemeURL in bundledThemeCandidateURLs(fileName: fileName) {
      guard fileManager.fileExists(atPath: bundledThemeURL.path) else {
        continue
      }

      return try loadThemeFile(
        at: bundledThemeURL,
        path: "bundled theme \(fileName).toml"
      )
    }

    throw ConfigError.invalidValue(
      path: "theme.name",
      message: "theme '\(name)' was not found in \(themesDir) or bundled themes"
    )
  }

  /// Returns all bundled theme lookup candidates for one theme file.
  private func bundledThemeCandidateURLs(fileName: String) -> [URL] {
    var candidates: [URL] = []

    if let resourceURL = Bundle.main.resourceURL {
      candidates.append(
        resourceURL
          .appendingPathComponent("Themes", isDirectory: true)
          .appendingPathComponent("\(fileName).toml")
      )
    }

    if let executableURL = Bundle.main.executableURL {
      let executableDirectory = executableURL.deletingLastPathComponent()

      candidates.append(
        executableDirectory
          .deletingLastPathComponent()
          .appendingPathComponent("Resources", isDirectory: true)
          .appendingPathComponent("Themes", isDirectory: true)
          .appendingPathComponent("\(fileName).toml")
      )

      candidates.append(
        executableDirectory
          .appendingPathComponent("Themes", isDirectory: true)
          .appendingPathComponent("\(fileName).toml")
      )
    }

    candidates.append(
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("themes", isDirectory: true)
        .appendingPathComponent("\(fileName).toml")
    )

    return uniqueThemeCandidateURLs(candidates)
  }

  /// Returns theme candidate URLs without duplicate paths.
  private func uniqueThemeCandidateURLs(_ urls: [URL]) -> [URL] {
    var seen: Set<String> = []
    var unique: [URL] = []

    for url in urls {
      let path = url.standardizedFileURL.path
      guard !seen.contains(path) else { continue }
      seen.insert(path)
      unique.append(url)
    }

    return unique
  }

  /// Loads and parses one complete theme TOML file.
  private func loadThemeFile(
    at url: URL,
    path: String
  ) throws -> ThemeColors {
    let text: String

    do {
      text = try String(contentsOf: url, encoding: .utf8)
    } catch {
      throw ConfigError.invalidValue(
        path: path,
        message: "failed to read theme file at \(url.path): \(error.localizedDescription)"
      )
    }

    do {
      let table = try TOMLTable(string: text)
      let reader = configReader(table: table, path: path)

      guard let colorsReader = try reader.optionalSection("colors") else {
        throw ConfigError.invalidValue(
          path: "\(path).colors",
          message: "theme file must contain a [colors] table"
        )
      }

      return try parseCompleteThemeColors(reader: colorsReader)
    } catch let error as TOMLParseError {
      throw makeParseFailure(
        from: error,
        text: text,
        sourceDescription: path
      )
    } catch let error as ConfigError {
      throw error
    } catch {
      throw ConfigError.invalidValue(
        path: path,
        message: "failed to parse theme TOML at \(url.path): \(error)"
      )
    }
  }

  /// Parses a complete theme color table.
  private func parseCompleteThemeColors(reader: ConfigReader) throws -> ThemeColors {
    try validateKnownThemeColorKeys(reader)

    return ThemeColors(
      valuesByToken: try Dictionary(
        uniqueKeysWithValues: ThemeColorToken.allCases.map { token in
          (token, try requiredThemeColor(reader, token.rawValue))
        }
      )
    )
  }

  /// Rejects unknown color keys in standalone theme files.
  private func validateKnownThemeColorKeys(_ reader: ConfigReader) throws {
    let knownKeys = Set(ThemeColorToken.allCases.map(\.rawValue))

    for key in reader.keys where !knownKeys.contains(key) {
      throw ConfigError.invalidValue(
        path: reader.path(for: key),
        message: "unknown theme color token '\(key)'"
      )
    }
  }

  /// Parses optional inline theme color overrides from `config.toml`.
  private func parseThemeColorOverrides(
    reader: ConfigReader,
    fallback: ThemeColors
  ) throws -> ThemeColors {
    ThemeColors(
      valuesByToken: try Dictionary(
        uniqueKeysWithValues: ThemeColorToken.allCases.map { token in
          let value = try reader.string(token.rawValue, fallback: fallback[token])
          return (
            token,
            try Config.validatedThemeColorLiteral(
              value,
              path: reader.path(for: token.rawValue)
            )
          )
        }
      )
    )
  }

  /// Returns one required color value from a complete theme file.
  private func requiredThemeColor(
    _ reader: ConfigReader,
    _ key: String
  ) throws -> String {
    guard let value = try reader.optionalString(key) else {
      throw ConfigError.invalidValue(
        path: reader.path(for: key),
        message: "missing required theme color '\(key)'"
      )
    }

    return try Config.validatedThemeColorLiteral(
      value,
      path: reader.path(for: key)
    )
  }

  /// Returns the user theme file URL for one theme name.
  private func userThemeURL(
    fileName: String,
    themesDir: String
  ) -> URL? {
    let trimmed = themesDir.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let expanded = NSString(string: trimmed).expandingTildeInPath

    return URL(fileURLWithPath: expanded, isDirectory: true)
      .appendingPathComponent("\(fileName).toml")
  }

  /// Returns the safe file name for one theme.
  private func themeFileName(for name: String) throws -> String {
    let normalized = normalizedThemeName(name)

    guard !normalized.isEmpty else {
      throw ConfigError.invalidValue(
        path: "theme.name",
        message: "theme name must not be empty"
      )
    }

    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
    guard normalized.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
      throw ConfigError.invalidValue(
        path: "theme.name",
        message: "theme name may only contain letters, numbers, dots, underscores, and dashes"
      )
    }

    return normalized
  }

  /// Normalizes one theme name for lookup.
  private func normalizedThemeName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// Normalizes one theme token for lookup.
  private func normalizedThemeToken(_ token: String) -> String {
    token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
