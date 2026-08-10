import Foundation

/// Selects which host-owned built-in surfaces a frontend asks EasyBarKit to create.
///
/// Lua remains the public widget extension model. This policy only controls EasyBarKit's
/// internal surfaces, such as the shared Inbox or the full EasyBar built-in widget set.
public enum EasyBarBuiltInSurfacePolicy: String, Sendable {
  /// Enables every EasyBarKit built-in surface.
  case all
  /// Enables only the shared Inbox surface.
  case inboxOnly = "inbox_only"
  /// Disables all EasyBarKit built-in surfaces.
  case none

  /// Returns whether one internal built-in registration is allowed by this policy.
  func allows(_ id: String) -> Bool {
    switch self {
    case .all:
      return true
    case .inboxOnly:
      return id == "inbox"
    case .none:
      return false
    }
  }
}
