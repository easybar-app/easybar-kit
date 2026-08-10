import EasyBarShared
import Foundation

/// Shared lifecycle and message handling for calendar-agent stream clients.
///
/// Concrete wrappers only provide the request builder and snapshot sink.
final class CalendarAgentStreamController: @unchecked Sendable {
  private struct LifecycleState {
    var started = false
    var socketPath: String
    var request: CalendarAgentRequest
    var permanentlyRejectedRequest: CalendarAgentRequest?
    var nextRequestSequence: UInt64 = 0
    var pendingRequests: [String: CalendarAgentRequest] = [:]
  }

  private struct ConnectionInputUpdate {
    let blockedByPermanentError: Bool
    let resumedAfterRequestChange: Bool
  }

  /// Human-readable stream label used in logs.
  private let label: String
  /// Returns the current socket path.
  private let socketPath: () -> String
  /// Builds the current subscribe or refresh request.
  private let makeRequest: () -> CalendarAgentRequest
  /// Applies decoded snapshots to the caller state.
  private let applySnapshot: @MainActor @Sendable (EasyBarShared.CalendarAgentSnapshot) -> Void
  /// Clears caller state after errors or disconnects.
  private let clearState: @MainActor @Sendable () -> Void
  /// Metrics key used for this stream.
  private let metricsAgent: MetricsCoordinator.AgentKey
  /// Metrics recorder for agent lifecycle and messages.
  private let metricsCoordinator: MetricsCoordinator
  private let eventRelay: CalendarAgentEventRelay
  /// Wake-triggered refresh controller.
  private let wakeRefreshController: AgentWakeRefreshController
  /// Logger used for stream diagnostics.
  private let logger: ProcessLogger

  /// Cached stream state consumed by background socket work.
  private let lifecycleState: LockedState<LifecycleState>

  /// Socket client that owns the calendar-agent stream.
  private lazy var client: AgentSocketClient<CalendarAgentRequest, CalendarAgentMessage> = {
    let metricCallbacks = AgentSocketMetricCallbacks.recording(
      metricsAgent,
      coordinator: metricsCoordinator
    )

    return AgentSocketClient(
      label: label,
      socketPath: { [weak self] in self?.currentSocketPath() ?? "" },
      subscribeRequest: { [weak self] in
        self?.nextCorrelatedRequest() ?? CalendarAgentRequest(command: .ping)
      },
      handleMessage: { [weak self] message, connectionID in
        self?.handle(message, connectionID: connectionID)
      },
      clearState: { [weak self] connectionID in
        self?.handleDisconnectedStateReset(connectionID: connectionID)
      },
      onConnected: metricCallbacks.onConnected,
      onDisconnected: metricCallbacks.onDisconnected,
      onDecodedMessage: metricCallbacks.onDecodedMessage,
      onDecodeError: metricCallbacks.onDecodeError,
      logger: logger.child("socket_client")
    )
  }()

  /// Creates one shared calendar-agent stream controller.
  init(
    label: String,
    metricsAgent: MetricsCoordinator.AgentKey = .calendar,
    socketPath: @escaping () -> String,
    makeRequest: @escaping () -> CalendarAgentRequest,
    applySnapshot: @escaping @MainActor @Sendable (EasyBarShared.CalendarAgentSnapshot) -> Void,
    clearState: @escaping @MainActor @Sendable () -> Void = {},
    metricsCoordinator: MetricsCoordinator = .shared,
    eventRelay: CalendarAgentEventRelay,
    logger: ProcessLogger
  ) {
    self.label = label
    self.metricsAgent = metricsAgent
    self.metricsCoordinator = metricsCoordinator
    self.eventRelay = eventRelay
    self.socketPath = socketPath
    self.makeRequest = makeRequest
    self.applySnapshot = applySnapshot
    self.clearState = clearState
    self.logger = logger
    self.lifecycleState = LockedState(
      LifecycleState(
        socketPath: socketPath(),
        request: CalendarAgentRequest(command: .ping),
        permanentlyRejectedRequest: nil
      )
    )

    wakeRefreshController = AgentWakeRefreshController(
      label: label,
      eventHub: eventRelay.eventHub,
      logger: logger.child("wake_refresh")
    )
  }

