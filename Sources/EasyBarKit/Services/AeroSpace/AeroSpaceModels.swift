import AppKit
import Foundation

/// The current AeroSpace layout mode resolved from the focused window/container.
enum AeroSpaceLayoutMode: String, Codable, Sendable {
  case hTiles = "h_tiles"
  case vTiles = "v_tiles"
  case hAccordion = "h_accordion"
  case vAccordion = "v_accordion"
  case floating
  case unknown
}

/// A single running application shown inside a workspace.
struct SpaceApp: Identifiable, Hashable, Sendable {
  /// Stable application identifier used by the bar diffing model.
  let id: String
  /// Application bundle identifier.
  let bundleID: String
  /// Display name shown in the bar.
  let name: String
  /// Bundle path used for icons and activation.
  let bundlePath: String?

  /// Returns the application icon if the bundle path is known.
  func icon() -> NSImage? {
    guard let bundlePath, !bundlePath.isEmpty else { return nil }
    return NSWorkspace.shared.icon(forFile: bundlePath)
  }
}

/// A workspace shown in the bar.
struct SpaceItem: Identifiable, Hashable, Sendable {
  /// Stable workspace identifier.
  let id: String
  /// Workspace display name.
  let name: String
  /// Whether this workspace is focused.
  let isFocused: Bool
  /// Whether this workspace is visible.
  let isVisible: Bool
  /// Apps currently shown in this workspace.
  let apps: [SpaceApp]
}
