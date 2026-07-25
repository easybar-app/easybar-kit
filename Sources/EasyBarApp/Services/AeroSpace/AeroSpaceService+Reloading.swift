import EasyBarShared
import Foundation

// MARK: - State Reloading

extension AeroSpaceService {
  /// Replaces any queued or running refresh with the newest request.
  func queueRefresh(source: String, expectedGeneration: UInt64? = nil) {
    let reservation = withLock {
      state -> (token: AeroSpaceRefreshToken, replacedTask: Task<Void, Never>?)? in
      guard state.running, state.active, !state.consumers.isEmpty else { return nil }
      if let expectedGeneration, state.generation != expectedGeneration {
        return nil
      }

      let token = state.refreshSequence.issue(
        generation: state.generation,
        focusedStateRevision: state.focusedStateRevision
      )
      let replacedTask = state.refreshTask
      state.pendingRefreshToken = token
      state.refreshTask = nil
      return (token, replacedTask)
    }

    guard let reservation else { return }
    reservation.replacedTask?.cancel()

    logger.debug(
      "aerospace refresh queued",
      .field("source", source),
      .field("consumers", consumerCount),
      .field("request_id", reservation.token.requestID)
    )

    let task = Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      await self.reloadState(refreshToken: reservation.token)
    }

    let shouldCancel = withLock { state -> Bool in
      guard state.pendingRefreshToken == reservation.token else { return true }
      state.refreshTask = task
      return false
    }
    if shouldCancel {
      task.cancel()
    }
  }

  /// Reads current AeroSpace state and publishes it, retaining last-known-good state on failure.
  private func reloadState(refreshToken: AeroSpaceRefreshToken) async {
    defer { finishRefresh(refreshToken) }
    guard shouldExecute(refreshToken: refreshToken), !Task.isCancelled else { return }

    logger.debug(
      "aerospace reloadState begin",
      .field("request_id", refreshToken.requestID)
    )

    guard await versionValidationCache.validate(generation: refreshToken.generation) else {
      guard shouldExecute(refreshToken: refreshToken), !Task.isCancelled else { return }
      await publishRefreshFailure(
        message: "AeroSpace version validation failed",
        refreshToken: refreshToken
      )
      scheduleRefreshRetry(generation: refreshToken.generation)
      return
    }

    guard shouldExecute(refreshToken: refreshToken), !Task.isCancelled else { return }

    do {
      let snapshot = try await AeroSpaceSnapshotLoader.load(
        run: { [weak self] arguments in
          guard let self else { return nil }
          return await self.runAeroSpace(arguments: arguments)
        },
        resolveAppID: { name, bundlePath in
          Self.resolvedAppID(name: name, bundlePath: bundlePath)
        }
      )

      guard shouldExecute(refreshToken: refreshToken), !Task.isCancelled else { return }
      refreshRetryScheduler.cancel()
      await publish(snapshot: snapshot, refreshToken: refreshToken)
    } catch is CancellationError {
      return
    } catch {
      guard shouldExecute(refreshToken: refreshToken), !Task.isCancelled else { return }
      logger.error(
        "aerospace JSON snapshot unavailable",
        .field("error", error),
        .field("request_id", refreshToken.requestID)
      )
      await publishRefreshFailure(
        message: String(describing: error),
        refreshToken: refreshToken
      )
      scheduleRefreshRetry(generation: refreshToken.generation)
    }
  }

  /// Publishes one successful snapshot on the main actor.
  private func publish(
    snapshot: AeroSpaceSnapshot,
    refreshToken: AeroSpaceRefreshToken
  ) async {
    await MainActor.run { [weak self] in
      guard let self, self.shouldExecute(refreshToken: refreshToken) else { return }

      let appliesFocusedState = self.shouldApplyFocusedState(from: refreshToken)
      let stateChanged =
        self.spaces != snapshot.spaces
        || (appliesFocusedState
          && (self.focusedApp != snapshot.focusedApp
            || self.focusedLayoutMode != snapshot.focusedLayoutMode))
      let statusChanged = self.snapshotStatus != .current
      self.replaceSnapshotStatus(.current)

      guard stateChanged || statusChanged else {
        self.logger.debug("aerospace reloadState end without changes")
        return
      }

      self.replaceSpaces(snapshot.spaces)
      if appliesFocusedState {
        self.replaceFocusedState(
          app: snapshot.focusedApp,
          layoutMode: snapshot.focusedLayoutMode
        )
      }

      self.logger.debug(
        "aerospace state updated",
        .field("spaces", snapshot.spaces.count),
        .field("focused", snapshot.focusedApp?.name ?? "none"),
        .field("layout", snapshot.focusedLayoutMode.rawValue)
      )

      for callback in self.withLock({ Array($0.consumers.values) }) {
        callback()
      }

      self.logger.debug("aerospace reloadState end with changes")
    }
  }

  /// Marks the snapshot stale or unavailable without clearing published values.
  private func publishRefreshFailure(
    message: String,
    refreshToken: AeroSpaceRefreshToken
  ) async {
    await MainActor.run { [weak self] in
      guard let self, self.shouldExecute(refreshToken: refreshToken) else { return }

      let nextStatus: AeroSpaceSnapshotStatus
      switch self.snapshotStatus {
      case .current, .stale:
        nextStatus = .stale(message: message)
      case .unavailable:
        nextStatus = .unavailable(message: message)
      }

      guard self.snapshotStatus != nextStatus else { return }
      self.replaceSnapshotStatus(nextStatus)
      for callback in self.withLock({ Array($0.consumers.values) }) {
        callback()
      }
    }
  }

  /// Schedules another refresh after a transient validation or snapshot failure.
  private func scheduleRefreshRetry(generation: UInt64) {
    guard shouldExecute(generation: generation) else { return }
    refreshRetryScheduler.schedule { [weak self] in
      self?.queueRefresh(source: "failure retry", expectedGeneration: generation)
    }
  }

  /// Clears task ownership only when the completed task is still current.
  private func finishRefresh(_ refreshToken: AeroSpaceRefreshToken) {
    withLock { state in
      guard state.pendingRefreshToken == refreshToken else { return }
      state.pendingRefreshToken = nil
      state.refreshTask = nil
    }
  }

  /// Prevents an older full snapshot from overwriting a newer fast focus request.
  private func shouldApplyFocusedState(from token: AeroSpaceRefreshToken) -> Bool {
    withLock { $0.focusedStateRevision == token.focusedStateRevision }
  }
}
