import Foundation

/// Runtime category inferred from one structured process log entry.
public enum ProcessLogRuntime: String, Codable, CaseIterable, Sendable {
  case lua
  case native
  case agent

  /// Returns a normalized runtime filter value.
  public static func normalized(_ value: String) -> ProcessLogRuntime? {
    ProcessLogRuntime(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }
}

/// One parsed EasyBar process log line.
public struct ProcessLogRecord: Sendable {
  private static let timestampFormatter = LockedState<ISO8601DateFormatter>(
    {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter
    }())

  public let timestamp: Date?
  public let timestampText: String?
  public let level: ProcessLogLevel?
  public let message: String
  public let fields: [String: String]
  public let source: String
  public let rawLine: String

  /// Creates one parsed or raw process log record.
  public init(
    timestamp: Date?,
    timestampText: String?,
    level: ProcessLogLevel?,
    message: String,
    fields: [String: String],
    source: String,
    rawLine: String
  ) {
    self.timestamp = timestamp
    self.timestampText = timestampText
    self.level = level
    self.message = message
    self.fields = fields
    self.source = source
    self.rawLine = rawLine
  }

  /// Widget identity carried by the line or inferred from a native-widget subsystem.
  public var widget: String? {
    if let configured = fields["widget"] {
      return Self.normalizedWidget(configured)
    }

    guard let subsystem = fields["subsystem"] else { return nil }
    guard let marker = subsystem.range(of: ".widgets.") else { return nil }
    let suffix = String(subsystem[marker.upperBound...])
    guard let component = suffix.split(separator: ".").first else { return nil }
    return Self.normalizedWidget(String(component))
  }

  /// Runtime carried by the line or inferred from its process and subsystem metadata.
  public var runtime: ProcessLogRuntime? {
    if let configured = fields["runtime"], let runtime = ProcessLogRuntime.normalized(configured) {
      return runtime
    }

    if source == "calendar-agent" || source == "network-agent"
      || source == "easybar-calendar-agent" || source == "easybar-network-agent"
    {
      return .agent
    }

    if fields["request_id"]?.hasPrefix("lua-") == true {
      return .lua
    }

    if fields["component"]?.lowercased() == "runtime" {
      return .lua
    }

    let subsystem = fields["subsystem"]?.lowercased() ?? ""
    let lowercasedMessage = message.lowercased()
    if subsystem.contains(".lua") || lowercasedMessage.hasPrefix("lua ") {
      return .lua
    }

    if subsystem.contains(".widgets") || subsystem.contains("wifi_store")
      || lowercasedMessage.contains("native widget") || lowercasedMessage.hasPrefix("wifi widget")
    {
      return .native
    }

    if source == "easybar", fields["widget"] != nil {
      return .lua
    }

    return nil
  }

  /// Parses one shared logger line and preserves unstructured lines as raw records.
  public static func parse(_ line: String, source: String) -> ProcessLogRecord {
    guard let header = parsedHeader(line) else {
      return ProcessLogRecord(
        timestamp: nil,
        timestampText: nil,
        level: nil,
        message: line,
        fields: [:],
        source: source,
        rawLine: line
      )
    }

    let tokens = tokenize(header.remainder)
    let fieldStart = tokens.indices.first { index in
      tokens[index...].allSatisfy { splitField($0) != nil }
    }
    let messageTokens = fieldStart.map { Array(tokens[..<$0]) } ?? tokens
    let fieldTokens = fieldStart.map { Array(tokens[$0...]) } ?? []
    let fields = Dictionary(
      fieldTokens.compactMap(splitField),
      uniquingKeysWith: { _, latest in latest }
    )

    return ProcessLogRecord(
      timestamp: parseTimestamp(header.timestamp),
      timestampText: header.timestamp,
      level: ProcessLogLevel.normalized(header.level),
      message: messageTokens.joined(separator: " "),
      fields: fields,
      source: source,
      rawLine: line
    )
  }

  private static func normalizedWidget(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.hasPrefix("builtin_")
      ? String(normalized.dropFirst("builtin_".count)) : normalized
  }

  private static func parsedHeader(_ line: String) -> (
    timestamp: String, level: String, remainder: String
  )? {
    guard line.hasPrefix("[") else { return nil }
    guard let timestampEnd = line.firstIndex(of: "]") else { return nil }
    let afterTimestamp = line.index(after: timestampEnd)
    guard afterTimestamp < line.endIndex else { return nil }

    let remaining = line[afterTimestamp...].drop(while: \.isWhitespace)
    guard remaining.first == "[", let levelEnd = remaining.firstIndex(of: "]") else { return nil }

    let timestamp = String(line[line.index(after: line.startIndex)..<timestampEnd])
    let level = String(remaining[remaining.index(after: remaining.startIndex)..<levelEnd])
    let remainder = String(remaining[remaining.index(after: levelEnd)...])
      .trimmingCharacters(in: .whitespaces)
    return (timestamp, level, remainder)
  }

