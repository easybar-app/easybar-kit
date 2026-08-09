import EasyBarShared
import Foundation

/// Parsed options for the `easybar logs` command.
struct LogCommandOptions: Equatable {
  var widget: String?
  var runtime: ProcessLogRuntime?
  var minimumLevel: ProcessLogLevel?
  var requestID: String?
  var since: String?
  var historyLimit: Int?
  var follow = false
  var json = false
}

/// Mutable parsing state for log-specific command-line options.
struct LogCommandOptionState {
  var options = LogCommandOptions(historyLimit: 100)
  var linesSpecified = false
  var allHistory = false

  mutating func finalize() throws -> LogCommandOptions {
    guard !(linesSpecified && allHistory) else {
      throw AppError.message("--lines cannot be combined with --all")
    }

    if shouldReadAllHistory {
      options.historyLimit = nil
    }
    return options
  }

  private var shouldReadAllHistory: Bool {
    allHistory || (hasHistoryFilter && !linesSpecified)
  }

  private var hasHistoryFilter: Bool {
    options.requestID != nil || options.since != nil
  }
}