  /// Returns whether the stream lifecycle is active.
  var isStarted: Bool {
    return lifecycleState.withLock { $0.started }
  }

  /// Returns whether the stream currently has an active connection.
  var isConnected: Bool {
    return isStarted && client.isConnected
  }

  /// Starts the stream when the calendar agent is enabled.
  func start(enabled: Bool) {
    guard !isStarted else { return }

    guard enabled else {
      logger.debug("\(label) start skipped because agent is disabled")
      return
    }

    _ = updateCachedConnectionInputs(started: true, resetPermanentError: true)

    wakeRefreshController.start { [weak self] in
      guard let self, self.isStarted else { return }
      self.refresh()
    }

    logger.debug(
      "starting \(label)",
      .field("socket", socketPath()),
    )
    client.start()
  }

  /// Stops the stream and clears published state.
  func stop() {
    let shouldStop = lifecycleState.withLock { state -> Bool in
      guard state.started else { return false }
      state.started = false
      return true
    }

    guard shouldStop else { return }

    logger.debug("stopping \(label)")

    wakeRefreshController.stop()
    client.stop()
    let clearState = clearState
    Task { @MainActor in
      clearState()
    }
  }

  /// Restarts the stream against the latest config-derived request and socket path.
  func restart(enabled: Bool) {
    stop()
    start(enabled: enabled)
  }

  /// Applies configuration lifecycle changes and returns whether only a refresh is needed.
  func configurationDidChange(
    previousEnabled: Bool,
    previousSocketPath: String,
    enabled: Bool,
    socketPath: String
  ) -> Bool {
    guard isStarted else { return false }
    guard previousEnabled == enabled, previousSocketPath == socketPath else {
      restart(enabled: enabled)
      return false
    }
    return true
  }

  /// Sends one fresh request and returns whether it was dispatched.
  @discardableResult
  func refresh() -> Bool {
    guard isStarted else { return false }

    let inputUpdate = updateCachedConnectionInputs(started: true)
    guard !inputUpdate.blockedByPermanentError else {
      logger.debug("\(label) refresh skipped for permanently rejected request")
      return false
    }

    if inputUpdate.resumedAfterRequestChange {
      logger.debug("\(label) request changed; resuming calendar-agent connection")
      client.resumeReconnect()
    }

    Task {
      await metricsCoordinator.recordAgentRefresh(metricsAgent)
    }
    client.refresh()
    return true
  }

  /// Handles one decoded calendar-agent response.
  private func handle(_ response: CalendarAgentMessage, connectionID: UInt64) {
    guard isCurrentConnection(connectionID) else { return }

    switch response.kind {
    case .snapshot:
      guard shouldApplySnapshot(response) else {
        logger.debug(
          "\(label) ignored stale or uncorrelated snapshot",
          .field("request_id", response.requestID ?? "none")
        )
        return
      }

      guard let snapshot = response.snapshot else {
        logger.warn("\(label) received snapshot without payload")
        return
      }

      logger.debug(
        "\(label) applied snapshot",
        .field("permission_state", snapshot.permissionState),
        .field("access_granted", snapshot.accessGranted),
        .field("events", snapshot.events.count),
        .field("sections", snapshot.sections.count),
      )

      Task { @MainActor [weak self] in
        guard let self else { return }
        guard self.isCurrentConnection(connectionID) else {
          return
        }

        self.applySnapshot(snapshot)
        self.eventRelay.noteSnapshotUpdate()
      }

    case .error:
      if response.errorCode == .invalidRequest {
        let resolution = resolveErrorRequest(response)
        guard resolution.matchesCurrentRequest else {
          logger.debug(
            "\(label) ignored stale permanent rejection",
            .field("request_id", response.requestID ?? "none")
          )
          return
        }

        client.suspendReconnect()

        if resolution.shouldLog {
          logger.warn(
            "\(label) request permanently rejected",
            .field("code", response.errorCode?.rawValue ?? "unknown"),
            .field("message", response.message ?? "unknown"),
            .field("request_id", response.requestID ?? "none")
          )
        }
        return
      }

      guard resolveErrorRequest(response).matchesCurrentRequest else {
        logger.debug(
          "\(label) ignored stale error response",
          .field("request_id", response.requestID ?? "none")
        )
        return
      }

      logger.warn(
        "\(label) received error",
        .field("code", response.errorCode?.rawValue ?? "unknown"),
        .field("message", response.message ?? "unknown"),
      )
      Task { @MainActor [weak self] in
        guard let self else { return }
        guard self.isCurrentConnection(connectionID) else {
          return
        }
        self.clearState()
      }

    case .version:
      break

    case .pong, .subscribed, .logSubscribed, .logRecord, .restarting, .created, .updated,
      .deleted:
      break
    }
  }

