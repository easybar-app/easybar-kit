import EasyBarShared
import Foundation
import SwiftTOMLEdit

extension Config.BuiltinBatteryColorMode: TOMLStringDecodable {}
extension Config.BuiltinBatteryDisplayMode: TOMLStringDecodable {}
extension Config.BuiltinWiFiContentMode: TOMLStringDecodable {}
extension Config.BuiltinWiFiContentSurface: TOMLStringDecodable {}

extension Config {
  /// Parses one configured minimum log level.
  func parseLogLevel(
    _ value: String,
    path: String
  ) throws -> ProcessLogLevel {
    if let parsed = ProcessLogLevel.normalized(value) {
      return parsed
    }

    let expected = ProcessLogLevel.allCases
      .map(\.rawValue)
      .sorted()
      .joined(separator: ", ")

    throw ConfigError.invalidValue(
      path: path,
      message: "expected one of \(expected)"
    )
  }

  /// Validates one configured built-in group reference.
  func validatedBuiltinGroupReference(
    _ value: String?,
    path: String,
    allowGroupReference: Bool
  ) throws -> String? {
    guard let value else { return nil }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    guard allowGroupReference else {
      throw ConfigError.invalidValue(
        path: path,
        message: "built-in groups cannot be nested"
      )
    }

    guard builtinGroups.contains(where: { $0.id == trimmed }) else {
      let knownGroups = builtinGroups.map(\.id).sorted()

      if knownGroups.isEmpty {
        throw ConfigError.invalidValue(
          path: path,
          message: "unknown built-in group '\(trimmed)'"
        )
      }

      throw ConfigError.invalidValue(
        path: path,
        message:
          "unknown built-in group '\(trimmed)'; expected one of \(knownGroups.joined(separator: ", "))"
      )
    }

    return trimmed
  }

  /// Validates one configured spaces text weight.
  func validatedSpacesTextWeight(
    _ value: String,
    path: String
  ) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.lowercased()

    let allowed = [
      "ultralight",
      "thin",
      "light",
      "regular",
      "medium",
      "semibold",
      "bold",
      "heavy",
      "black",
    ]

    guard allowed.contains(normalized) else {
      throw ConfigError.invalidValue(
        path: path,
        message: "expected one of \(allowed.joined(separator: ", "))"
      )
    }

    return trimmed
  }
}
extension Config {
  /// Returns a validated config color reference without resolving theme tokens.
  static func validatedConfigColor(_ value: String, path: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty || trimmed.isValidHexColorLiteral {
      return trimmed
    }

    if let token = Self.themeColorTokenReference(from: trimmed) {
      return token.reference
    }

    throw ConfigError.invalidValue(
      path: path,
      message: "expected #RRGGBB, #RRGGBBAA, RRGGBB, RRGGBBAA, or theme.<known_token>"
    )
  }

  /// Returns a validated concrete theme color literal.
  static func validatedThemeColorLiteral(_ value: String, path: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

    guard trimmed.isValidHexColorLiteral else {
      throw ConfigError.invalidValue(
        path: path,
        message: "expected #RRGGBB, #RRGGBBAA, RRGGBB, or RRGGBBAA"
      )
    }

    return trimmed
  }

  /// Validates and resolves one config color to a concrete hex literal.
  func resolvedConfigColor(_ value: String, path: String) throws -> String {
    let validated = try Self.validatedConfigColor(value, path: path)

    guard let resolved = resolveThemeColorHex(validated) else {
      return validated
    }

    return resolved
  }

  private static func themeColorTokenReference(from value: String) -> ThemeColorToken? {
    let prefix = "theme."
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)

    guard normalized.lowercased().hasPrefix(prefix) else {
      return nil
    }

    let token = String(normalized.dropFirst(prefix.count))
    return ThemeColorToken(normalizedToken: token)
  }
}

extension TOMLConfigReader where Failure == ConfigError {
  /// Returns a validated color value or the fallback when absent.
  func color(_ key: String, fallback: String) throws -> String {
    try Config.validatedConfigColor(
      string(key, fallback: fallback),
      path: path(for: key)
    )
  }

  /// Returns a validated optional color value or the optional fallback when absent.
  func optionalColor(_ key: String, fallback: String? = nil) throws -> String? {
    guard let value = try optionalString(key, fallback: fallback) else { return nil }
    return try Config.validatedConfigColor(
      value,
      path: path(for: key)
    )
  }
}
