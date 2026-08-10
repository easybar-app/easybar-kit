import EasyBarShared
import Foundation

extension MetricsCoordinator {
  /// Computes a per-second rate from cumulative counters.
  func rate(current: Int, previous: Int?, context: RateContext) -> Double {
    guard context.collectionEnabled, let previous, context.interval > 0 else { return 0 }
    return Double(max(0, current - previous)) / context.interval
  }

  /// Collects one metrics snapshot and updates rate baselines when enabled.
  func collectSnapshot(collectionEnabled: Bool) -> IPC.MetricsSnapshot {
    let now = Date()
    let snapshotState = state

    let previousSampleAt = snapshotState.lastSampleAt
    let interval = previousSampleAt.map { now.timeIntervalSince($0) } ?? sampleIntervalSeconds
    let safeInterval = interval > 0 ? interval : sampleIntervalSeconds
    let rateContext = RateContext(
      baseline: snapshotState.previousCounters,
      interval: safeInterval,
      collectionEnabled: collectionEnabled
    )
    let processSamples = sampleProcesses(from: snapshotState, now: now)
    let currentCounters = sampleCounters(from: snapshotState)

    let snapshot = IPC.MetricsSnapshot(
      timestamp: now,
      collectionEnabled: collectionEnabled,
      sampleIntervalSeconds: sampleIntervalSeconds,
      process: processSamples.app,
      lua: processSamples.lua,
      runtime: runtimeMetrics(from: snapshotState, rateContext: rateContext),
      agents: agentMetrics(
        from: snapshotState,
        processSamples: processSamples,
        rateContext: rateContext
      ),
      widgets: widgetMetrics(from: snapshotState, rateContext: rateContext),
      events: eventMetrics(from: snapshotState, rateContext: rateContext)
    )

    if collectionEnabled {
      state.previousCounters = currentCounters
      state.lastSampleAt = now
    }

    return snapshot
  }

  /// Samples EasyBar, Lua, and helper agent processes.
  func sampleProcesses(from snapshotState: State, now: Date) -> ProcessSamples {
    return ProcessSamples(
      app: processSampler.sampleCurrentProcess(named: "EasyBar", now: now),
      lua: processSampler.sampleProcess(named: "lua", pid: snapshotState.luaPID, now: now),
      calendar: processSampler.sampleProcessNamed(
        named: AgentKey.calendar.processName,
        executableName: AgentKey.calendar.processName,
        now: now
      ),
      network: processSampler.sampleProcessNamed(
        named: AgentKey.network.processName,
        executableName: AgentKey.network.processName,
        now: now
      )
    )
  }

  /// Captures cumulative counters for the next streaming-rate baseline.
  func sampleCounters(from snapshotState: State) -> SampleCounters {
    return SampleCounters(
      totalEvents: snapshotState.totalEvents,
      droppedEvents: snapshotState.droppedEvents,
      coalescedEvents: snapshotState.coalescedEvents,
      treeUpdates: snapshotState.treeUpdates,
      agentMessages: AgentKey.allCases.reduce(into: [:]) { result, key in
        result[key] = snapshotState.agents[key]?.messagesTotal ?? 0
      },
      widgetUpdates: snapshotState.widgetUpdateCounts,
      eventCounts: snapshotState.eventCounts,
      droppedEventCounts: snapshotState.droppedEventCounts,
      coalescedEventCounts: snapshotState.coalescedEventCounts
    )
  }

  /// Builds runtime counters for one snapshot.
  func runtimeMetrics(
    from snapshotState: State,
    rateContext: RateContext
  ) -> IPC.RuntimeMetrics {
    let baseline = rateContext.baseline

    return IPC.RuntimeMetrics(
      subscriberCount: snapshotState.streamingSubscriberFDs.count,
      luaRestartCount: snapshotState.luaRestartCount,
      luaReady: snapshotState.luaReady,
      subscribedEventCount: snapshotState.subscribedEvents.count,
      subscribedEvents: snapshotState.subscribedEvents.sorted(),
      totalEvents: snapshotState.totalEvents,
      appEvents: snapshotState.appEvents,
      widgetEvents: snapshotState.widgetEvents,
      eventsPerSecond: rate(
        current: snapshotState.totalEvents,
        previous: baseline?.totalEvents,
        context: rateContext
      ),
      droppedEvents: snapshotState.droppedEvents,
      droppedEventsPerSecond: rate(
        current: snapshotState.droppedEvents,
        previous: baseline?.droppedEvents,
        context: rateContext
      ),
      coalescedEvents: snapshotState.coalescedEvents,
      coalescedEventsPerSecond: rate(
        current: snapshotState.coalescedEvents,
        previous: baseline?.coalescedEvents,
        context: rateContext
      ),
      transportLines: snapshotState.transportLines,
      luaWrites: snapshotState.luaWrites,
      luaLogLines: snapshotState.luaLogLines,
      luaWarningLines: snapshotState.luaWarningLines,
      luaErrorLines: snapshotState.luaErrorLines,
      luaRawStderrLines: snapshotState.luaRawStderrLines,
      treeUpdates: snapshotState.treeUpdates,
      treeUpdatesPerSecond: rate(
        current: snapshotState.treeUpdates,
        previous: baseline?.treeUpdates,
        context: rateContext
      ),
      decodeErrors: snapshotState.decodeErrors,
      luaRuntimeInputOverflows: snapshotState.luaRuntimeInputOverflows,
      luaEventQueueDepth: snapshotState.luaEventQueueDepth,
      luaEventQueueOverflows: snapshotState.luaEventQueueOverflows,
      lastTreeRoot: snapshotState.lastTreeRoot,
      lastTreeNodeCount: snapshotState.lastTreeNodeCount,
      lastTreeAt: snapshotState.lastTreeAt
    )
  }

