import Darwin
import EasyBarShared
import Foundation

/// CLI entry point.
@main
enum EasyBarCtlApp {
  static func main() async {
    exit(await AppController().run())
  }
}

/// Runs the CLI flow.
private struct AppController {
  func run() async -> Int32 {
    do {
      let parsed = try parseArguments(CommandLine.arguments)
      let context = AppContext(debugEnabled: parsed.debugEnabled)

      switch parsed.action {
      case .validateConfig(let configPath):
        let socketPath = try resolvedControlSocketPath(
          explicitPath: parsed.socketPath,
          context: context
        )
        try validateConfig(configPath: configPath, socketPath: socketPath, context: context)

      case .control(let command):
        let socketPath = try resolvedControlSocketPath(
          explicitPath: parsed.socketPath,
          context: context
        )
        try sendCommand(command, to: socketPath, context: context)

      case .metrics(let watch):
        let socketPath = try resolvedControlSocketPath(
          explicitPath: parsed.socketPath,
          context: context
        )
        if watch {
          try streamMetrics(to: socketPath, context: context)
        } else {
          let snapshot = try fetchMetricsSnapshot(from: socketPath, context: context)
          CLIOutput.printMetricsSnapshot(snapshot)
        }

      case .restartAgent(let target):
        switch target {
        case .calendar:
          try restartCalendarAgent(socketPath: parsed.socketPath, context: context)
        case .network:
          try restartNetworkAgent(socketPath: parsed.socketPath, context: context)
        case .all:
          try restartAgents(context: context)
        }

      case .versionAgent(let target, let json):
        try showAgentVersions(
          target: target,
          json: json,
          socketPath: parsed.socketPath,
          context: context
        )

      case .logs(let options):
        try showLogs(
          options: options,
          explicitSocketPath: parsed.socketPath,
          context: context
        )

      case .inbox(let command):
        let socketPath = try resolvedControlSocketPath(
          explicitPath: parsed.socketPath,
          context: context
        )
        try runInboxCommand(command, socketPath: socketPath, context: context)

      case .installWidgetPackage(let options):
        try await installWidgetPackage(options: options, context: context)

      case .searchWidgetPackages(let options):
        try await searchWidgetPackages(options: options, context: context)

      case .uninstallWidgetPackage(let name):
        try uninstallWidgetPackage(name: name, context: context)
      }

      return 0
    } catch AppError.showUsage(let topic) {
      CLIOutput.printUsage(topic: topic)
      return 0
    } catch AppError.showVersion {
      CLIOutput.printVersion()
      return 0
    } catch AppError.message(let message) {
      CLIOutput.printError(message)
    } catch AppError.commandFailed(let message) {
      CLIOutput.printError(message)
      return 1
    } catch AppError.reportedFailure {
      return 1
    } catch {
      CLIOutput.printError("\(error)")
    }

    CLIOutput.printUsage()
    return 1
  }
}

/// Resolves the control socket and reports malformed shared configuration clearly.
private func resolvedControlSocketPath(
  explicitPath: String?,
  context: AppContext
) throws -> String {
  do {
    let resolution = try SharedRuntimeSocketResolver.controlSocket(explicitPath: explicitPath)
    logSocketResolution(resolution, kind: "control", context: context)
    return resolution.path
  } catch {
    throw AppError.message(
      "failed to resolve control socket from shared runtime config: "
        + "\(error.localizedDescription). Use --socket PATH to bypass config resolution."
    )
  }
}

/// Logs one resolved CLI socket source.
func logSocketResolution(
  _ resolution: SharedRuntimeSocketResolution,
  kind: String,
  context: AppContext
) {
  switch resolution.source {
  case .explicit:
    context.debug("resolved \(kind) socket from --socket: \(resolution.path)")

  case .sharedConfig(let path):
    context.debug(
      "resolved \(kind) socket from shared config \(path): \(resolution.path)"
    )
  }
}
