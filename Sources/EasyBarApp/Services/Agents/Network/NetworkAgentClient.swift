import EasyBarShared
import Foundation

/// Streams Wi-Fi and network state from the network agent.
final class NetworkAgentClient: @unchecked Sendable {
  private struct ErrorLogKey: Equatable {
    let code: String
  }

  private struct ErrorLogState {
    var lastKey: ErrorLogKey?
    var repeatCount = 0
  }

  private struct LifecycleState {
    var config: ConfigSnapshot.NetworkAgent
    var started = false
    var publicationID: UInt64 = 0
  }

  /// Shared network-agent client.
  /// Logger used for network-agent diagnostics.
  private let logger: ProcessLogger
  /// Metrics recorder for network-agent lifecycle and messages.
  private let metricsCoordinator: MetricsCoordinator
  private let nativeWiFiStore: NativeWiFiStore
  private let eventHub: EventHub
  /// Active network-agent lifecycle state.
  private let lifecycleState: LockedState<LifecycleState>
  /// Last logged network-agent error, used to suppress identical repeats.
  private let errorLogState = LockedState(ErrorLogState())
  /// Publishes network-agent snapshots to app stores and events.
  private lazy var snapshotPublisher = NetworkAgentSnapshotPublisher(
    store: nativeWiFiStore,
    eventHub: eventHub,
    isCurrent: { [weak self] publicationID in
      self?.isPublicationCurrent(publicationID) ?? false
    }
  )

  /// Wake-triggered refresh controller.
  private lazy var wakeRefreshController = AgentWakeRefreshController(
    label: "network agent client",
    eventHub: eventHub,
    logger: logger.child("wake_refresh")
  )

