import Foundation
import SwiftTOMLEdit

extension Config {

  /// Converts a lossless parser error into a user-facing config error.
  func makeParseFailure(
    from error: TOMLParseError,
    text: String,
    sourceDescription: String? = nil
  ) -> ConfigError {
    let line = error.line
    let column = error.column
    let lines = text.components(separatedBy: .newlines)
    let lineText = sourceLine(in: lines, line: line)

    let tablePath = nearestTableHeaderPath(in: lines, beforeLine: line)
    let key = keyText(from: lineText)
    let item = problemItem(tablePath: tablePath, key: key)
    let value = valueText(from: lineText)

    return ConfigError.parseFailure(
      message: error.message,
      sourceDescription: sourceDescription,
      line: line,
      column: column,
      item: item,
      value: value
    )
  }

  /// Returns one source line for a 1-based line number.
  private func sourceLine(in lines: [String], line: Int?) -> String? {
    guard let line, line > 0, line <= lines.count else {
      return nil
    }

    return lines[line - 1]
  }

  /// Returns the nearest TOML table header path before the failing line.
  private func nearestTableHeaderPath(in lines: [String], beforeLine line: Int?) -> String? {
    guard let line, line > 1 else {
      return nil
    }

    let startIndex = min(line - 2, lines.count - 1)
    guard startIndex >= 0 else {
      return nil
    }

    for index in stride(from: startIndex, through: 0, by: -1) {
      if let tablePath = tableHeaderPath(from: lines[index]) {
        return tablePath
      }
    }

    return nil
  }

  /// Returns the TOML table path from a complete table-header line.
  private func tableHeaderPath(from line: String) -> String? {
    let trimmed = trimInlineComment(from: line)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.hasPrefix("[[") {
      guard let end = trimmed.range(of: "]]") else {
        return nil
      }

      let remainder = trimmed[end.upperBound...]
        .trimmingCharacters(in: .whitespacesAndNewlines)

      guard remainder.isEmpty else {
        return nil
      }

      let start = trimmed.index(trimmed.startIndex, offsetBy: 2)
      let value = trimmed[start..<end.lowerBound]
        .trimmingCharacters(in: .whitespacesAndNewlines)

      return value.isEmpty ? nil : value
    }

    if trimmed.hasPrefix("[") {
      guard let end = trimmed.firstIndex(of: "]") else {
        return nil
      }

      let remainder = trimmed[trimmed.index(after: end)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)

      guard remainder.isEmpty else {
        return nil
      }

      let start = trimmed.index(after: trimmed.startIndex)
      let value = trimmed[start..<end]
        .trimmingCharacters(in: .whitespacesAndNewlines)

      return value.isEmpty ? nil : value
    }

    return nil
  }

  /// Returns the key before the assignment operator on one TOML line.
  private func keyText(from line: String?) -> String? {
    guard
      let line,
      let assignmentIndex = assignmentIndex(in: line)
    else {
      return nil
    }

    let key = line[..<assignmentIndex]
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return key.isEmpty ? nil : key
  }

  /// Returns the value after the assignment operator on one TOML line.
  private func valueText(from line: String?) -> String? {
    guard
      let line,
      let assignmentIndex = assignmentIndex(in: line)
    else {
      return nil
    }

    let valueStart = line.index(after: assignmentIndex)
    let rawValue = String(line[valueStart...])
    let value = trimInlineComment(from: rawValue)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return value.isEmpty ? nil : value
  }

  /// Combines a table path and key into a readable TOML item label.
  private func problemItem(tablePath: String?, key: String?) -> String? {
    guard let key, !key.isEmpty else {
      return nil
    }

    guard let tablePath, !tablePath.isEmpty else {
      return key
    }

    return "[\(tablePath)].\(key)"
  }

  /// Finds the first assignment operator outside strings and comments.
  private func assignmentIndex(in line: String) -> String.Index? {
    var scanner = TOMLLineScanner()

    for index in line.indices {
      let character = line[index]

      if scanner.consume(character) == .commentStart {
        return nil
      }

      if character == "=" && scanner.isOutsideString {
        return index
      }
    }

    return nil
  }

  /// Removes an inline comment while preserving hashes inside strings.
  private func trimInlineComment(from value: String) -> String {
    var result = ""
    var scanner = TOMLLineScanner()

    for character in value {
      if scanner.consume(character) == .commentStart {
        break
      }

      result.append(character)
    }

    return result
  }
}

private enum TOMLLineToken {
  case content
  case commentStart
}

/// Tracks the minimal TOML string state needed to ignore comments and assignments inside strings.
private struct TOMLLineScanner {
  private var inSingleQuotedString = false
  private var inDoubleQuotedString = false
  private var escaped = false

  var isOutsideString: Bool {
    !inSingleQuotedString && !inDoubleQuotedString
  }

  mutating func consume(_ character: Character) -> TOMLLineToken {
    if escaped {
      escaped = false
      return .content
    }

    if character == "\\" && inDoubleQuotedString {
      escaped = true
      return .content
    }

    if character == "\"" && !inSingleQuotedString {
      inDoubleQuotedString.toggle()
      return .content
    }

    if character == "'" && !inDoubleQuotedString {
      inSingleQuotedString.toggle()
      return .content
    }

    if character == "#" && isOutsideString {
      return .commentStart
    }

    return .content
  }
}
