import Foundation

/// Shared cache for format-driven date rendering across native widgets.
final class FormattedDateFormatterCache {

  private var formatters: [String: DateFormatter] = [:]

  /// Formats one date with a cached formatter for the given format.
  func string(from date: Date, format: String) -> String {
    return formatter(for: format).string(from: date)
  }

  /// Returns a cached formatter for the given date format.
  private func formatter(for format: String) -> DateFormatter {
    if let formatter = formatters[format] {
      return formatter
    }

    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.calendar = .autoupdatingCurrent
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = format
    formatters[format] = formatter
    return formatter
  }
}

/// Resolves the lowest-cost refresh cadence that still keeps formatted date output current.
enum FormattedClockRefreshPolicy {

  /// Returns the refresh event required by the given date format.
  static func event(for format: String) -> AppEvent {
    return containsSecondPrecision(format) ? .secondTick : .minuteTick
  }

  /// Detects real second-based fields while ignoring quoted literals in the date format string.
  private static func containsSecondPrecision(_ format: String) -> Bool {
    var index = format.startIndex
    var inQuotedLiteral = false

    while index < format.endIndex {
      let character = format[index]

      if character == "'" {
        let nextIndex = format.index(after: index)
        if nextIndex < format.endIndex, format[nextIndex] == "'" {
          index = format.index(after: nextIndex)
          continue
        }

        inQuotedLiteral.toggle()
        index = nextIndex
        continue
      }

      if !inQuotedLiteral && (character == "s" || character == "S") {
        return true
      }

      index = format.index(after: index)
    }

    return false
  }
}
