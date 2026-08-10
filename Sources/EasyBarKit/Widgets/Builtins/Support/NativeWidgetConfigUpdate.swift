import SwiftTOMLEdit

/// Commits native-widget runtime state only after a comment-preserving TOML write succeeds.
@MainActor
enum NativeWidgetConfigUpdate {
  /// Persists one batch and runs the in-memory commit exactly once on success.
  @discardableResult
  static func persist(
    edits: [TOMLEdit],
    using persistence: ConfigPersistence,
    commit: () -> Void
  ) -> Bool {
    guard persistence.apply(edits) else { return false }
    commit()
    return true
  }
}
