import Foundation

/// One structured log event that can be delivered to a live diagnostics sink.
public struct ProcessLogEvent: Codable, Sendable {
  public let timestamp: Date
  public let timestampText: String
  public let level: ProcessLogLevel
  public let message: String
  public let fields: [String: String]
  public let source: String
  public let rawLine: String

  /// Creates one structured live log event.
  public init(
    timestamp: Date,
    timestampText: String,
    level: ProcessLogLevel,
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

  /// Converts the event into the same record shape used by retained log files.
  public var record: ProcessLogRecord {
    ProcessLogRecord(
      timestamp: timestamp,
      timestampText: timestampText,
      level: level,
      message: message,
      fields: fields,
      source: source,
      rawLine: rawLine
    )
  }

  /// Widget identity carried by the event metadata.
  public var widget: String? {
    record.widget
  }

  /// Runtime category carried by or inferred from the event metadata.
  public var runtime: ProcessLogRuntime? {
    record.runtime
  }
}
