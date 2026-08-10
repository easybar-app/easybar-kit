import Foundation

/// Canonical AeroSpace CLI arguments used by native actions.
enum AeroSpaceCommandArguments {
  static func layout(_ mode: AeroSpaceLayoutMode) -> [String] {
    ["layout", mode.rawValue]
  }

  static let configPath = ["config", "--config-path"]
}
