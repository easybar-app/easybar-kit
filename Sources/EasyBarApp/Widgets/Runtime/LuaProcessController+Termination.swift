import Darwin
import EasyBarShared

/// Grace period between terminate and forced kill.
private let easyBarLuaTerminationGracePeriod: Duration = .milliseconds(150)

extension LuaProcessController {
  /// Terminates the Lua runtime process tree and schedules one forced kill fallback.
  func terminateProcess(processIdentifier: Int32, processGroupIdentifier: Int32?) {
    let processIsRunning = ProcessSignalSupport.isRunning(processIdentifier: processIdentifier)
    let groupIsRunning =
      processGroupIdentifier.map {
        ProcessSignalSupport.isRunning(processGroupIdentifier: $0)
      } ?? false
    guard processIsRunning || groupIsRunning else { return }

    cancelForcedKillWorkItem()

    logger.debug(
      "sending SIGTERM to lua process tree",
      .field("pgid", processGroupIdentifier),
      .field("pid", processIdentifier)
    )
    logSignalFailure(
      ProcessSignalSupport.send(
        SIGTERM,
        processIdentifier: processIdentifier,
        processGroupIdentifier: processGroupIdentifier
      ),
      signal: SIGTERM,
      processIdentifier: processIdentifier,
      processGroupIdentifier: processGroupIdentifier
    )

    let task = DetachedTask.run(priority: .utility) { [weak self] in
      do {
        try await Task.sleep(for: easyBarLuaTerminationGracePeriod)
      } catch {
        return
      }

      guard let self else { return }
      let processIsRunning = ProcessSignalSupport.isRunning(
        processIdentifier: processIdentifier
      )
      let groupIsRunning =
        processGroupIdentifier.map {
          ProcessSignalSupport.isRunning(processGroupIdentifier: $0)
        } ?? false
      guard processIsRunning || groupIsRunning else { return }

      self.logger.warn(
        "forcing lua process tree shutdown",
        .field("pgid", processGroupIdentifier),
        .field("pid", processIdentifier)
      )
      self.logSignalFailure(
        ProcessSignalSupport.send(
          SIGKILL,
          processIdentifier: processIdentifier,
          processGroupIdentifier: processGroupIdentifier
        ),
        signal: SIGKILL,
        processIdentifier: processIdentifier,
        processGroupIdentifier: processGroupIdentifier
      )
    }

    let installed = state.withLock { state -> Bool in
      guard case .running(let trackedProcessIdentifier, _, _) = state.lifecycle,
        trackedProcessIdentifier == processIdentifier
      else {
        return false
      }
      state.forcedKillTask = task
      return true
    }

    if !installed {
      task.cancel()
    }
  }

  /// Cancels the pending forced kill work item when present.
  func cancelForcedKillWorkItem() {
    let task = state.withLock { state -> Task<Void, Never>? in
      let task = state.forcedKillTask
      state.forcedKillTask = nil
      return task
    }
    task?.cancel()
  }

  /// Logs checked signal failures while ignoring an already-absent process tree.
  private func logSignalFailure(
    _ delivery: ProcessSignalDelivery,
    signal: Int32,
    processIdentifier: Int32,
    processGroupIdentifier: Int32?
  ) {
    guard !delivery.delivered, !delivery.targetWasMissing else { return }
    logger.warn(
      "failed to signal lua process tree",
      .field("pid", processIdentifier),
      .field("pgid", processGroupIdentifier),
      .field("signal", signal),
      .field("group_errno", delivery.processGroupError),
      .field("process_errno", delivery.processError)
    )
  }
}
