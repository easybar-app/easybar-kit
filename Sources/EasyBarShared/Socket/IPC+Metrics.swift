import Foundation

extension IPC {
  /// One point-in-time metrics payload streamed by EasyBar.
  public struct MetricsSnapshot: Codable, Sendable {
    public let timestamp: Date
    public let collectionEnabled: Bool
    public let sampleIntervalSeconds: Double
    public let process: ProcessMetrics
    public let lua: ProcessMetrics
    public let runtime: RuntimeMetrics
    public let agents: [AgentMetrics]
    public let widgets: [WidgetMetrics]
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
    public let name: String
    public let running: Bool
    public let pid: Int32?
    public let cpuPercent: Double?
    public let residentSizeBytes: UInt64?
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
    public let subscriberCount: Int
    public let luaRestartCount: Int
    public let luaReady: Bool
    public let subscribedEventCount: Int
    /// Sorted global Lua event subscriptions.
    public let subscribedEvents: [String]
    public let totalEvents: Int
    public let appEvents: Int
    public let widgetEvents: Int
    public let eventsPerSecond: Double
    public let droppedEvents: Int
    public let droppedEventsPerSecond: Double
    public let coalescedEvents: Int
    public let coalescedEventsPerSecond: Double
    public let transportLines: Int
    public let luaWrites: Int
    /// Structured Lua log lines.
    public let luaLogLines: Int
    /// Structured Lua warning lines.
    public let luaWarningLines: Int
    /// Structured Lua error lines.
    public let luaErrorLines: Int
    /// Unstructured Lua stderr lines.
    public let luaRawStderrLines: Int
    public let treeUpdates: Int
    public let treeUpdatesPerSecond: Double
    public let decodeErrors: Int
    public let luaRuntimeInputOverflows: Int
    public let luaEventQueueDepth: Int
    public let luaEventQueueOverflows: Int
    public let lastTreeRoot: String?
    public let lastTreeNodeCount: Int?
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
    public let name: String
    public let connected: Bool
    public let process: ProcessMetrics
    public let messagesTotal: Int
    public let messagesPerSecond: Double
    public let reconnectsTotal: Int
    public let refreshesTotal: Int
    public let decodeErrorsTotal: Int
    public let lastMessageAt: Date?
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
    public let id: String
    public let updatesTotal: Int
    public let updatesPerSecond: Double
    public let lastNodeCount: Int
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
    public let name: String
    public let total: Int
    public let perSecond: Double
    public let droppedTotal: Int
    public let droppedPerSecond: Double
    public let coalescedTotal: Int
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
