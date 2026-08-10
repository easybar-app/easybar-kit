import Foundation

/// Validation errors raised while loading EasyBar config.
enum ConfigError: Error, LocalizedError {
  /// A config value had the wrong TOML type.
  case invalidType(path: String, expected: String, actual: String)
  /// A config value had an unsupported value.
  case invalidValue(path: String, message: String)
  /// The TOML file could not be parsed before key-level validation started.
  case parseFailure(
    message: String,
    sourceDescription: String?,
    line: Int?,
    column: Int?,
    item: String?,
    value: String?
  )

  /// Returns the config path or source location associated with the validation failure.
  var configPath: String {
    switch self {
    case .invalidType(let path, _, _):
      return path

    case .invalidValue(let path, _):
      return path

    case .parseFailure(_, let sourceDescription, let line, let column, _, _):
      let location: String
      if let line, let column {
        location = "line \(line), column \(column)"
      } else if let line {
        location = "line \(line)"
      } else {
        location = "TOML syntax"
      }

      guard let sourceDescription else {
        return location
      }

      return "\(sourceDescription), \(location)"
    }
  }

  /// Returns the item/key that caused the failure when available.
  var problemItem: String? {
    switch self {
    case .parseFailure(_, _, _, _, let item, _):
      return item

    case .invalidType(let path, _, _):
      return path

    case .invalidValue(let path, _):
      return path
    }
  }

  /// Returns the problematic TOML value or value description when available.
  var problemValue: String? {
    switch self {
    case .parseFailure(_, _, _, _, _, let value):
      return value

    case .invalidType(_, _, let actual):
      return actual

    case .invalidValue:
      return nil
    }
  }

  /// Returns the human-readable failure detail without the config path prefix.
  var detail: String {
    switch self {
    case .invalidType(_, let expected, let actual):
      return "expected \(expected), got \(actual)"

    case .invalidValue(_, let message):
      return message

    case .parseFailure(let message, let sourceDescription, let line, let column, _, _):
      let locationText: String
      if let line, let column {
        locationText = " at line \(line), column \(column)"
      } else if let line {
        locationText = " at line \(line)"
      } else {
        locationText = ""
      }

      let sourceText = sourceDescription.map { " in \($0)" } ?? ""

      let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedMessage.isEmpty else {
        return "Could not parse TOML\(sourceText)\(locationText)."
      }

      return "Could not parse TOML\(sourceText)\(locationText): \(trimmedMessage)"
    }
  }

  var errorDescription: String? {
    return "\(configPath): \(detail)"
  }
}
