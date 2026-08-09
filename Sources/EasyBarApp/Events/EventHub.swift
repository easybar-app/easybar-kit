import EasyBarShared
import Foundation

/// Actor-owned event hub for native widgets and the Lua runtime.
actor EventHub {
  /// Prefix used for Lua interval subscriptions.
  private static let intervalTickPrefix = "interval_tick:"

  /// Injectable metrics operations used by event delivery.
  struct MetricsRecorder: Sendable {
    let recordEmission:
      @Sendable (
        _ name: String,
        _ isWidgetEvent: Bool,
        _ backpressure: [EventBackpressureSample]
      ) async -> Void
    let recordBackpressure: @Sendable (_ samples: [EventBackpressureSample]) async -> Void

    /// Builds the production recorder backed by one metrics coordinator.
    static func live(_ coordinator: MetricsCoordinator) -> MetricsRecorder {
      MetricsRecorder(
        recordEmission: { name, isWidgetEvent, backpressure in
          await coordinator.recordEvent(
            name: name,
            isWidgetEvent: isWidgetEvent,
            backpressure: backpressure
          )
        },
        recordBackpressure: { samples in
          await coordinator.recordEventBackpressure(samples)
        }
      )
    }
  }

  /// Logger used for event diagnostics.
  private let logger: ProcessLogger
  /// Sink that forwards selected events into Lua.
  private let enqueueLuaEvent: @Sendable (EasyBarEventPayload) -> Void
  /// Production sink retained so a new Lua runtime session can reset overflow state.
  private let luaEventSink: LuaEventSink?
  /// Metrics operations kept outside ordering-sensitive actor state.
  private let metricsRecorder: MetricsRecorder
  private let wifiSnapshotProvider: @MainActor @Sendable () -> NetworkAgentSnapshot?

  /// Active stream subscribers keyed by id.
  private var subscribers: [UUID: Subscriber] = [:]
  /// Latest payload cached for each replayable event.
  private var replayablePayloads: [String: EasyBarEventPayload] = [:]
  /// App events currently requested by Lua.
  private var luaForwardedAppEvents = Set<String>()

  /// Subscriber filters and continuation.
  private struct Subscriber {
    /// Optional event-name filter.
    let eventNames: Set<String>?
    /// Optional widget target filter.
    let widgetTargetIDs: Set<String>?
    /// Stream continuation used to deliver payloads.
    let continuation: AsyncStream<EasyBarEventPayload>.Continuation
  }

  /// Dictionary key used while aggregating one synchronous delivery pass.
  private struct BackpressureKey: Hashable, Sendable {
    let name: String
    let coalesced: Bool
  }

  /// Creates one production event hub.
  init(
    logger: ProcessLogger,
    luaRuntime: LuaRuntime,
    metricsCoordinator: MetricsCoordinator,
    wifiSnapshotProvider: @escaping @MainActor @Sendable () -> NetworkAgentSnapshot?
  ) {
    let sink = LuaEventSink(
      runtime: luaRuntime,
      logger: logger.child("lua_sink"),
      metricsCoordinator: metricsCoordinator
    )
    self.init(
      logger: logger,
      enqueueLuaEvent: { payload in sink.enqueue(payload) },
      luaEventSink: sink,
      metricsCoordinator: metricsCoordinator,
      wifiSnapshotProvider: wifiSnapshotProvider
    )
  }

  /// Creates one event hub with an injected sink.
  init(
    logger: ProcessLogger,
    enqueueLuaEvent: @escaping @Sendable (EasyBarEventPayload) -> Void,
    luaEventSink: LuaEventSink? = nil,
    metricsCoordinator: MetricsCoordinator = .shared,
    metricsRecorder: MetricsRecorder? = nil,
    wifiSnapshotProvider: @escaping @MainActor @Sendable () -> NetworkAgentSnapshot? = { nil }
  ) {
    self.logger = logger
    self.enqueueLuaEvent = enqueueLuaEvent
    self.luaEventSink = luaEventSink
    self.metricsRecorder = metricsRecorder ?? .live(metricsCoordinator)
    self.wifiSnapshotProvider = wifiSnapshotProvider
  }

  /// Subscribes to a filtered subset of the app-wide event stream.
  func subscribe(
    eventNames: Set<String>,
    widgetTargetIDs: Set<String>? = nil,
    replayLatest: Bool = false,
    bufferingPolicy: AsyncStream<EasyBarEventPayload>.Continuation.BufferingPolicy? = nil
  ) -> AsyncStream<EasyBarEventPayload> {
    let normalizedEventNames = eventNames.isEmpty ? nil : eventNames
    let resolvedBufferingPolicy =
      bufferingPolicy
      ?? EventDeliveryPolicy.defaultBufferingPolicy(for: eventNames)

    return makeSubscription(
      eventNames: normalizedEventNames,
      widgetTargetIDs: widgetTargetIDs,
      replayLatest: replayLatest,
      bufferingPolicy: resolvedBufferingPolicy
    )
  }

  /// Subscribes to every event with an explicit mixed-stream buffering contract.
  func subscribeAll(
    widgetTargetIDs: Set<String>? = nil,
    replayLatest: Bool = false,
    bufferingPolicy: AsyncStream<EasyBarEventPayload>.Continuation.BufferingPolicy
  ) -> AsyncStream<EasyBarEventPayload> {
    makeSubscription(
      eventNames: nil,
      widgetTargetIDs: widgetTargetIDs,
      replayLatest: replayLatest,
      bufferingPolicy: bufferingPolicy
    )
  }

  /// Emits one app-wide event.
  func emit(_ event: AppEvent, source: String? = nil) async {
    await emit(.app(event, source: source))
  }

  /// Emits one widget-scoped interaction event.
  func emitWidgetEvent(
    _ event: WidgetEvent,
    widgetID: String,
    targetWidgetID: String? = nil,
    source: String? = nil,
    button: MouseButton? = nil,
    direction: ScrollDirection? = nil,
    value: Double? = nil,
    deltaX: Double? = nil,
    deltaY: Double? = nil,
    actionID: String? = nil
  ) async {
    await emit(
      .widget(
        event,
        widgetID: widgetID,
        targetWidgetID: targetWidgetID,
        source: source,
        button: button,
        direction: direction,
        value: value,
        deltaX: deltaX,
        deltaY: deltaY,
        actionID: actionID
      )
    )
  }

  /// Emits one fully constructed payload.
  func emit(_ payload: EasyBarEventPayload) async {
    // Complete every ordering-sensitive hub mutation and delivery before the first suspension.
    // Metrics live on a separate actor and may allow another emission to enter this actor.
    if EventReplayCatalog.isReplayable(payload.eventName) {
      replayablePayloads[payload.eventName] = payload
    }

    var backpressureCounts: [BackpressureKey: Int] = [:]
    var terminatedSubscriberIDs = Set<UUID>()
    var overflowedSubscriberIDs = Set<UUID>()

    for (subscriberID, subscriber) in subscribers {
      guard shouldDeliver(payload, to: subscriber) else { continue }

      switch subscriber.continuation.yield(payload) {
      case .enqueued:
        break
      case .dropped(let droppedPayload):
        recordBackpressure(for: droppedPayload, in: &backpressureCounts)
        if EventDeliveryPolicy.forEventName(droppedPayload.eventName) == .mustDeliver {
          overflowedSubscriberIDs.insert(subscriberID)
        }
      case .terminated:
        terminatedSubscriberIDs.insert(subscriberID)
      @unknown default:
        break
      }
    }

    for subscriberID in overflowedSubscriberIDs {
      subscribers[subscriberID]?.continuation.finish()
    }
    for subscriberID in terminatedSubscriberIDs.union(overflowedSubscriberIDs) {
      subscribers.removeValue(forKey: subscriberID)
    }

    let backpressure = backpressureSamples(from: backpressureCounts)
    let mustDeliverDropCount = backpressure.reduce(into: 0) { count, sample in
      if !sample.coalesced {
        count += sample.count
      }
    }

    if mustDeliverDropCount > 0 {
      logger.error(
        "subscriber buffer overflow terminated stalled subscribers",
        .field("trigger", payload.eventName),
        .field("dropped_events", mustDeliverDropCount),
        .field("terminated_subscribers", overflowedSubscriberIDs.count)
      )
    }

    logEmission(payload)

    if shouldForwardPayloadToLua(payload) {
      enqueueLuaEvent(payload)
    }

    await metricsRecorder.recordEmission(
      payload.eventName,
      payload.widgetEvent != nil,
      backpressure
    )
  }

  /// Replaces the set of app-level events that may be forwarded into Lua.
  func setLuaForwardedAppEvents(_ eventNames: Set<String>) {
    luaForwardedAppEvents = eventNames
  }

  /// Clears all app-level event forwarding for the Lua runtime.
  func clearLuaForwardedAppEvents() {
    luaForwardedAppEvents.removeAll()
  }

  /// Resets Lua queue state before one new runtime process session begins.
  func resetLuaEventSink() {
    luaEventSink?.reset()
  }

  /// Emits the latest replayable state for the requested event names.
  func emitReplayableState(for eventNames: Set<String>) async {
    let payloads = await EventReplayCatalog.payloads(
      for: eventNames,
      wifiSnapshotProvider: wifiSnapshotProvider
    )

    for payload in payloads {
      await emit(payload)
    }
  }

  /// Creates one stream and synchronously seeds requested replay state.
  private func makeSubscription(
    eventNames: Set<String>?,
    widgetTargetIDs: Set<String>?,
    replayLatest: Bool,
    bufferingPolicy: AsyncStream<EasyBarEventPayload>.Continuation.BufferingPolicy
  ) -> AsyncStream<EasyBarEventPayload> {
    let id = UUID()
    let normalizedWidgetTargetIDs = widgetTargetIDs?.isEmpty == true ? nil : widgetTargetIDs
    let (stream, continuation) = AsyncStream<EasyBarEventPayload>.makeStream(
      bufferingPolicy: bufferingPolicy
    )

    continuation.onTermination = { [weak self] _ in
      Task {
        await self?.removeContinuation(id: id)
      }
    }

    subscribers[id] = Subscriber(
      eventNames: eventNames,
      widgetTargetIDs: normalizedWidgetTargetIDs,
      continuation: continuation
    )

    guard replayLatest else { return stream }

    var replayBackpressure: [BackpressureKey: Int] = [:]
    var terminated = false
    var mustDeliverOverflow = false

    for event in EventReplayCatalog.orderedEvents {
      let eventName = event.rawValue
      if let eventNames, !eventNames.contains(eventName) {
        continue
      }

      guard let payload = replayablePayloads[eventName] else { continue }

      switch continuation.yield(payload) {
      case .enqueued:
        break
      case .dropped(let droppedPayload):
        recordBackpressure(for: droppedPayload, in: &replayBackpressure)
        mustDeliverOverflow =
          EventDeliveryPolicy.forEventName(droppedPayload.eventName) == .mustDeliver
      case .terminated:
        terminated = true
      @unknown default:
        break
      }

      let replayEnded = terminated || mustDeliverOverflow
      if replayEnded {
        break
      }
    }

    if mustDeliverOverflow {
      continuation.finish()
    }
    let replayEnded = terminated || mustDeliverOverflow
    if replayEnded {
      subscribers.removeValue(forKey: id)
    }

    reportReplayBackpressure(backpressureSamples(from: replayBackpressure))
    return stream
  }

  /// Reports replay overflow outside the event-hub actor without hiding it.
  private func reportReplayBackpressure(_ samples: [EventBackpressureSample]) {
    guard !samples.isEmpty else { return }

    let metricsRecorder = metricsRecorder
    let logger = logger

    Task {
      for sample in samples {
        logger.warn(
          "replay subscriber buffer overflowed",
          .field("name", sample.name),
          .field("count", sample.count)
        )
      }
      await metricsRecorder.recordBackpressure(samples)
    }
  }

  /// Counts the payload actually displaced by one bounded AsyncStream buffer.
  private func recordBackpressure(
    for payload: EasyBarEventPayload,
    in counts: inout [BackpressureKey: Int]
  ) {
    let key = BackpressureKey(
      name: payload.eventName,
      coalesced: EventDeliveryPolicy.forEventName(payload.eventName) == .coalescing
    )
    counts[key, default: 0] += 1
  }

  /// Converts one delivery-pass counter map into stable metrics samples.
  private func backpressureSamples(
    from counts: [BackpressureKey: Int]
  ) -> [EventBackpressureSample] {
    counts
      .map { key, count in
        EventBackpressureSample(
          name: key.name,
          count: count,
          coalesced: key.coalesced
        )
      }
      .sorted { lhs, rhs in
        if lhs.name != rhs.name {
          return lhs.name < rhs.name
        }
        return !lhs.coalesced && rhs.coalesced
      }
  }

  /// Removes one terminated subscription.
  private func removeContinuation(id: UUID) {
    subscribers.removeValue(forKey: id)
  }

  /// Returns whether one payload matches one subscriber filter.
  private func shouldDeliver(_ payload: EasyBarEventPayload, to subscriber: Subscriber) -> Bool {
    if let eventNames = subscriber.eventNames, !eventNames.contains(payload.eventName) {
      return false
    }

    guard EventDeliveryPolicy.routesDirectlyToWidgets(payload.eventName) else {
      return true
    }

    guard let widgetTargetIDs = subscriber.widgetTargetIDs else {
      return true
    }

    let widgetIDs = [payload.widgetID, payload.targetWidgetID].compactMap { $0 }
    return widgetIDs.contains { widgetTargetIDs.contains($0) }
  }

  /// Returns whether one payload should be forwarded into the Lua runtime.
  private func shouldForwardPayloadToLua(_ payload: EasyBarEventPayload) -> Bool {
    if payload.widgetEvent != nil {
      return true
    }

    guard let appEvent = payload.appEvent else {
      return false
    }

    if appEvent == .manualRefresh {
      return luaForwardedAppEvents.contains(EventCatalog.forcedEventName)
    }

    if appEvent == .intervalTick {
      return luaForwardedAppEvents.contains { $0.hasPrefix(Self.intervalTickPrefix) }
    }

    return luaForwardedAppEvents.contains(appEvent.rawValue)
  }

  /// Logs one emitted payload for verbose debugging.
  private func logEmission(_ payload: EasyBarEventPayload) {
    guard !payload.eventName.isEmpty else { return }

    logger.trace(
      "event emitted",
      .field("name", payload.eventName),
      .field("source", payload.source ?? payload.widgetID ?? "system")
    )
  }
}
