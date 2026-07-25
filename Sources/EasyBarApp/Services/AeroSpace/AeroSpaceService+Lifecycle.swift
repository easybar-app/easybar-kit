import EasyBarShared
import Foundation

// MARK: - Service Activation

extension AeroSpaceService {
  /// Starts expensive AeroSpace observation once the first consumer is present.
  @discardableResult
  func activateIfNeeded(source: String) -> Bool {
    let shouldActivate = withLock { coordination -> Bool in
      guard coordination.running, !coordination.active, !coordination.consumers.isEmpty else {
        return false
      }

      coordination.active = true
      coordination.generation &+= 1
      return true
    }

    guard shouldActivate else { return false }

    logger.debug(
      "aerospace service activate begin",
      .field("source", source),
      .field("consumers", consumerCount)
    )

    subscriptionController.start()
    refresh()

    logger.debug("aerospace service activate end")
    return true
  }

  /// Stops AeroSpace observation once the last consumer disappears.
  func deactivateIfNeeded(reason: String) {
    let result = withLock {
      coordination -> (
        didDeactivate: Bool,
        refreshTask: Task<Void, Never>?,
        focusedStateTask: Task<Void, Never>?,
        workspaceFocusTask: Task<Void, Never>?
      ) in
      guard coordination.active else { return (false, nil, nil, nil) }

      coordination.active = false
      coordination.generation &+= 1
      coordination.pendingRefreshToken = nil
      coordination.pendingFocusedStateToken = nil
      coordination.pendingWorkspaceFocusToken = nil
      let refreshTask = coordination.refreshTask
      let focusedStateTask = coordination.focusedStateTask
      let workspaceFocusTask = coordination.workspaceFocusTask
      coordination.refreshTask = nil
      coordination.focusedStateTask = nil
      coordination.workspaceFocusTask = nil

      return (true, refreshTask, focusedStateTask, workspaceFocusTask)
    }

    guard result.didDeactivate else { return }

    result.refreshTask?.cancel()
    result.focusedStateTask?.cancel()
    result.workspaceFocusTask?.cancel()
    subscriptionController.stop()
    subscriptionRefreshScheduler.cancel()
    refreshRetryScheduler.cancel()
    Task { await versionValidationCache.cancel() }

    logger.debug(
      "aerospace service deactivate end",
      .field("reason", reason)
    )
  }
}
