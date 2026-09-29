import EasyBarShared
import Foundation

/// Parsed options for the `easybar logs` command.
struct LogCommandOptions: Equatable {
  /// The widget for this log command options.
  var widget: String?
  /// The runtime for this log command options.
  var runtime: ProcessLogRuntime?
  /// The minimum level accepted by this log command options.
  var minimumLevel: ProcessLogLevel?
  /// The stable identifier for this log command options.
  var requestID: String?
  /// The since for this log command options.
  var since: String?
  /// The history limit for this log command options.
  var historyLimit: Int?
  /// Whether the follow option is enabled for this log command options.
  var follow = false
  /// Whether the JSON option is enabled for this log command options.
  var json = false
}

/// Mutable parsing state for log-specific command-line options.
struct LogCommandOptionState {
  /// The options for this log command option state.
  var options = LogCommandOptions(historyLimit: 100)
  /// Whether the lines specified option is enabled for this log command option state.
  var linesSpecified = false
  /// Whether the all history option is enabled for this log command option state.
  var allHistory = false

  /// Finalizes the accumulated state.
  mutating func finalize() throws -> LogCommandOptions {
    guard !(linesSpecified && allHistory) else {
      throw AppError.message("--lines cannot be combined with --all")
    }

    if shouldReadAllHistory {
      options.historyLimit = nil
    }
    return options
  }

  /// Whether the should read all history option is enabled for this log command option state.
  private var shouldReadAllHistory: Bool {
    allHistory || (hasHistoryFilter && !linesSpecified)
  }

  /// Whether the has history filter option is enabled for this log command option state.
  private var hasHistoryFilter: Bool {
    options.requestID != nil || options.since != nil
  }
}
