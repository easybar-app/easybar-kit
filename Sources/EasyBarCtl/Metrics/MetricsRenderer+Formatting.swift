import EasyBarShared
import Foundation

extension MetricsRenderer {
  /// Renders the metrics title and timestamp.
  static func header(_ snapshot: IPC.MetricsSnapshot, live: Bool) -> String {
    let mode = live ? "live" : "snapshot"
    return "EasyBar metrics (\(mode))  \(timestamp(snapshot.timestamp))"
  }
  /// Renders the shared process table header.
  static func processHeader() -> String {
    row([
      column("name", width: 10),
      column("pid", width: 7),
      column("cpu", width: 8),
      column("mem", width: 10),
      column("thr", width: 5),
    ])
  }

  /// Renders one process metrics row.
  static func processLine(_ process: IPC.ProcessMetrics, name: String? = nil) -> String {
    row([
      column(name ?? process.name, width: 10),
      column(process.pid.map(String.init) ?? "-", width: 7),
      column(percent(process.cpuPercent), width: 8),
      column(bytes(process.residentSizeBytes), width: 10),
      column(process.threadCount.map(String.init) ?? "-", width: 5),
    ])
  }

  /// Formats a snapshot timestamp for display.
  static func timestamp(_ date: Date) -> String {
    return timestampFormatter.string(from: date)
  }

  /// Formats an optional date as elapsed seconds from now.
  static func relative(_ date: Date?) -> String {
    guard let date else { return "-" }

    let delta = max(0, Int(Date().timeIntervalSince(date)))
    return "\(delta)s"
  }

  /// Formats a Boolean value as `yes` or `no`.
  static func yesNo(_ value: Bool) -> String {
    return value ? "yes" : "no"
  }

  /// Formats an optional numeric metric value.
  static func number(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "-" }

    if value == 0 {
      return "0.0"
    }

    if value < 1 {
      return String(format: "%.2f", value)
    }

    return String(format: "%.1f", value)
  }

  /// Formats an optional percentage metric value.
  static func percent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "-" }

    if value == 0 {
      return "0.0%"
    }

    if value < 1 {
      return String(format: "%.2f%%", value)
    }

    return String(format: "%.1f%%", value)
  }

  /// Formats an optional byte count.
  static func bytes(_ value: UInt64?) -> String {
    guard let value, value <= UInt64(Int64.max) else { return "-" }
    return byteFormatter.string(fromByteCount: Int64(value))
  }

  /// Formats the metrics sample interval.
  static func sampleInterval(_ value: Double) -> String {
    return "\(number(value))s"
  }

  /// Returns the arithmetic mean for a series of values.
  static func average(_ values: [Double]) -> Double? {
    let finiteValues = values.filter(\.isFinite)
    guard !finiteValues.isEmpty else { return nil }
    return finiteValues.reduce(0, +) / Double(finiteValues.count)
  }

  /// Joins preformatted columns into one table row.
  static func row(_ columns: [String]) -> String {
    return columns.joined(separator: "  ")
  }

  /// Horizontal alignment for fixed-width table columns.
  enum ColumnAlignment {
    /// Left-aligns column text.
    case left
    /// Right-aligns column text.
    case right
  }

  /// Pads or truncates one value to a fixed-width column.
  static func column(_ value: String, width: Int, alignment: ColumnAlignment = .left)
    -> String
  {
    if value.count >= width {
      return String(value.prefix(width))
    }

    let padding = String(repeating: " ", count: width - value.count)

    switch alignment {
    case .left:
      return value + padding
    case .right:
      return padding + value
    }
  }
}
