import Foundation

extension IPC {
  /// One point-in-time metrics payload streamed by EasyBar.
  public struct MetricsSnapshot: Codable, Sendable {
    /// The timestamp for this metrics snapshot.
    public let timestamp: Date
    /// Whether the collection enabled option is enabled for this metrics snapshot.
    public let collectionEnabled: Bool
    /// The sample interval seconds for this metrics snapshot.
    public let sampleIntervalSeconds: Double
    /// The process for this metrics snapshot.
    public let process: ProcessMetrics
    /// The Lua for this metrics snapshot.
    public let lua: ProcessMetrics
    /// The runtime for this metrics snapshot.
    public let runtime: RuntimeMetrics
    /// The agents for this metrics snapshot.
    public let agents: [AgentMetrics]
    /// The widgets for this metrics snapshot.
    public let widgets: [WidgetMetrics]
    /// The events for this metrics snapshot.
    public let events: [CounterMetrics]

    /// Creates one metrics snapshot.
    public init(
      timestamp: Date,
      collectionEnabled: Bool,
      sampleIntervalSeconds: Double,
      process: ProcessMetrics,
      lua: ProcessMetrics,
      runtime: RuntimeMetrics,
      agents: [AgentMetrics],
      widgets: [WidgetMetrics],
      events: [CounterMetrics]
    ) {
      self.timestamp = timestamp
      self.collectionEnabled = collectionEnabled
      self.sampleIntervalSeconds = sampleIntervalSeconds
      self.process = process
      self.lua = lua
      self.runtime = runtime
      self.agents = agents
      self.widgets = widgets
      self.events = events
    }
  }

  /// One sampled process state.
  public struct ProcessMetrics: Codable, Sendable {
    /// The name for this process metrics.
    public let name: String
    /// Whether this process metrics is running.
    public let running: Bool
    /// The pid for this process metrics.
    public let pid: Int32?
    /// The CPU percent for this process metrics.
    public let cpuPercent: Double?
    /// The resident size bytes for this process metrics.
    public let residentSizeBytes: UInt64?
    /// The thread count for this process metrics.
    public let threadCount: Int?

    /// Creates one process metrics payload.
    public init(
      name: String,
      running: Bool,
      pid: Int32? = nil,
      cpuPercent: Double? = nil,
      residentSizeBytes: UInt64? = nil,
      threadCount: Int? = nil
    ) {
      self.name = name
      self.running = running
      self.pid = pid
      self.cpuPercent = cpuPercent
      self.residentSizeBytes = residentSizeBytes
      self.threadCount = threadCount
    }
  }

  /// One aggregated runtime metrics payload.
  public struct RuntimeMetrics: Codable, Sendable {
    /// The subscriber count for this runtime metrics.
    public let subscriberCount: Int
    /// The Lua restart count for this runtime metrics.
    public let luaRestartCount: Int
    /// Whether the Lua ready option is enabled for this runtime metrics.
    public let luaReady: Bool
    /// The subscribed event count for this runtime metrics.
    public let subscribedEventCount: Int
    /// Sorted global Lua event subscriptions.
    public let subscribedEvents: [String]
    /// The total events for this runtime metrics.
    public let totalEvents: Int
    /// The app events for this runtime metrics.
    public let appEvents: Int
    /// The widget events for this runtime metrics.
    public let widgetEvents: Int
    /// The events per second for this runtime metrics.
    public let eventsPerSecond: Double
    /// The dropped events for this runtime metrics.
    public let droppedEvents: Int
    /// The dropped events per second for this runtime metrics.
    public let droppedEventsPerSecond: Double
    /// The coalesced events for this runtime metrics.
    public let coalescedEvents: Int
    /// The coalesced events per second for this runtime metrics.
    public let coalescedEventsPerSecond: Double
    /// The transport lines for this runtime metrics.
    public let transportLines: Int
    /// The Lua writes for this runtime metrics.
    public let luaWrites: Int
    /// Structured Lua log lines.
    public let luaLogLines: Int
    /// Structured Lua warning lines.
    public let luaWarningLines: Int
    /// Structured Lua error lines.
    public let luaErrorLines: Int
    /// Unstructured Lua stderr lines.
    public let luaRawStderrLines: Int
    /// The tree updates for this runtime metrics.
    public let treeUpdates: Int
    /// The tree updates per second for this runtime metrics.
    public let treeUpdatesPerSecond: Double
    /// The decode errors for this runtime metrics.
    public let decodeErrors: Int
    /// The Lua runtime input overflows for this runtime metrics.
    public let luaRuntimeInputOverflows: Int
    /// The Lua event queue depth for this runtime metrics.
    public let luaEventQueueDepth: Int
    /// The Lua event queue overflows for this runtime metrics.
    public let luaEventQueueOverflows: Int
    /// The last tree root for this runtime metrics.
    public let lastTreeRoot: String?
    /// The last tree node count for this runtime metrics.
    public let lastTreeNodeCount: Int?
    /// The last tree at for this runtime metrics.
    public let lastTreeAt: Date?

