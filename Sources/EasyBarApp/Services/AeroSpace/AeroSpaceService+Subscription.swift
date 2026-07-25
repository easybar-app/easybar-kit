import EasyBarShared
import Foundation

// MARK: - AeroSpace Event Subscription

extension AeroSpaceService {
  /// Handles one JSON-line event received from `aerospace subscribe`.
  func handleAeroSpaceSubscriptionEvent(_ event: AeroSpaceSubscriptionEvent) {
    let source = "aerospace subscribe \(event.name)"
    switch event.refreshPolicy {
    case .fastFocusAndDebouncedSnapshot:
      queueFocusedStateRefresh(source: source)
      scheduleDebouncedSnapshot(source: source)
    case .fastWorkspaceAndImmediateSnapshot:
      if let workspace = event.workspace {
        Task { @MainActor [weak self] in
          self?.publishFocusedWorkspace(workspace, source: source)
        }
      }
      subscriptionRefreshScheduler.cancel()
      triggerRefresh(source: source)
    case .immediateSnapshot:
      subscriptionRefreshScheduler.cancel()
      triggerRefresh(source: source)
    case .debouncedSnapshot:
      scheduleDebouncedSnapshot(source: source)
    }

    guard let appEvent = event.appEvent else { return }

    Task {
      await eventHub.emit(appEvent, source: source)
    }
  }

  /// Applies the workspace carried by a post-change event before canonical reload completes.
  @MainActor
  private func publishFocusedWorkspace(_ workspace: String, source: String) {
    guard spaces.contains(where: { $0.name == workspace }) else { return }
    guard spaces.first(where: { $0.isFocused })?.name != workspace else { return }

    replaceSpaces(
      spaces.map { space in
        SpaceItem(
          id: space.id,
          name: space.name,
          isFocused: space.name == workspace,
          isVisible: space.isVisible,
          apps: space.apps
        )
      })
    notifyConsumers()
    logger.debug(
      "aerospace focused workspace updated from event",
      .field("source", source),
      .field("workspace", workspace)
    )
  }

  /// Schedules one trailing complete snapshot after a burst of subscription events.
  private func scheduleDebouncedSnapshot(source: String) {
    let generation = currentGeneration()
    let delayNanoseconds = AeroSpaceSubscriptionEvent.fullSnapshotDebounceNanoseconds
    subscriptionRefreshScheduler.schedule { [weak self] in
      guard let self else { return }
      guard self.shouldExecute(generation: generation) else { return }
      self.triggerRefresh(source: source)
    }

    logger.debug(
      "aerospace subscription refresh scheduled",
      .field("source", source),
      .field("delay_ms", Int(delayNanoseconds / 1_000_000))
    )
  }
}

// MARK: - Focused State Reloading

extension AeroSpaceService {
  /// Replaces only the focused-window query, leaving complete snapshots independent.
  private func queueFocusedStateRefresh(source: String) {
    let reservation = withLock {
      state -> (token: AeroSpaceFocusedStateToken, replacedTask: Task<Void, Never>?)? in
      guard state.running, state.active, !state.consumers.isEmpty else { return nil }

      state.focusedStateRevision &+= 1
      let token = AeroSpaceFocusedStateToken(
        generation: state.generation,
        requestID: state.focusedStateRevision
      )
      let replacedTask = state.focusedStateTask
      state.pendingFocusedStateToken = token
      state.focusedStateTask = nil
      return (token, replacedTask)
    }

    guard let reservation else { return }
    reservation.replacedTask?.cancel()

    logger.debug(
      "aerospace focused state refresh queued",
      .field("source", source),
      .field("request_id", reservation.token.requestID)
    )

    let task = Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      defer { self.finishFocusedStateRefresh(reservation.token) }
      guard self.shouldExecute(focusedStateToken: reservation.token) else { return }

      do {
        let focusedState = try await AeroSpaceSnapshotLoader.loadFocusedState(
          run: { [weak self] arguments in
            guard let self else { return nil }
            return await self.runAeroSpace(arguments: arguments)
          },
          resolveAppID: { name, bundlePath in
            Self.resolvedAppID(name: name, bundlePath: bundlePath)
          }
        )
        await self.publishFocusedState(focusedState, token: reservation.token)
      } catch is CancellationError {
        return
      } catch {
        guard self.shouldExecute(focusedStateToken: reservation.token) else { return }
        self.logger.debug(
          "aerospace focused state refresh failed",
          .field("source", source),
          .field("error", error)
        )
      }
    }

    let shouldCancel = withLock { state -> Bool in
      guard state.pendingFocusedStateToken == reservation.token else { return true }
      state.focusedStateTask = task
      return false
    }
    if shouldCancel {
      task.cancel()
    }
  }

  @MainActor
  private func publishFocusedState(
    _ focusedState: AeroSpaceFocusedState,
    token: AeroSpaceFocusedStateToken
  ) {
    guard shouldExecute(focusedStateToken: token) else { return }
    guard focusedApp != focusedState.app || focusedLayoutMode != focusedState.layoutMode else {
      return
    }

    replaceFocusedState(
      app: focusedState.app,
      layoutMode: focusedState.layoutMode
    )
    notifyConsumers()
    logger.debug(
      "aerospace focused state updated",
      .field("focused", focusedState.app?.name ?? "none"),
      .field("layout", focusedState.layoutMode.rawValue)
    )
  }

  private func finishFocusedStateRefresh(_ token: AeroSpaceFocusedStateToken) {
    withLock { state in
      guard state.pendingFocusedStateToken == token else { return }
      state.pendingFocusedStateToken = nil
      state.focusedStateTask = nil
    }
  }

  private func shouldExecute(focusedStateToken token: AeroSpaceFocusedStateToken) -> Bool {
    withLock { state in
      state.running
        && state.active
        && !state.consumers.isEmpty
        && state.generation == token.generation
        && state.pendingFocusedStateToken == token
    }
  }
}
