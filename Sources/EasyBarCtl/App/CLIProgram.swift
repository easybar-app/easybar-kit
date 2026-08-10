import EasyBarShared
import Foundation

/// Frontend-specific presentation settings for the shared EasyBar CLI implementation.
struct CLIProgram: Equatable {
  let commandName: String
  let displayName: String
  let supportsHelperAgents: Bool

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    commandName = Self.nonEmpty(environment[SharedEnvironmentKeys.cliName]) ?? "easybar"
    displayName = Self.nonEmpty(environment[SharedEnvironmentKeys.cliDisplayName]) ?? "EasyBar"
    supportsHelperAgents = Self.boolValue(
      environment[SharedEnvironmentKeys.cliSupportsHelperAgents],
      fallback: true
    )
  }

  static var current: CLIProgram { CLIProgram() }

  var loggerLabel: String {
    commandName.replacingOccurrences(of: "-", with: "_") + "ctl"
  }

  func validate(action: CLIAction) throws {
    guard !supportsHelperAgents else { return }

    switch action {
    case .restartAgent, .versionAgent:
      throw AppError.message("helper-agent commands are not available in \(commandName)")
    default:
      return
    }
  }

  func isVisible(commandPath: [String]) -> Bool {
    supportsHelperAgents || commandPath.first != "agent"
  }

  func userFacingDescription(_ value: String) -> String {
    var result = value.replacingOccurrences(of: "EasyBar", with: displayName)
    if !supportsHelperAgents {
      result = result.replacingOccurrences(
        of: "the bar, widgets, and agent-backed data",
        with: "widgets and runtime data"
      )
    }
    return result
  }

  private static func nonEmpty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private static func boolValue(_ value: String?, fallback: Bool) -> Bool {
    guard let value = nonEmpty(value)?.lowercased() else { return fallback }
    switch value {
    case "1", "true", "yes", "on":
      return true
    case "0", "false", "no", "off":
      return false
    default:
      return fallback
    }
  }
}