  /// Builds helper agent metrics for one snapshot.
  func agentMetrics(
    from snapshotState: State,
    processSamples: ProcessSamples,
    rateContext: RateContext
  ) -> [IPC.AgentMetrics] {
    return AgentKey.allCases.map { key -> IPC.AgentMetrics in
      let agentState = snapshotState.agents[key] ?? AgentState()
      let processMetrics = key == .calendar ? processSamples.calendar : processSamples.network

      return IPC.AgentMetrics(
        name: key.displayName,
        connected: agentState.activeConnections > 0,
        process: processMetrics,
        messagesTotal: agentState.messagesTotal,
        messagesPerSecond: rate(
          current: agentState.messagesTotal,
          previous: rateContext.baseline?.agentMessages[key],
          context: rateContext
        ),
        reconnectsTotal: agentState.reconnectsTotal,
        refreshesTotal: agentState.refreshesTotal,
        decodeErrorsTotal: agentState.decodeErrorsTotal,
        lastMessageAt: agentState.lastMessageAt,
        lastDisconnectAt: agentState.lastDisconnectAt
      )
    }
  }

  /// Builds the highest-volume widget counters for one snapshot.
  func widgetMetrics(
    from snapshotState: State,
    rateContext: RateContext
  ) -> [IPC.WidgetMetrics] {
    let widgets = snapshotState.widgetUpdateCounts
      .map { id, total in
        IPC.WidgetMetrics(
          id: id,
          updatesTotal: total,
          updatesPerSecond: rate(
            current: total,
            previous: rateContext.baseline?.widgetUpdates[id],
            context: rateContext
          ),
          lastNodeCount: snapshotState.widgetNodeCounts[id] ?? 0,
          lastUpdatedAt: snapshotState.widgetLastUpdatedAt[id]
        )
      }
      .sorted { lhs, rhs in
        if lhs.updatesTotal != rhs.updatesTotal {
          return lhs.updatesTotal > rhs.updatesTotal
        }
        return lhs.id < rhs.id
      }
      .prefix(8)

    return Array(widgets)
  }

  /// Builds the highest-volume event counters for one snapshot.
  func eventMetrics(
    from snapshotState: State,
    rateContext: RateContext
  ) -> [IPC.CounterMetrics] {
    let counterNames = Set(snapshotState.eventCounts.keys)
      .union(snapshotState.droppedEventCounts.keys)
      .union(snapshotState.coalescedEventCounts.keys)

    let events =
      counterNames
      .map { name in
        IPC.CounterMetrics(
          name: name,
          total: snapshotState.eventCounts[name] ?? 0,
          perSecond: rate(
            current: snapshotState.eventCounts[name] ?? 0,
            previous: rateContext.baseline?.eventCounts[name],
            context: rateContext
          ),
          droppedTotal: snapshotState.droppedEventCounts[name] ?? 0,
          droppedPerSecond: rate(
            current: snapshotState.droppedEventCounts[name] ?? 0,
            previous: rateContext.baseline?.droppedEventCounts[name],
            context: rateContext
          ),
          coalescedTotal: snapshotState.coalescedEventCounts[name] ?? 0,
          coalescedPerSecond: rate(
            current: snapshotState.coalescedEventCounts[name] ?? 0,
            previous: rateContext.baseline?.coalescedEventCounts[name],
            context: rateContext
          )
        )
      }
      .sorted { lhs, rhs in
        if lhs.total != rhs.total {
          return lhs.total > rhs.total
        }
        return lhs.name < rhs.name
      }
      .prefix(8)

    return Array(events)
  }
}
