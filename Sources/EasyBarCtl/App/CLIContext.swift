import Darwin
import EasyBarShared

/// Shared runtime context for CLI operations.
struct AppContext {
  /// Logger used for optional debug output.
  let logger: ProcessLogger

  /// Creates a context and enables debug logging when requested.
  init(debugEnabled: Bool) {
    logger = ProcessLogger(
      label: "easybarctl",
      minimumLevel: debugEnabled ? .debug : .info,
      outputStream: stderr,
      errorStream: stderr
    )
  }

  /// Logs a debug line.
  func debug(_ message: String) {
    logger.debug(message)
  }
}

/// Errors used to control CLI flow and user-facing output.
enum AppError: Error {
  /// Requests root, group, or command-specific usage output.
  case showUsage([String])
  /// Requests version output.
  case showVersion
  /// Carries a user-facing error message.
  case message(String)
  /// Reports an operational failure without appending command usage.
  case commandFailed(String)
  /// Returns a failing status after the command already printed its diagnostics.
  case reportedFailure
}
