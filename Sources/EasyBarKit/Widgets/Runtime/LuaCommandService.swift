import Dispatch
import EasyBarShared
import Foundation

/// Handles Lua command requests, async command limits, and command responses.
actor LuaCommandService {
  private struct ActiveAsyncCommand {
    let runtimeSessionID: UInt64
    let task: Task<Void, Never>
    let widget: String?
    let operation: String?
  }

  private struct LuaCommandResponse: Encodable {
    let protocolVersion = easyBarLuaRuntimeProtocolVersion
    let type = "command_response"
    let token: String
    let output: String
    let status: Int32
    let durationMS: Int

    enum CodingKeys: String, CodingKey {
      case protocolVersion = "protocol_version"
      case type
      case token
      case output
      case status
      case durationMS = "duration_ms"
    }
  }

  private let logger: ProcessLogger
  private let luaRuntime: LuaRuntime
  private let configManager: ConfigManager
  private let commandRunner: LuaCommandRunner
  private let encoder = JSONEncoder()

  private var activeAsyncCommandSessionID: UInt64?
  private var activeAsyncCommands: [String: ActiveAsyncCommand] = [:]

  init(logger: ProcessLogger, luaRuntime: LuaRuntime, configManager: ConfigManager) {
    self.logger = logger
    self.luaRuntime = luaRuntime
    self.configManager = configManager
    self.commandRunner = LuaCommandRunner(logger: logger)
  }

  /// Resets async command accounting during runtime start or shutdown.
  func resetActiveAsyncCommandCount() {
    cancelActiveAsyncCommands()
    activeAsyncCommandSessionID = nil
  }

  /// Handles one Lua command execution request.
  func handleCommandRequest(
    token: String,
    invocation: LuaCommandInvocation,
    isSynchronous: Bool,
    timeoutSecondsOverride: TimeInterval?,
    maxOutputBytesOverride: Int?,
    widget: String?,
    operation: String?,
    runtimeSessionID: UInt64,
    isRuntimeSessionActive: @escaping @Sendable (UInt64) async -> Bool
  ) async {
    let commandSettings = await configManager.luaCommandSettings()
    let commandLimits = LuaCommandRunner.Limits(
      timeoutSeconds: timeoutSecondsOverride ?? commandSettings.timeoutSeconds,
      maxOutputBytes: maxOutputBytesOverride ?? commandSettings.maxOutputBytes
    )

    let requestID = logRequestID(for: token)
    let startedAt = DispatchTime.now().uptimeNanoseconds
    logCommandStarted(
      requestID: requestID,
      isSynchronous: isSynchronous,
      invocation: invocation,
      limits: commandLimits,
      widget: widget,
      operation: operation
    )

    if isSynchronous {
      let result = await commandRunner.run(
        invocation: invocation,
        limits: commandLimits,
        environment: commandSettings.environment
      )
      let durationMS = elapsedMilliseconds(since: startedAt)
      logCommandCompleted(
        requestID: requestID,
        isSynchronous: true,
        result: result,
        durationMS: durationMS,
        widget: widget,
        operation: operation
      )

      guard await isRuntimeSessionActive(runtimeSessionID) else {
        logger.debug(
          "dropping stale sync lua command response",
          .field("request_id", requestID),
          .field("runtime_session_id", runtimeSessionID)
        )
        return
      }

      await sendCommandResponse(token: token, result: result, durationMS: durationMS)
      return
    }

    if activeAsyncCommandSessionID != runtimeSessionID {
      cancelActiveAsyncCommands()
      activeAsyncCommandSessionID = runtimeSessionID
    }

    if activeAsyncCommands[token] != nil {
      logger.warn(
        "lua async command rejected because token is already active",
        .field("request_id", requestID),
        .field("widget", widget ?? "unknown"),
        .field("operation", operation ?? "none")
      )
      await sendCommandResponse(
        token: token,
        result: LuaCommandResult(
          output: "\(invocation.asynchronousAPIName) rejected: duplicate active token",
          status: 69
        ),
        durationMS: elapsedMilliseconds(since: startedAt)
      )
      return
    }

    let maxAsyncJobs = commandSettings.maxAsyncJobs
    guard activeAsyncCommands.count < maxAsyncJobs else {
      logAsyncCommandRejected(
        requestID: requestID,
        invocation: invocation,
        activeJobs: activeAsyncCommands.count,
        maxJobs: maxAsyncJobs,
        widget: widget,
        operation: operation
      )
      await sendCommandResponse(
        token: token,
        result: LuaCommandResult(
          output: "\(invocation.asynchronousAPIName) rejected: max async job limit reached",
          status: 69
        ),
        durationMS: elapsedMilliseconds(since: startedAt)
      )
      return
    }

    let commandRunner = commandRunner

    let task = Task { [weak self] in
      let result = await commandRunner.run(
        invocation: invocation,
        limits: commandLimits,
        environment: commandSettings.environment
      )
      let durationMS = Self.elapsedMilliseconds(from: startedAt)
      await self?.logAsyncCommandCompletion(
        requestID: requestID,
        result: result,
        durationMS: durationMS,
        widget: widget,
        operation: operation
      )
      await self?.sendAsyncCommandResponse(
        token: token,
        result: result,
        durationMS: durationMS,
        runtimeSessionID: runtimeSessionID,
        isRuntimeSessionActive: isRuntimeSessionActive
      )
    }

    activeAsyncCommands[token] = ActiveAsyncCommand(
      runtimeSessionID: runtimeSessionID,
      task: task,
      widget: widget,
      operation: operation
    )
  }

  /// Cancels one host-owned asynchronous command from the active Lua runtime session.
  func cancelAsyncCommand(token: String, runtimeSessionID: UInt64) {
    guard activeAsyncCommandSessionID == runtimeSessionID else { return }
    guard let command = activeAsyncCommands[token], command.runtimeSessionID == runtimeSessionID
    else {
      logger.debug(
        "lua async cancellation ignored for unknown request",
        .field("request_id", logRequestID(for: token))
      )
      return
    }

    logCommandCancellation(
      requestID: logRequestID(for: token),
      widget: command.widget,
      operation: command.operation
    )
    command.task.cancel()
  }

  /// Sends one command response back into the Lua runtime.
  private func sendCommandResponse(
    token: String,
    result: LuaCommandResult,
    durationMS: Int
  ) async {
    let response = LuaCommandResponse(
      token: token,
      output: result.rawOutput,
      status: result.status,
      durationMS: durationMS
    )

    guard
      let data = try? encoder.encode(response),
      let encoded = String(data: data, encoding: .utf8)
    else {
      logger.error(
        "failed to encode lua command response",
        .field("request_id", logRequestID(for: token))
      )
      return
    }

    await luaRuntime.send(encoded)
  }

  /// Logs one completed asynchronous command before session filtering decides delivery.
  private func logAsyncCommandCompletion(
    requestID: String,
    result: LuaCommandResult,
    durationMS: Int,
    widget: String?,
    operation: String?
  ) {
    logCommandCompleted(
      requestID: requestID,
      isSynchronous: false,
      result: result,
      durationMS: durationMS,
      widget: widget,
      operation: operation
    )
  }

  /// Sends one async command response only when the originating runtime session is still active.
  private func sendAsyncCommandResponse(
    token: String,
    result: LuaCommandResult,
    durationMS: Int,
    runtimeSessionID: UInt64,
    isRuntimeSessionActive: @escaping @Sendable (UInt64) async -> Bool
  ) async {
    guard activeAsyncCommandSessionID == runtimeSessionID,
      let command = activeAsyncCommands[token],
      command.runtimeSessionID == runtimeSessionID
    else {
      logger.debug(
        "dropping async lua command response from stale session accounting",
        .field("request_id", logRequestID(for: token)),
        .field("runtime_session_id", runtimeSessionID)
      )
      return
    }
    activeAsyncCommands.removeValue(forKey: token)

    guard await isRuntimeSessionActive(runtimeSessionID) else {
      logger.debug(
        "dropping stale async lua command response",
        .field("request_id", logRequestID(for: token)),
        .field("runtime_session_id", runtimeSessionID)
      )
      return
    }

    await sendCommandResponse(token: token, result: result, durationMS: durationMS)
  }

  private func logCommandStarted(
    requestID: String,
    isSynchronous: Bool,
    invocation: LuaCommandInvocation,
    limits: LuaCommandRunner.Limits,
    widget: String?,
    operation: String?
  ) {
    if let operation {
      logger.debug(
        "lua command started",
        .field("request_id", requestID),
        .field("sync", isSynchronous),
        .field("widget", widget ?? "unknown"),
        .field("operation", operation),
        .field("command_bytes", invocation.payloadByteCount),
        .field("timeout_seconds", limits.timeoutSeconds),
        .field("max_output_bytes", limits.maxOutputBytes)
      )
    } else {
      logger.debug(
        "lua command started",
        .field("request_id", requestID),
        .field("sync", isSynchronous),
        .field("widget", widget ?? "unknown"),
        .field("command_bytes", invocation.payloadByteCount),
        .field("timeout_seconds", limits.timeoutSeconds),
        .field("max_output_bytes", limits.maxOutputBytes)
      )
    }
  }

  private func logCommandCompleted(
    requestID: String,
    isSynchronous: Bool,
    result: LuaCommandResult,
    durationMS: Int,
    widget: String?,
    operation: String?
  ) {
    if let operation {
      logger.debug(
        "lua command completed",
        .field("request_id", requestID),
        .field("sync", isSynchronous),
        .field("widget", widget ?? "unknown"),
        .field("operation", operation),
        .field("status", result.status),
        .field("duration_ms", durationMS)
      )
    } else {
      logger.debug(
        "lua command completed",
        .field("request_id", requestID),
        .field("sync", isSynchronous),
        .field("widget", widget ?? "unknown"),
        .field("status", result.status),
        .field("duration_ms", durationMS)
      )
    }
  }

  private func logAsyncCommandRejected(
    requestID: String,
    invocation: LuaCommandInvocation,
    activeJobs: Int,
    maxJobs: Int,
    widget: String?,
    operation: String?
  ) {
    if let operation {
      logger.warn(
        "lua async command rejected because limit was reached",
        .field("request_id", requestID),
        .field("widget", widget ?? "unknown"),
        .field("operation", operation),
        .field("active_async_jobs", activeJobs),
        .field("max_async_jobs", maxJobs),
        .field("command_bytes", invocation.payloadByteCount)
      )
    } else {
      logger.warn(
        "lua async command rejected because limit was reached",
        .field("request_id", requestID),
        .field("widget", widget ?? "unknown"),
        .field("active_async_jobs", activeJobs),
        .field("max_async_jobs", maxJobs),
        .field("command_bytes", invocation.payloadByteCount)
      )
    }
  }

  private func logCommandCancellation(
    requestID: String,
    widget: String?,
    operation: String?
  ) {
    if let operation {
      logger.debug(
        "cancelling lua async command",
        .field("request_id", requestID),
        .field("widget", widget ?? "unknown"),
        .field("operation", operation)
      )
    } else {
      logger.debug(
        "cancelling lua async command",
        .field("request_id", requestID),
        .field("widget", widget ?? "unknown")
      )
    }
  }

  /// Returns one compact request identifier for human-readable logs.
  private func logRequestID(for token: String) -> String {
    guard let sequence = token.split(separator: ":").last, !sequence.isEmpty else {
      return "lua-unknown"
    }
    return "lua-\(sequence)"
  }

  /// Returns elapsed monotonic milliseconds for one command.
  private func elapsedMilliseconds(since startedAt: UInt64) -> Int {
    Self.elapsedMilliseconds(from: startedAt)
  }

  private static func elapsedMilliseconds(from startedAt: UInt64) -> Int {
    let now = DispatchTime.now().uptimeNanoseconds
    guard now >= startedAt else { return 0 }
    return Int((now - startedAt) / 1_000_000)
  }

  /// Cancels and forgets all async command tasks owned by the current session.
  private func cancelActiveAsyncCommands() {
    let tasks = activeAsyncCommands.values.map(\.task)
    activeAsyncCommands.removeAll()

    for task in tasks {
      task.cancel()
    }
  }
}
