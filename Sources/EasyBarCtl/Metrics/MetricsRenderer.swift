import EasyBarShared
import Foundation

/// Renders metrics output.
enum MetricsRenderer {
  /// Number of historical samples rendered in watch-mode sparklines.
  static let watchGraphWidth = 32
  /// Minimum terminal width used for side-by-side watch tiles.
  static let wideWatchMinimumWidth = 100
  /// Maximum live dashboard width, keeping related tile columns visually grouped.
  static let wideWatchMaximumWidth = 120
  /// Formatter used for metrics snapshot timestamps.
  static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
  }()
  /// Formatter used for memory values.
  nonisolated(unsafe) static let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .memory
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter
  }()

  /// Renders a complete one-shot metrics snapshot.
  static func snapshotText(_ snapshot: IPC.MetricsSnapshot) -> String {
    let sections = [
      header(snapshot, live: false),
      processes(snapshot),
      runtime(snapshot),
      subscriptions(snapshot),
      agents(snapshot),
      widgets(snapshot),
      events(snapshot),
    ]

    return sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  /// Renders one live metrics frame for watch mode.
  static func watchText(
    _ snapshot: IPC.MetricsSnapshot,
    history: MetricsHistory,
    terminalWidth: Int = 80
  ) -> String {
    let dashboard =
      terminalWidth >= wideWatchMinimumWidth
      ? wideWatchDashboard(snapshot, terminalWidth: terminalWidth)
      : narrowWatchDashboard(snapshot, terminalWidth: terminalWidth)
    let sections = [
      header(snapshot, live: true),
      graphs(snapshot, history: history),
      dashboard,
    ]

    return sections.filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n"
  }
}
