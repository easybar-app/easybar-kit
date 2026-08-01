import EasyBarShared
import Foundation

/// Collects lightweight runtime metrics and streams coalesced snapshots on demand.
actor MetricsCoordinator {
  /// Callback invoked for streamed snapshots.
  typealias SnapshotHandler = (IPC.MetricsSnapshot) -> Void

  /// Helper agent tracked by metrics.
  enum AgentKey: String, CaseIterable {
    case calendar
    case network

    /// Name shown in metrics output.
    var displayName: String {
      switch self {
      case .calendar:
        return "calendar"
      case .network:
        return "network"
      }
    }

    /// Bundle identifier for the helper app.
    var bundleIdentifier: String {
      switch self {
      case .calendar:
        return "com.gi8lino.EasyBarCalendarAgent"
      case .network:
        return "com.gi8lino.EasyBarNetworkAgent"
      }
    }

    /// Process name used for sampling.
    var processName: String {
      switch self {
      case .calendar:
        return "EasyBarCalendarAgent"
      case .network:
        return "EasyBarNetworkAgent"
      }
    }
  }

  /// Mutable counters for one helper agent.
  struct AgentState {
    /// Number of active socket connections.
    var activeConnections = 0
    /// Whether the agent has connected at least once.
    var everConnected = false
    /// Total decoded messages.
    var messagesTotal = 0
    /// Total reconnects after the first connection.
    var reconnectsTotal = 0
    /// Total refresh requests.
    var refreshesTotal = 0
    /// Total decode failures.
    var decodeErrorsTotal = 0
    /// Timestamp of the last decoded message.
    var lastMessageAt: Date?
    /// Timestamp of the last disconnect.
    var lastDisconnectAt: Date?

    /// Records a new active connection and counts reconnects after the first connection.
    mutating func recordConnection() {
      if activeConnections == 0 && everConnected {
        reconnectsTotal += 1
      }

      activeConnections += 1
      everConnected = true
    }

    /// Records one closed connection without allowing the active count to go negative.
    mutating func recordDisconnect(at date: Date) {
      activeConnections = max(0, activeConnections - 1)
      lastDisconnectAt = date
    }
  }

  /// Counter snapshot used to compute rates.
  struct SampleCounters {
    var totalEvents: Int
    var droppedEvents: Int
    var coalescedEvents: Int
    var treeUpdates: Int
    var agentMessages: [AgentKey: Int]
    var widgetUpdates: [String: Int]
    var eventCounts: [String: Int]
    var droppedEventCounts: [String: Int]
    var coalescedEventCounts: [String: Int]
  }

  /// Inputs needed to compute per-second rates.
  struct RateContext {
    let baseline: SampleCounters?
    let interval: TimeInterval
    let collectionEnabled: Bool
  }

  /// Process samples included in one metrics snapshot.
  struct ProcessSamples {
    let app: IPC.ProcessMetrics
    let lua: IPC.ProcessMetrics
    let calendar: IPC.ProcessMetrics
    let network: IPC.ProcessMetrics
  }

  /// Actor-isolated mutable metrics state.
  struct State {
    var streamingSubscriberFDs = Set<Int32>()
    var luaPID: Int32?
    var hasSeenLuaStart = false
    var luaRestartCount = 0
    var luaReady = false
    var subscribedEvents = Set<String>()

    var totalEvents = 0
    var appEvents = 0
    var widgetEvents = 0
    var eventCounts: [String: Int] = [:]
    var droppedEvents = 0
    var coalescedEvents = 0
    var droppedEventCounts: [String: Int] = [:]
    var coalescedEventCounts: [String: Int] = [:]

    var transportLines = 0
    var luaWrites = 0
    var luaLogLines = 0
    var luaWarningLines = 0
    var luaErrorLines = 0
    var luaRawStderrLines = 0
    var decodeErrors = 0
    var luaRuntimeInputOverflows = 0
    var luaEventQueueDepth = 0
    var luaEventQueueOverflows = 0

    var treeUpdates = 0
    var lastTreeRoot: String?
    var lastTreeNodeCount: Int?
    var lastTreeAt: Date?
    var widgetUpdateCounts: [String: Int] = [:]
    var widgetNodeCounts: [String: Int] = [:]
    var widgetLastUpdatedAt: [String: Date] = [:]

    var agents: [AgentKey: AgentState] = Dictionary(
      uniqueKeysWithValues: AgentKey.allCases.map { ($0, AgentState()) })

    var previousCounters: SampleCounters?
    var lastSampleAt: Date?

    /// Returns whether at least one metrics stream subscriber is active.
    var hasStreamingSubscribers: Bool {
      !streamingSubscriberFDs.isEmpty
    }

    /// Adds one stream subscriber and returns whether sampling should start.
    mutating func addStreamingSubscriber(fd: Int32) -> Bool {
      let wasEmpty = streamingSubscriberFDs.isEmpty
      let inserted = streamingSubscriberFDs.insert(fd).inserted
      return inserted && wasEmpty
    }

    /// Removes one stream subscriber and returns whether sampling should stop.
    mutating func removeStreamingSubscriber(fd: Int32) -> Bool {
      guard streamingSubscriberFDs.remove(fd) != nil else {
        return false
      }

      return streamingSubscriberFDs.isEmpty
    }

    /// Removes all stream subscribers.
    mutating func removeAllStreamingSubscribers() {
      streamingSubscriberFDs.removeAll()
    }
  }

  /// Shared process-wide metrics coordinator.
  static let shared = MetricsCoordinator()

  /// Metrics sampling interval.
  let sampleIntervalSeconds: TimeInterval = 1
  /// Metrics sampling interval.
  private let sampleInterval: Duration = .seconds(1)
  /// Process sampler for EasyBar, Lua, and agents.
  let processSampler = ProcessSampler()

  /// Current actor-isolated metrics state.
  var state = State()
  /// Periodic streaming task.
  private var streamingTask: Task<Void, Never>?
  /// Callback invoked for streamed snapshots.
  private var onSnapshot: SnapshotHandler?

  init() {}

  /// Returns whether metrics streaming is currently active.
  var isStreamingActive: Bool {
    return state.hasStreamingSubscribers
  }

  /// Installs the callback invoked for streamed snapshots.
  func setSnapshotHandler(_ handler: SnapshotHandler?) {
    onSnapshot = handler
  }

  /// Starts streaming collection for one subscriber.
  func addStreamingSubscriber(fd: Int32) {
    if state.addStreamingSubscriber(fd: fd) {
      startStreamingTask()
    }
  }

  /// Stops streaming collection for one subscriber.
  func removeStreamingSubscriber(fd: Int32) {
    if state.removeStreamingSubscriber(fd: fd) {
      stopStreamingTask()
    }
  }

  /// Stops all streaming subscribers and sampling.
  func resetStreaming() {
    state.removeAllStreamingSubscribers()
    stopStreamingTask()
  }

  /// Builds one point-in-time snapshot.
  func snapshot() -> IPC.MetricsSnapshot {
    return collectSnapshot(collectionEnabled: isStreamingActive)
  }

  /// Records one emitted event and any subscriber overflow observed during delivery.
  func recordEvent(
    name: String,
    isWidgetEvent: Bool,
    backpressure: [EventBackpressureSample] = []
  ) {
    state.totalEvents += 1
    if isWidgetEvent {
      state.widgetEvents += 1
    } else {
      state.appEvents += 1
    }
    state.eventCounts[name, default: 0] += 1
    recordEventBackpressure(backpressure)
  }

  /// Records one socket client rejected because the server was at capacity.
  func recordSocketClientRejection() {
    state.eventCounts["socket_client_rejected", default: 0] += 1
  }

  /// Records events dropped or coalesced because subscriber buffers were full.
  func recordEventBackpressure(_ samples: [EventBackpressureSample]) {
    for sample in samples where sample.count > 0 {
      if sample.coalesced {
        state.coalescedEvents += sample.count
        state.coalescedEventCounts[sample.name, default: 0] += sample.count
      } else {
        state.droppedEvents += sample.count
        state.droppedEventCounts[sample.name, default: 0] += sample.count
      }
    }
  }

  /// Records one line written to the Lua transport socket.
  func recordLuaWrite() {
    state.luaWrites += 1
  }

  /// Records one line read from the Lua transport socket.
  func recordLuaTransportLine() {
    state.transportLines += 1
  }

  /// Records one classified line read from the Lua runtime's stderr pipe.
  func recordLuaStderrLine(_ classification: LuaStderrLineClassification) {
    switch classification {
    case .structured(let level):
      state.luaLogLines += 1
      if level == .warn {
        state.luaWarningLines += 1
      } else if level == .error {
        state.luaErrorLines += 1
      }
    case .raw:
      state.luaRawStderrLines += 1
    }
  }

  /// Records one runtime decode failure.
  func recordDecodeError() {
    state.decodeErrors += 1
  }

  /// Records one bounded Lua runtime input queue overflow.
  func recordLuaRuntimeInputOverflow() {
    state.luaRuntimeInputOverflows += 1
  }

  /// Records the current number of event payloads waiting for Lua delivery.
  func recordLuaEventQueueDepth(_ depth: Int) {
    state.luaEventQueueDepth = max(0, depth)
  }

  /// Records one hard must-deliver event queue overflow.
  func recordLuaEventQueueOverflow() {
    state.luaEventQueueOverflows += 1
    state.luaEventQueueDepth = 0
  }

  /// Records the Lua runtime starting with a new PID.
  func recordLuaRuntimeStarted(pid: Int32) {
    if state.hasSeenLuaStart {
      state.luaRestartCount += 1
    }
    state.hasSeenLuaStart = true
    state.luaPID = pid
    state.luaReady = false
  }

  /// Records the Lua runtime stopping.
  func recordLuaRuntimeStopped() {
    let pid = state.luaPID
    state.luaPID = nil
    state.luaReady = false
    state.subscribedEvents.removeAll()

    processSampler.clear(pid: pid)
  }

  /// Records the Lua runtime ready handshake.
  func recordLuaReady() {
    state.luaReady = true
  }

  /// Records the subscribed runtime event set.
  func recordLuaSubscriptions(_ events: Set<String>) {
    state.subscribedEvents = events
  }

  /// Records one widget tree update.
  func recordTreeUpdate(root: String, nodeCount: Int, at date: Date = Date()) {
    state.treeUpdates += 1
    state.lastTreeRoot = root
    state.lastTreeNodeCount = nodeCount
    state.lastTreeAt = date
    state.widgetUpdateCounts[root, default: 0] += 1
    state.widgetNodeCounts[root] = nodeCount
    state.widgetLastUpdatedAt[root] = date
  }

  /// Records one agent connection.
  func recordAgentConnected(_ agent: AgentKey) {
    var agentState = state.agents[agent] ?? AgentState()
    agentState.recordConnection()
    state.agents[agent] = agentState
  }

  /// Records one agent disconnect.
  func recordAgentDisconnected(_ agent: AgentKey, at date: Date = Date()) {
    var agentState = state.agents[agent] ?? AgentState()
    agentState.recordDisconnect(at: date)
    state.agents[agent] = agentState
  }

  /// Records one agent refresh request.
  func recordAgentRefresh(_ agent: AgentKey) {
    var agentState = state.agents[agent] ?? AgentState()
    agentState.refreshesTotal += 1
    state.agents[agent] = agentState
  }

  /// Records one decoded agent message.
  func recordAgentMessage(_ agent: AgentKey, at date: Date = Date()) {
    var agentState = state.agents[agent] ?? AgentState()
    agentState.messagesTotal += 1
    agentState.lastMessageAt = date
    state.agents[agent] = agentState
  }

  /// Records one agent decode failure.
  func recordAgentDecodeError(_ agent: AgentKey) {
    var agentState = state.agents[agent] ?? AgentState()
    agentState.decodeErrorsTotal += 1
    state.agents[agent] = agentState
  }

  /// Starts periodic metrics sampling.
  private func startStreamingTask() {
    guard streamingTask == nil else { return }

    let interval = sampleInterval

    streamingTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: interval)
        } catch {
          break
        }

        guard !Task.isCancelled else { break }
        await self?.collectAndPublishStreamingSnapshot()
      }
    }
  }

  /// Stops periodic metrics sampling.
  private func stopStreamingTask() {
    streamingTask?.cancel()
    streamingTask = nil
    state.previousCounters = nil
    state.lastSampleAt = nil
  }

  /// Collects and publishes one streaming snapshot when subscribers are still active.
  private func collectAndPublishStreamingSnapshot() {
    guard state.hasStreamingSubscribers else {
      stopStreamingTask()
      return
    }

    let snapshot = collectSnapshot(collectionEnabled: true)
    onSnapshot?(snapshot)
  }

}