  /// Socket client that owns the network-agent stream.
  private lazy var client: AgentSocketClient<NetworkAgentRequest, NetworkAgentMessage> = {
    let metricCallbacks = AgentSocketMetricCallbacks.recording(
      .network,
      coordinator: metricsCoordinator
    )

    return AgentSocketClient(
      label: "network agent client",
      socketPath: { [weak self] in self?.currentConfig().socketPath ?? "" },
      subscribeRequest: {
        NetworkAgentRequest(command: .subscribe, fields: NetworkAgentSnapshot.snapshotFieldSet)
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

  /// Creates the shared network-agent client.
  init(
    logger: ProcessLogger,
    config: ConfigSnapshot.NetworkAgent,
    nativeWiFiStore: NativeWiFiStore,
    eventHub: EventHub,
    metricsCoordinator: MetricsCoordinator = .shared
  ) {
    self.logger = logger
    self.lifecycleState = LockedState(LifecycleState(config: config))
    self.nativeWiFiStore = nativeWiFiStore
    self.eventHub = eventHub
    self.metricsCoordinator = metricsCoordinator
  }

  /// Returns whether the client currently has an open socket.
  var isConnected: Bool {
    return client.isConnected
  }

  /// Replaces the active network-agent config snapshot.
  func updateConfiguration(_ config: ConfigSnapshot.NetworkAgent) {
    let change = lifecycleState.withLock {
      state -> (
        shouldRestart: Bool,
        enabled: Bool,
        publicationID: UInt64?
      ) in
      let socketPathChanged = state.config.socketPath != config.socketPath
      let enabledChanged = state.config.enabled != config.enabled
      let shouldRestart = state.started && (socketPathChanged || enabledChanged)
      state.config = config

      guard shouldRestart else { return (false, config.enabled, nil) }
      state.publicationID &+= 1
      return (true, config.enabled, state.publicationID)
    }

    guard change.shouldRestart else { return }

    logger.debug(
      "network agent config changed; restarting client",
      .field("socket", config.socketPath),
      .field("enabled", config.enabled)
    )

    client.stop()

    if let publicationID = change.publicationID {
      snapshotPublisher.clear(notify: true, publicationID: publicationID)
    }

    guard change.enabled else {
      lifecycleState.withLock { $0.started = false }
      wakeRefreshController.stop()
      return
    }

    client.start()
  }

  /// Starts the network agent client.
  func start() {
    let config = lifecycleState.withLock { state -> ConfigSnapshot.NetworkAgent? in
      guard !state.started else { return nil }
      return state.config
    }

    guard let config else { return }
    guard config.enabled else {
      logger.debug("network agent client start skipped because agent is disabled")
      let publicationID = issuePublicationID()
      snapshotPublisher.clear(notify: false, publicationID: publicationID)
      return
    }

    lifecycleState.withLock { state in
      state.started = true
      state.publicationID &+= 1
    }

    wakeRefreshController.start { [weak self] in
      guard let self, self.isStarted else { return }
      self.refresh()
    }

    client.start()
  }

  /// Stops the network agent client.
  func stop() {
    let publicationID = lifecycleState.withLock { state -> UInt64? in
      guard state.started else { return nil }
      state.started = false
      state.publicationID &+= 1
      return state.publicationID
    }

    guard let publicationID else { return }

    wakeRefreshController.stop()
    client.stop()
    snapshotPublisher.clear(notify: false, publicationID: publicationID)
  }

  /// Requests one fresh network-agent update using the current subscription.
  func refresh() {
    guard isStarted else { return }

    logger.debug("network agent client manual refresh")

    Task {
      await metricsCoordinator.recordAgentRefresh(.network)
    }
    client.refresh()
  }

  /// Handles one decoded network agent message.
  private func handle(_ message: NetworkAgentMessage, connectionID: UInt64) {
    guard isStarted, client.isCurrentConnectionGeneration(connectionID) else { return }

    switch message.kind {
    case .version:
      break

    case .subscribed:
      logger.debug("network agent client subscribed")

    case .fields:
      let permissionDeniedFields =
        message.fieldStatuses?.compactMap { key, status in
          status == .permissionDenied ? key : nil
        } ?? []
      if !permissionDeniedFields.isEmpty {
        logger.debug(
          "network agent omitted permission-protected fields",
          .field("fields", permissionDeniedFields.sorted())
        )
      }

      guard let fields = message.fields else {
        logger.warn("network agent returned fields message without payload")
        return
      }

      guard let snapshot = NetworkAgentSnapshot(fields: fields) else {
        logger.warn("network agent returned incomplete field set")
        return
      }

      resetErrorLogState()
      let publicationID = issuePublicationID()
      snapshotPublisher.publish(snapshot: snapshot, publicationID: publicationID)

    case .pong, .logSubscribed, .logRecord, .restarting:
      break

    case .error:
      handleError(code: message.errorCode, connectionID: connectionID)
    }
  }

  /// Handles one network-agent error message.
  private func handleError(code: NetworkAgentErrorCode?, connectionID: UInt64) {
    guard isStarted, client.isCurrentConnectionGeneration(connectionID) else { return }

    logAgentErrorIfNeeded(code: code)

    guard code == .permissionDenied else { return }

    let publicationID = issuePublicationID()
    snapshotPublisher.publish(
      snapshot: NetworkAgentSnapshot(
        accessGranted: false,
        permissionState: "denied",
        generatedAt: Date(),
        ssid: nil,
        ipv4Address: nil,
        ipv6Address: nil,
        bssid: nil,
        interfaceName: nil,
        hardwareAddress: nil,
        power: nil,
        serviceActive: nil,
        primaryInterfaceIsTunnel: false,
        rssi: nil,
        noise: nil,
        snr: nil,
        linkQuality: nil,
        txRate: nil,
        channel: nil,
        channelBand: nil,
        channelWidth: nil,
        security: nil,
        phyMode: nil,
        interfaceMode: nil,
        countryCode: nil,
        roaming: nil,
        ssidChangedAt: nil,
        interfaceChangedAt: nil
      ),
      publicationID: publicationID
    )
  }

  /// Handles a socket disconnect by clearing published state.
  private func handleDisconnectedStateReset(connectionID: UInt64) {
    guard isStarted, client.isCurrentConnectionGeneration(connectionID) else { return }
    resetErrorLogState()
    let publicationID = issuePublicationID()
    snapshotPublisher.clear(notify: true, publicationID: publicationID)
  }

  /// Logs the first instance of an agent error, then suppresses identical repeats.
  private func logAgentErrorIfNeeded(code: NetworkAgentErrorCode?) {
    let key = ErrorLogKey(code: code?.rawValue ?? "unknown")
    let decision = errorLogState.withLock { state -> (shouldLog: Bool, repeatCount: Int) in
      guard state.lastKey == key else {
        state.lastKey = key
        state.repeatCount = 0
        return (true, 0)
      }

      state.repeatCount += 1
      return (state.repeatCount % 25 == 0, state.repeatCount)
    }

    guard decision.shouldLog else { return }

    if decision.repeatCount > 0 {
      logger.warn(
        "network agent error",
        .field("code", key.code),
        .field("repeat_count", decision.repeatCount),
      )
      return
    }

    logger.warn(
      "network agent error",
      .field("code", key.code),
    )
  }

  /// Allows the next network-agent error after a successful update to be logged.
  private func resetErrorLogState() {
    errorLogState.withLock { state in
      state.lastKey = nil
      state.repeatCount = 0
    }
  }

  /// Issues a new publication id that invalidates older queued store updates.
  private func issuePublicationID() -> UInt64 {
    lifecycleState.withLock { state in
      state.publicationID &+= 1
      return state.publicationID
    }
  }

  /// Returns whether a queued store update is still the newest publication.
  private func isPublicationCurrent(_ publicationID: UInt64) -> Bool {
    lifecycleState.withLock { $0.publicationID == publicationID }
  }

  /// Returns the current network-agent configuration.
  private func currentConfig() -> ConfigSnapshot.NetworkAgent {
    lifecycleState.withLock { $0.config }
  }

  /// Returns whether the network-agent client lifecycle is active.
  private var isStarted: Bool {
    lifecycleState.withLock { $0.started }
  }
}
