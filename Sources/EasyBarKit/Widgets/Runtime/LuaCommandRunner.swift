@preconcurrency import EasyBarShared
import Foundation

/// Result returned by one host-owned Lua command execution.
struct LuaCommandResult: Sendable {
  /// Normalized output with trailing line endings removed.
  let output: String
  /// Exact bytes decoded as UTF-8 for Lua's `raw_output` option.
  let rawOutput: String
  let status: Int32

  init(output: String, status: Int32) {
    self.rawOutput = output
    self.output = Self.removingTrailingLineEndings(from: output)
    self.status = status
  }

  /// Removes only CR/LF terminators; spaces and tabs remain command data.
  private static func removingTrailingLineEndings(from value: String) -> String {
    var result = value
    while result.last == "\n" || result.last == "\r" {
      result.removeLast()
    }
    return result
  }
}

/// One process invocation requested by the Lua runtime.
enum LuaCommandInvocation: Sendable, Equatable {
  case shell(String)
  case executable([String])

  var displayName: String {
    switch self {
    case .shell:
      return "shell command"
    case .executable(let arguments):
      return arguments.first ?? "executable"
    }
  }

  var payloadByteCount: Int {
    switch self {
    case .shell(let command):
      return command.utf8.count
    case .executable(let arguments):
      return arguments.reduce(0) { $0 + $1.utf8.count }
    }
  }

  var asynchronousAPIName: String {
    switch self {
    case .shell:
      return "easybar.exec_async"
    case .executable:
      return "easybar.spawn_async"
    }
  }
}

/// Adapts Lua command requests to the shared process executor.
final class LuaCommandRunner: @unchecked Sendable {
  struct Limits: Sendable {
    let timeoutSeconds: TimeInterval
    let maxOutputBytes: Int

    static let timedOutStatus: Int32 = 124
    static let cancelledStatus: Int32 = 130
    static let outputLimitStatus: Int32 = 65
    static let readFailureStatus: Int32 = 74
  }

  private static let shellPath = "/bin/sh"

  private let logger: ProcessLogger
  private let executor: ProcessExecutor

  /// Creates one Lua command runner.
  init(logger: ProcessLogger) {
    self.logger = logger
    self.executor = ProcessExecutor(logger: logger.child("process"))
  }

