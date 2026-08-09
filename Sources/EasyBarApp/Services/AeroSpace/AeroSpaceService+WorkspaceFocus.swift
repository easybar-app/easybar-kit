import EasyBarShared
import Foundation

// MARK: - Workspace Focus Ownership

extension AeroSpaceService {
  /// Reserves ownership for one optimistic workspace-focus mutation.
  func reserveWorkspaceFocus() -> (
    token: AeroSpaceWorkspaceFocusToken,
    replacedTask: Task<Void, Never>?
  )? {
    withLock { state in
      guard state.acceptsWork else { return nil }

      state.workspaceFocusRequestID &+= 1
      let token = AeroSpaceWorkspaceFocusToken(
        generation: state.generation,
        requestID: state.workspaceFocusRequestID
      )
      let replacedTask = state.workspaceFocusTask
      state.pendingWorkspaceFocusToken = token
      state.workspaceFocusTask = nil
      return (token, replacedTask)
    }
  }

  /// Restores the previous published focus only while the failed command still owns it.
  @MainActor
  func rollbackWorkspaceFocus(
    _ previousSpaces: [SpaceItem],
    workspace: String,
    token: AeroSpaceWorkspaceFocusToken
  ) {
    guard shouldExecute(workspaceFocusToken: token) else { return }

    replaceSpaces(previousSpaces)
    notifyConsumers()
    logger.warn(
      "failed to focus AeroSpace workspace; restored previous focus",
      .field("workspace", workspace)
    )
  }

  /// Clears focus-task ownership only when the completed task is still current.
  func finishWorkspaceFocus(_ token: AeroSpaceWorkspaceFocusToken) {
    withLock { state in
      guard state.pendingWorkspaceFocusToken == token else { return }
      state.pendingWorkspaceFocusToken = nil
      state.workspaceFocusTask = nil
    }
  }

  /// Returns whether one workspace-focus command still owns the optimistic state.
  func shouldExecute(workspaceFocusToken token: AeroSpaceWorkspaceFocusToken) -> Bool {
    withLock { state in
      state.acceptsWork
        && state.generation == token.generation
        && state.pendingWorkspaceFocusToken == token
    }
  }

  /// Notifies the active native consumers about a main-actor state mutation.
  @MainActor
  func notifyConsumers() {
    for callback in withLock({ Array($0.consumers.values) }) {
      callback()
    }
  }
}