  /// Clears published state only for disconnects that occur while the stream is active.
  private func handleDisconnectedStateReset(connectionID: UInt64) {
    guard isCurrentConnection(connectionID) else { return }
    let retainsLastSnapshot = lifecycleState.withLock { state in
      state.pendingRequests.removeAll()
      return state.permanentlyRejectedRequest == state.request
    }
    guard !retainsLastSnapshot else { return }

    Task { @MainActor [weak self] in
      guard let self else { return }
      guard self.isCurrentConnection(connectionID) else {
        return
      }
      self.clearState()
    }
  }

  /// Returns whether a callback belongs to the active stream connection.
  private func isCurrentConnection(_ connectionID: UInt64) -> Bool {
    isStarted && client.isCurrentConnectionGeneration(connectionID)
  }

  /// Refreshes the cached request and socket path used by background socket work.
  private func updateCachedConnectionInputs(
    started: Bool,
    resetPermanentError: Bool = false
  ) -> ConnectionInputUpdate {
    let socketPath = socketPath()
    let request = makeRequest()

    return lifecycleState.withLock { state in
      let requestChanged = state.socketPath != socketPath || state.request != request
      let wasPermanentlyRejected = state.permanentlyRejectedRequest != nil
      let shouldResetPermanentError = resetPermanentError || requestChanged

      if shouldResetPermanentError {
        state.permanentlyRejectedRequest = nil
      }
      if resetPermanentError {
        state.pendingRequests.removeAll()
      }

      state.started = started
      state.socketPath = socketPath
      state.request = request

      return ConnectionInputUpdate(
        blockedByPermanentError: state.permanentlyRejectedRequest == request,
        resumedAfterRequestChange: wasPermanentlyRejected && state.permanentlyRejectedRequest == nil
      )
    }
  }

  /// Returns the latest socket path prepared on the stream owner thread.
  private func currentSocketPath() -> String {
    lifecycleState.withLock { $0.socketPath }
  }

  /// Builds one uniquely correlated copy of the latest subscription request.
  private func nextCorrelatedRequest() -> CalendarAgentRequest {
    lifecycleState.withLock { state in
      state.nextRequestSequence &+= 1
      let requestID = String(state.nextRequestSequence)
      let baseRequest = state.request
      state.pendingRequests[requestID] = baseRequest
      return baseRequest.correlated(requestID: requestID)
    }
  }

  /// Returns whether one snapshot belongs to the latest requested subscription.
  private func shouldApplySnapshot(_ response: CalendarAgentMessage) -> Bool {
    lifecycleState.withLock { state in
      guard let requestID = response.requestID else { return false }
      guard let request = takePendingRequest(requestID: requestID, state: &state) else { return false }
      return request == state.request
    }
  }

  /// Removes one pending request by identifier.
  private func takePendingRequest(
    requestID: String,
    state: inout LifecycleState
  ) -> CalendarAgentRequest? {
    guard let request = state.pendingRequests.removeValue(forKey: requestID) else {
      return nil
    }
    return request
  }

  /// Resolves one error to the exact request that produced it.
  private func resolveErrorRequest(
    _ response: CalendarAgentMessage
  ) -> (matchesCurrentRequest: Bool, shouldLog: Bool) {
    lifecycleState.withLock { state in
      guard let requestID = response.requestID else { return (false, false) }
      guard let rejectedRequest = takePendingRequest(requestID: requestID, state: &state) else {
        return (false, false)
      }

      let matchesCurrentRequest = rejectedRequest == state.request
      guard matchesCurrentRequest else { return (false, false) }

      let shouldLog = state.permanentlyRejectedRequest != rejectedRequest
      if response.errorCode == .invalidRequest {
        state.permanentlyRejectedRequest = rejectedRequest
      }
      return (true, shouldLog)
    }
  }
}