  /// Runs one shell command through `/bin/sh -lc`.
  func run(
    command: String,
    limits: Limits,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async -> LuaCommandResult {
    await run(invocation: .shell(command), limits: limits, environment: environment)
  }

  /// Runs one executable directly without shell parsing or interpolation.
  func run(
    arguments: [String],
    limits: Limits,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async -> LuaCommandResult {
    await run(invocation: .executable(arguments), limits: limits, environment: environment)
  }

  /// Runs one validated Lua process invocation.
  func run(
    invocation: LuaCommandInvocation,
    limits: Limits,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async -> LuaCommandResult {
    do {
      let launch = try launchInput(for: invocation, environment: environment)
      let request = ProcessExecutionRequest(
        executablePath: launch.executablePath,
        arguments: launch.arguments,
        environment: environment,
        timeout: normalizedTimeout(limits.timeoutSeconds),
        standardOutputLimit: max(1, limits.maxOutputBytes),
        mergeStandardError: true
      )
      let result = try await executor.run(request)
      return commandResult(from: result, invocation: invocation, limits: limits)
    } catch is CancellationError {
      logger.debug(
        "lua command cancelled before launch",
        .field("command_bytes", invocation.payloadByteCount)
      )
      return LuaCommandResult(output: "", status: Limits.cancelledStatus)
    } catch let error as ProcessSpawnError {
      return launchFailure(error, invocation: invocation)
    } catch {
      logger.warn(
        "failed to launch lua command",
        .field("command_bytes", invocation.payloadByteCount),
        .field("error", "\(error)")
      )
      return LuaCommandResult(output: "failed to launch command: \(error)", status: 1)
    }
  }

  /// Resolves shell and direct-executable launch inputs.
  private func launchInput(
    for invocation: LuaCommandInvocation,
    environment: [String: String]
  ) throws -> (executablePath: String, arguments: [String]) {
    switch invocation {
    case .shell(let command):
      return (Self.shellPath, [Self.shellPath, "-lc", command])
    case .executable(let arguments):
      guard let executable = arguments.first, !executable.isEmpty else {
        throw ProcessSpawnError.emptyExecutable
      }
      return (
        try ProcessSpawnSupport.resolveExecutable(executable, environment: environment),
        arguments
      )
    }
  }

  /// Preserves the previous safe behavior for invalid runtime timeout overrides.
  private func normalizedTimeout(_ timeoutSeconds: TimeInterval) -> TimeInterval? {
    guard timeoutSeconds.isFinite, timeoutSeconds > 0 else { return nil }
    return timeoutSeconds
  }

  /// Maps one shared executor result to the Lua command protocol.
  private func commandResult(
    from result: ProcessExecutionResult,
    invocation: LuaCommandInvocation,
    limits: Limits
  ) -> LuaCommandResult {
    let rawOutput = String(decoding: result.standardOutput, as: UTF8.self)

    switch result.outcome {
    case .timedOut:
      logger.warn(
        "lua command timed out",
        .field("command_bytes", invocation.payloadByteCount),
        .field("timeout_seconds", limits.timeoutSeconds)
      )
      return LuaCommandResult(output: rawOutput, status: Limits.timedOutStatus)

    case .cancelled:
      logger.debug(
        "lua command cancelled",
        .field("command_bytes", invocation.payloadByteCount)
      )
      return LuaCommandResult(output: rawOutput, status: Limits.cancelledStatus)

    case .outputLimitExceeded:
      logger.warn(
        "lua command output exceeded limit",
        .field("command_bytes", invocation.payloadByteCount),
        .field("max_output_bytes", limits.maxOutputBytes)
      )
      return LuaCommandResult(output: rawOutput, status: Limits.outputLimitStatus)

    case .readFailed(_, let errnoValue):
      logger.warn(
        "failed to read lua command output",
        .field("command_bytes", invocation.payloadByteCount),
        .field("errno", errnoValue)
      )
      return LuaCommandResult(
        output: appendingDiagnostic(
          "command output read failed (errno=\(errnoValue))",
          to: rawOutput
        ),
        status: Limits.readFailureStatus
      )

    case .reapFailed(let errnoValue):
      logger.warn(
        "failed to reap lua command",
        .field("command_bytes", invocation.payloadByteCount),
        .field("errno", errnoValue)
      )
      return LuaCommandResult(
        output: appendingDiagnostic("failed to reap command (errno=\(errnoValue))", to: rawOutput),
        status: 1
      )

    case .completed:
      let exitStatus = result.termination.shellExitStatus
      if exitStatus == 127 {
        let output =
          rawOutput.isEmpty
          ? "command not found: \(invocation.displayName)"
          : rawOutput
        logger.warn(
          "lua command not found",
          .field("command_bytes", invocation.payloadByteCount),
          .field("status", exitStatus)
        )
        return LuaCommandResult(output: output, status: exitStatus)
      }

      if exitStatus != 0 {
        logger.debug(
          "lua command exited non-zero",
          .field("command_bytes", invocation.payloadByteCount),
          .field("status", exitStatus)
        )
      }
      return LuaCommandResult(output: rawOutput, status: exitStatus)
    }
  }

  /// Maps launch validation and resolution failures without starting a process.
  private func launchFailure(
    _ error: ProcessSpawnError,
    invocation: LuaCommandInvocation
  ) -> LuaCommandResult {
    logger.warn(
      "failed to launch lua command",
      .field("command_bytes", invocation.payloadByteCount),
      .field("error", error.localizedDescription)
    )

    switch error {
    case .executableNotFound:
      return LuaCommandResult(
        output: "command not found: \(invocation.displayName)",
        status: 127
      )
    default:
      return LuaCommandResult(
        output: "failed to launch command: \(error.localizedDescription)", status: 1)
    }
  }

  /// Appends a host diagnostic without hiding already captured process output.
  private func appendingDiagnostic(_ diagnostic: String, to output: String) -> String {
    guard !output.isEmpty else { return diagnostic }
    guard output.hasSuffix("\n") else { return "\(output)\n\(diagnostic)" }
    return output + diagnostic
  }
}
