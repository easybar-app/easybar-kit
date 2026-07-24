import Foundation

/// Matches calendar event URLs against configurable meeting-service patterns.
public enum CalendarMeetingURLMatcher {
  /// Built-in case-insensitive URL substrings used when config does not override the list.
  public static let defaultPatterns = [
    "zoom.us",
    "meet.google.com",
    "teams.microsoft.com",
    "webex.com",
    "whereby.com",
    "jitsi",
    "gotomeeting.com",
    "bluejeans.com",
  ]

  /// Trims, lowercases, removes empty entries, and preserves the first occurrence of each pattern.
  public static func normalizedPatterns(_ patterns: [String]) -> [String] {
    var seen = Set<String>()

    return patterns.compactMap { pattern in
      let normalized =
        pattern
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

      guard !normalized.isEmpty, seen.insert(normalized).inserted else {
        return nil
      }
      return normalized
    }
  }

  /// Returns whether the URL contains at least one configured pattern.
  public static func matches(_ rawURL: String?, patterns: [String]) -> Bool {
    guard let rawURL else { return false }

    let normalizedURL =
      rawURL
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !normalizedURL.isEmpty else { return false }

    return normalizedPatterns(patterns).contains { normalizedURL.contains($0) }
  }
}
