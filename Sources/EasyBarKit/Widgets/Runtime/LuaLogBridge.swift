import EasyBarShared
import Foundation

/// Classification of one line received from the Lua runtime's stderr pipe.
enum LuaStderrLineClassification: Sendable {
  /// One structured EasyBar log message with its normalized severity.
  case structured(ProcessLogLevel)
  /// Unstructured output that bypassed the Lua logging protocol.
  case raw
}

/// Routes structured stderr lines from the Lua runtime into the normal logger.
final class LuaLogBridge {
  private let logger: ProcessLogger
  private let prefix = "EASYBAR_LUA_LOG\t"

  /// Creates one Lua log bridge.
  init(logger: ProcessLogger) {
    self.logger = logger
  }

  /// Handles one stderr line from the Lua runtime.
  @discardableResult
  func handle(_ line: String) -> LuaStderrLineClassification {
    guard line.hasPrefix(prefix) else {
      logRawStderr(line)
      return .raw
    }

    let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)

    guard parts.count == 4 else {
      logRawStderr(line)
      return .raw
    }

    let level = ProcessLogLevel.normalized(String(parts[1])) ?? .info
    let source = String(parts[2])
    let message = String(parts[3])

    logFormatted(level: level, source: source, message: message)
    return .structured(level)
  }

  /// Logs one raw stderr line that does not follow the structured format.
  private func logRawStderr(_ line: String) {
    logger.error(
      "lua stderr line",
      .field("bytes", line.utf8.count),
      .field("runtime", ProcessLogRuntime.lua.rawValue)
    )
  }

  /// Logs one structured Lua message at the requested level.
  private func logFormatted(level: ProcessLogLevel, source: String, message: String) {
    let field: ProcessLogField =
      source == "runtime"
      ? .field("component", "runtime")
      : .field("widget", source)

    let runtimeField = ProcessLogField.field("runtime", ProcessLogRuntime.lua.rawValue)

    switch level {
    case .trace:
      logger.trace(message, field, runtimeField)
    case .debug:
      logger.debug(message, field, runtimeField)
    case .info:
      logger.info(message, field, runtimeField)
    case .warn:
      logger.warn(message, field, runtimeField)
    case .error:
      logger.error(message, field, runtimeField)
    }
  }
}