  private static func parseTimestamp(_ value: String) -> Date? {
    timestampFormatter.withLock { $0.date(from: value) }
  }

  private static func tokenize(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var quoted = false
    var escaped = false

    for character in text {
      if escaped {
        current.append(character)
        escaped = false
        continue
      }

      if character == "\\" {
        current.append(character)
        escaped = quoted
        continue
      }

      if character == "\"" {
        quoted.toggle()
        current.append(character)
        continue
      }

      if character.isWhitespace, !quoted {
        if !current.isEmpty {
          tokens.append(current)
          current = ""
        }
        continue
      }

      current.append(character)
    }

    if !current.isEmpty {
      tokens.append(current)
    }
    return tokens
  }

  private static func splitField(_ token: String) -> (String, String)? {
    guard let separator = token.firstIndex(of: "=") else { return nil }
    let key = String(token[..<separator])
    guard isFieldKey(key) else { return nil }
    let valueStart = token.index(after: separator)
    return (key, decodedFieldValue(String(token[valueStart...])))
  }

  private static func isFieldKey(_ value: String) -> Bool {
    guard let first = value.first, first.isLetter || first == "_" else { return false }
    return value.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
  }

  private static func decodedFieldValue(_ value: String) -> String {
    guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
    let inner = value.dropFirst().dropLast()
    var decoded = ""
    var escaped = false

    for character in inner {
      if escaped {
        switch character {
        case "n": decoded.append("\n")
        case "r": decoded.append("\r")
        case "t": decoded.append("\t")
        default: decoded.append(character)
        }
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else {
        decoded.append(character)
      }
    }

    if escaped {
      decoded.append("\\")
    }
    return decoded
  }
}

/// Filters parsed process log records consistently for history and live output.
public struct ProcessLogFilter: Sendable {
  public let widget: String?
  public let runtime: ProcessLogRuntime?
  public let minimumLevel: ProcessLogLevel?
  public let requestID: String?
  public let since: Date?

  /// Creates one process log filter.
  public init(
    widget: String? = nil,
    runtime: ProcessLogRuntime? = nil,
    minimumLevel: ProcessLogLevel? = nil,
    requestID: String? = nil,
    since: Date? = nil
  ) {
    self.widget = widget.map(Self.normalizedWidget)
    self.runtime = runtime
    self.minimumLevel = minimumLevel
    self.requestID = requestID
    self.since = since
  }

  /// Returns whether one record satisfies every configured filter.
  public func matches(_ record: ProcessLogRecord) -> Bool {
    if let widget, record.widget != widget { return false }
    if let runtime, record.runtime != runtime { return false }
    if let minimumLevel {
      guard let level = record.level, minimumLevel.allows(level) else { return false }
    }
    if let requestID, record.fields["request_id"] != requestID { return false }
    if let since {
      guard let timestamp = record.timestamp, timestamp >= since else { return false }
    }
    return true
  }

  /// Cheaply rejects raw lines that cannot satisfy exact structured-field filters.
  func mightMatch(rawLine: Substring) -> Bool {
    guard let requestID else { return true }
    return rawLine.contains("request_id=\(requestID)")
  }

  private static func normalizedWidget(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.hasPrefix("builtin_")
      ? String(normalized.dropFirst("builtin_".count)) : normalized
  }
}

/// Parses relative durations or ISO-8601 timestamps accepted by `easybar logs --since`.
public enum ProcessLogSinceParser {
  /// Resolves one `--since` value relative to the supplied clock.
  public static func parse(_ value: String, now: Date = Date()) -> Date? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.lowercased()
    guard !normalized.isEmpty else { return nil }

    let units: [(suffix: String, seconds: TimeInterval)] = [
      ("s", 1),
      ("m", 60),
      ("h", 3_600),
      ("d", 86_400),
      ("w", 604_800),
    ]
    for unit in units where normalized.hasSuffix(unit.suffix) {
      let number = normalized.dropLast(unit.suffix.count)
      guard let amount = Double(number), amount >= 0, amount.isFinite else { return nil }
      return now.addingTimeInterval(-(amount * unit.seconds))
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: trimmed) {
      return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: trimmed)
  }
}
