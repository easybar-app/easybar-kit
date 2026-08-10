import EasyBarShared
import Foundation

/// Executes one AeroSpace CLI command.
protocol AeroSpaceCommandRunning: Sendable {
  /// Runs one command and returns trimmed stdout only when it succeeds.
  func run(arguments: [String]) async -> String?
}

/// Runs the AeroSpace CLI through the shared process executor.
final class AeroSpaceCommandRunner: AeroSpaceCommandRunning, @unchecked Sendable {
  /// Logger used for AeroSpace command diagnostics.
  private let logger: ProcessLogger
  /// Resolves the AeroSpace executable path.
  private let executablePathResolver: () -> String?
  /// Maximum time one short-lived AeroSpace CLI command may run.
  private let commandTimeout: TimeInterval
  /// Maximum stdout or stderr bytes kept for one AeroSpace command.
  private let commandOutputLimit: Int
  /// Shared process runner with bounded pipe and process-group cleanup.
  private let processExecutor: ProcessExecutor

  /// Creates one AeroSpace command runner.
  init(
    logger: ProcessLogger,
    executablePathResolver: @escaping () -> String? = AeroSpaceCommandRunner.defaultExecutablePath,
    commandTimeout: TimeInterval = 5,
    commandOutputLimit: Int = 1_048_576
  ) {
    self.logger = logger
    self.executablePathResolver = executablePathResolver
    self.commandTimeout = Self.normalizedTimeout(commandTimeout)
    self.commandOutputLimit = max(1, commandOutputLimit)
    self.processExecutor = ProcessExecutor(logger: logger.child("process"))
  }

  /// Executes one AeroSpace command and returns trimmed stdout on success.
  func run(arguments: [String]) async -> String? {
    guard let executable = executablePathResolver() else {
      logger.debug("aerospace executable not found")
      return nil
    }

    let request = ProcessExecutionRequest(
      executablePath: executable,
      arguments: [executable] + arguments,
      environment: ProcessInfo.processInfo.environment,
      timeout: commandTimeout,
      standardOutputLimit: commandOutputLimit,
      standardErrorLimit: commandOutputLimit
    )

    let result: ProcessExecutionResult
    do {
      result = try await processExecutor.run(request)
    } catch {
      logger.debug(
        "failed to run aerospace",
        .field("args", arguments.joined(separator: " ")),
        .field("error", error)
      )
      return nil
    }

    switch result.outcome {
    case .completed:
      break
    case .timedOut:
      logger.warn(
        "aerospace command timed out",
        .field("args", arguments.joined(separator: " ")),
        .field("timeout_seconds", commandTimeout)
      )
      return nil
    case .cancelled:
      logger.debug(
        "aerospace command cancelled",
        .field("args", arguments.joined(separator: " "))
      )
      return nil
    case .outputLimitExceeded(let stream):
      logger.warn(
        "aerospace command output exceeded limit",
        .field("args", arguments.joined(separator: " ")),
        .field("stream", stream.rawValue),
        .field("max_output_bytes", commandOutputLimit)
      )
      return nil
    case .readFailed(let stream, let errnoValue):
      logger.debug(
        "failed to read aerospace output",
        .field("args", arguments.joined(separator: " ")),
        .field("stream", stream.rawValue),
        .field("errno", errnoValue)
      )
      return nil
    case .reapFailed(let errnoValue):
      logger.warn(
        "failed to reap aerospace command",
        .field("args", arguments.joined(separator: " ")),
        .field("errno", errnoValue)
      )
      return nil
    }

    let exitStatus = result.termination.shellExitStatus
    guard exitStatus == 0 else {
      let stderr = String(decoding: result.standardError, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      logger.debug(
        "aerospace command exited",
        .field("status", exitStatus),
        .field("args", arguments.joined(separator: " ")),
        .field("stderr_bytes", stderr.utf8.count)
      )
      return nil
    }

    return String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Resolves the AeroSpace binary path from `PATH`, then known install locations.
  static func defaultExecutablePath() -> String? {
    defaultExecutablePath(environment: ProcessInfo.processInfo.environment)
  }

  /// Resolves the AeroSpace binary path from one environment snapshot.
  static func defaultExecutablePath(environment: [String: String]) -> String? {
    let pathCandidates =
      environment[SharedEnvironmentKeys.path]?
      .split(separator: ":")
      .map(String.init)
      .filter { !$0.isEmpty }
      .map { URL(fileURLWithPath: $0).appendingPathComponent("aerospace").path } ?? []

    let fallbackCandidates = [
      "/opt/homebrew/bin/aerospace",
      "/usr/local/bin/aerospace",
      "/Applications/AeroSpace.app/Contents/MacOS/aerospace",
    ]

    let fileManager = FileManager.default
    return uniqueCandidates(pathCandidates + fallbackCandidates)
      .first(where: { fileManager.isExecutableFile(atPath: $0) })
  }

  /// Removes duplicate candidate paths while preserving lookup order.
  private static func uniqueCandidates(_ candidates: [String]) -> [String] {
    var seen = Set<String>()
    return candidates.filter { seen.insert($0).inserted }
  }

  /// Normalizes a caller-supplied timeout without allowing NaN or infinity.
  private static func normalizedTimeout(_ value: TimeInterval) -> TimeInterval {
    guard value.isFinite, value > 0 else { return 5 }
    return max(0.001, value)
  }
}
