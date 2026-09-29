import Foundation

/// Preserves UI interaction ordering while forwarding events asynchronously.
@MainActor
final class WidgetEventDispatcher {
  static let shared = WidgetEventDispatcher()

  private var tailTask: Task<Void, Never>?

  /// Enqueues one value for asynchronous delivery.
  func enqueue(_ operation: @escaping @Sendable () async -> Void) {
    let previousTask = tailTask
    tailTask = Task {
      await previousTask?.value
      await operation()
    }
  }

  /// Waits for until idle.
  func waitUntilIdle() async {
    await tailTask?.value
  }
}
