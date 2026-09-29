import EasyBarShared
import Foundation

/// Frontend-specific presentation settings for the shared EasyBar CLI implementation.
struct CLIProgram: Equatable {
  /// The command name for this cli program.
  let commandName: String
  /// The display name for this cli program.
  let displayName: String
  /// Whether the supports helper agents option is enabled for this cli program.
  let supportsHelperAgents: Bool

  /// Creates a cli program.
  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    commandName = Self.nonEmpty(environment[SharedEnvironmentKeys.cliName]) ?? "easybar"
    displayName = Self.nonEmpty(environment[SharedEnvironmentKeys.cliDisplayName]) ?? "EasyBar"
    supportsHelperAgents = Self.boolValue(
      environment[SharedEnvironmentKeys.cliSupportsHelperAgents],
      fallback: true
    )
  }

  /// The current for this cli program.
  static var current: CLIProgram { CLIProgram() }

  /// The logger label for this cli program.
  var loggerLabel: String {
    commandName.replacingOccurrences(of: "-", with: "_") + "ctl"
  }

  /// Validates the requested input.
  func validate(action: CLIAction) throws {
    guard !supportsHelperAgents else { return }

    switch action {
    case .restartAgent, .versionAgent:
      throw AppError.message("helper-agent commands are not available in \(commandName)")
    default:
      return
    }
  }

  /// Evaluates the visible condition.
  func isVisible(commandPath: [String]) -> Bool {
    supportsHelperAgents || commandPath.first != "agent"
  }

  /// Returns the user facing description.
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

  /// Returns the non empty.
  private static func nonEmpty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  /// Returns the bool value.
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