    /// Creates one runtime metrics payload.
    public init(
      subscriberCount: Int,
      luaRestartCount: Int,
      luaReady: Bool,
      subscribedEventCount: Int,
      subscribedEvents: [String],
      totalEvents: Int,
      appEvents: Int,
      widgetEvents: Int,
      eventsPerSecond: Double,
      droppedEvents: Int,
      droppedEventsPerSecond: Double,
      coalescedEvents: Int,
      coalescedEventsPerSecond: Double,
      transportLines: Int,
      luaWrites: Int,
      luaLogLines: Int,
      luaWarningLines: Int,
      luaErrorLines: Int,
      luaRawStderrLines: Int,
      treeUpdates: Int,
      treeUpdatesPerSecond: Double,
      decodeErrors: Int,
      luaRuntimeInputOverflows: Int,
      luaEventQueueDepth: Int,
      luaEventQueueOverflows: Int,
      lastTreeRoot: String?,
      lastTreeNodeCount: Int?,
      lastTreeAt: Date?
    ) {
      self.subscriberCount = subscriberCount
      self.luaRestartCount = luaRestartCount
      self.luaReady = luaReady
      self.subscribedEventCount = subscribedEventCount
      self.subscribedEvents = subscribedEvents
      self.totalEvents = totalEvents
      self.appEvents = appEvents
      self.widgetEvents = widgetEvents
      self.eventsPerSecond = eventsPerSecond
      self.droppedEvents = droppedEvents
      self.droppedEventsPerSecond = droppedEventsPerSecond
      self.coalescedEvents = coalescedEvents
      self.coalescedEventsPerSecond = coalescedEventsPerSecond
      self.transportLines = transportLines
      self.luaWrites = luaWrites
      self.luaLogLines = luaLogLines
      self.luaWarningLines = luaWarningLines
      self.luaErrorLines = luaErrorLines
      self.luaRawStderrLines = luaRawStderrLines
      self.treeUpdates = treeUpdates
      self.treeUpdatesPerSecond = treeUpdatesPerSecond
      self.decodeErrors = decodeErrors
      self.luaRuntimeInputOverflows = luaRuntimeInputOverflows
      self.luaEventQueueDepth = luaEventQueueDepth
      self.luaEventQueueOverflows = luaEventQueueOverflows
      self.lastTreeRoot = lastTreeRoot
      self.lastTreeNodeCount = lastTreeNodeCount
      self.lastTreeAt = lastTreeAt
    }
  }

  /// One aggregated helper-agent metrics payload.
  public struct AgentMetrics: Codable, Sendable {
    /// The name for this agent metrics.
    public let name: String
    /// Whether this agent metrics is connected.
    public let connected: Bool
    /// The process for this agent metrics.
    public let process: ProcessMetrics
    /// The messages total for this agent metrics.
    public let messagesTotal: Int
    /// The messages per second for this agent metrics.
    public let messagesPerSecond: Double
    /// The reconnects total for this agent metrics.
    public let reconnectsTotal: Int
    /// The refreshes total for this agent metrics.
    public let refreshesTotal: Int
    /// The decode errors total for this agent metrics.
    public let decodeErrorsTotal: Int
    /// The last message at for this agent metrics.
    public let lastMessageAt: Date?
    /// The last disconnect at for this agent metrics.
    public let lastDisconnectAt: Date?

    /// Creates one agent metrics payload.
    public init(
      name: String,
      connected: Bool,
      process: ProcessMetrics,
      messagesTotal: Int,
      messagesPerSecond: Double,
      reconnectsTotal: Int,
      refreshesTotal: Int,
      decodeErrorsTotal: Int,
      lastMessageAt: Date?,
      lastDisconnectAt: Date?
    ) {
      self.name = name
      self.connected = connected
      self.process = process
      self.messagesTotal = messagesTotal
      self.messagesPerSecond = messagesPerSecond
      self.reconnectsTotal = reconnectsTotal
      self.refreshesTotal = refreshesTotal
      self.decodeErrorsTotal = decodeErrorsTotal
      self.lastMessageAt = lastMessageAt
      self.lastDisconnectAt = lastDisconnectAt
    }
  }

  /// One widget update counter in the metrics payload.
  public struct WidgetMetrics: Codable, Sendable {
    /// The stable identifier for this widget metrics.
    public let id: String
    /// The updates total for this widget metrics.
    public let updatesTotal: Int
    /// The updates per second for this widget metrics.
    public let updatesPerSecond: Double
    /// The last node count for this widget metrics.
    public let lastNodeCount: Int
    /// The last updated at for this widget metrics.
    public let lastUpdatedAt: Date?

    /// Creates one widget metrics payload.
    public init(
      id: String,
      updatesTotal: Int,
      updatesPerSecond: Double,
      lastNodeCount: Int,
      lastUpdatedAt: Date?
    ) {
      self.id = id
      self.updatesTotal = updatesTotal
      self.updatesPerSecond = updatesPerSecond
      self.lastNodeCount = lastNodeCount
      self.lastUpdatedAt = lastUpdatedAt
    }
  }

  /// One named counter with total and current per-second rate.
  public struct CounterMetrics: Codable, Sendable {
    /// The name for this counter metrics.
    public let name: String
    /// The total for this counter metrics.
    public let total: Int
    /// The per second for this counter metrics.
    public let perSecond: Double
    /// The dropped total for this counter metrics.
    public let droppedTotal: Int
    /// The dropped per second for this counter metrics.
    public let droppedPerSecond: Double
    /// The coalesced total for this counter metrics.
    public let coalescedTotal: Int
    /// The coalesced per second for this counter metrics.
    public let coalescedPerSecond: Double

    /// Creates one counter metrics payload.
    public init(
      name: String,
      total: Int,
      perSecond: Double,
      droppedTotal: Int = 0,
      droppedPerSecond: Double = 0,
      coalescedTotal: Int = 0,
      coalescedPerSecond: Double = 0
    ) {
      self.name = name
      self.total = total
      self.perSecond = perSecond
      self.droppedTotal = droppedTotal
      self.droppedPerSecond = droppedPerSecond
      self.coalescedTotal = coalescedTotal
      self.coalescedPerSecond = coalescedPerSecond
    }
  }
}
