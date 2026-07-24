import EasyBarShared
import XCTest

@testable import EasyBarApp

private actor SuspendedEventMetricsGate {
  private var didSuspend = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func recordEmission() async {
    guard !didSuspend else { return }

    didSuspend = true
    let waiters = enteredWaiters
    enteredWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }

    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
  }

  func waitUntilSuspended() async {
    guard !didSuspend else { return }

    await withCheckedContinuation { continuation in
      enteredWaiters.append(continuation)
    }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private actor EventBackpressureCapture {
  struct Sample: Equatable, Sendable {
    let name: String
    let count: Int
    let coalesced: Bool
  }

  private var samples: [Sample] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func record(name: String, count: Int, coalesced: Bool) {
    samples.append(Sample(name: name, count: count, coalesced: coalesced))

    let waiters = waiters
    self.waiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }

  func waitForTotalCount(_ expectedCount: Int) async {
    while samples.reduce(0, { $0 + $1.count }) < expectedCount {
      await withCheckedContinuation { continuation in
        waiters.append(continuation)
      }
    }
  }

  func snapshot() -> [Sample] {
    samples
  }
}

@MainActor
final class EventHubTests: XCTestCase {
  /// Builds an event hub with logging muted and Lua delivery replaced by a no-op sink.
  private static func makeHub(
    metricsRecorder: EventHub.MetricsRecorder? = nil
  ) -> EventHub {
    EventHub(
      logger: ProcessLogger(
        label: "eventhub.test",
        minimumLevel: .error
      ),
      enqueueLuaEvent: { _ in },
      metricsRecorder: metricsRecorder
    )
  }

  /// Verifies that filtered subscription receives matching event only.
  func testFilteredSubscriptionReceivesMatchingEventOnly() async {
    let hub = Self.makeHub()
    let stream = await hub.subscribe(eventNames: [AppEvent.systemWoke.rawValue])
    let task = Task { await Self.next(from: stream) }

    await hub.emit(.minuteTick)
    await hub.emit(.systemWoke)

    let payload = await task.value

    XCTAssertEqual(payload?.eventName, AppEvent.systemWoke.rawValue)
  }

  /// Verifies that unfiltered subscription receives app event.
  func testUnfilteredSubscriptionReceivesAppEvent() async {
    let hub = Self.makeHub()
    let stream = await hub.subscribeAll(bufferingPolicy: .unbounded)
    let task = Task { await Self.next(from: stream) }

    await hub.emit(.minuteTick, source: "test timer")

    let payload = await task.value

    XCTAssertEqual(payload?.eventName, AppEvent.minuteTick.rawValue)
    XCTAssertEqual(payload?.source, "test timer")
    XCTAssertEqual(payload?.luaPayload.source, "test timer")
  }

  /// Verifies that an internal manual refresh reaches Lua through its public forced token.
  func testManualRefreshForwardsToLuaAsForced() async throws {
    let forwardedPayloads = LockedState<[EasyBarEventPayload]>([])
    let hub = EventHub(
      logger: ProcessLogger(
        label: "eventhub.test",
        minimumLevel: .error
      ),
      enqueueLuaEvent: { payload in
        forwardedPayloads.withLock { $0.append(payload) }
      }
    )

    await hub.setLuaForwardedAppEvents([EventCatalog.forcedEventName])
    await hub.emit(.manualRefresh, source: "test refresh")

    let payload = try XCTUnwrap(forwardedPayloads.withLock(\.first))
    XCTAssertEqual(payload.eventName, AppEvent.manualRefresh.rawValue)
    XCTAssertEqual(payload.luaPayload.name, EventCatalog.forcedEventName)
    XCTAssertEqual(payload.luaPayload.source, "test refresh")
  }

  /// Verifies that manual refreshes are not forwarded when Lua did not subscribe to forced.
  func testManualRefreshRequiresForcedLuaSubscription() async {
    let forwardedPayloads = LockedState<[EasyBarEventPayload]>([])
    let hub = EventHub(
      logger: ProcessLogger(
        label: "eventhub.test",
        minimumLevel: .error
      ),
      enqueueLuaEvent: { payload in
        forwardedPayloads.withLock { $0.append(payload) }
      }
    )

    await hub.setLuaForwardedAppEvents([AppEvent.networkChange.rawValue])
    await hub.emit(.manualRefresh)

    XCTAssertTrue(forwardedPayloads.withLock(\.isEmpty))
  }

  /// Verifies that empty event filter behaves like unfiltered subscription.
  func testEmptyEventFilterBehavesLikeUnfilteredSubscription() async {
    let hub = Self.makeHub()
    let stream = await hub.subscribe(eventNames: Set<String>())
    let task = Task { await Self.next(from: stream) }

    await hub.emit(.secondTick)

    let payload = await task.value

    XCTAssertEqual(payload?.eventName, AppEvent.secondTick.rawValue)
  }

  /// Verifies that replay latest replays most recent replayable state.
  func testReplayLatestReplaysMostRecentReplayableState() async {
    let hub = Self.makeHub()

    await hub.emit(.secondTick)

    let stream = await hub.subscribe(
      eventNames: [AppEvent.secondTick.rawValue],
      replayLatest: true
    )

    let payload = await Self.next(from: stream)

    XCTAssertEqual(payload?.eventName, AppEvent.secondTick.rawValue)
  }

  /// Verifies that replay latest uses most recent payload for replayable event.
  func testReplayLatestUsesMostRecentPayloadForReplayableEvent() async {
    let hub = Self.makeHub()

    await hub.emit(.app(.networkChange, primaryInterfaceIsTunnel: false))
    await hub.emit(.app(.networkChange, primaryInterfaceIsTunnel: true))

    let stream = await hub.subscribe(
      eventNames: [AppEvent.networkChange.rawValue],
      replayLatest: true
    )

    let payload = await Self.next(from: stream)

    XCTAssertEqual(payload?.eventName, AppEvent.networkChange.rawValue)
    XCTAssertEqual(payload?.primaryInterfaceIsTunnel, true)
  }

  /// Verifies that replay latest respects event filter.
  func testReplayLatestRespectsEventFilter() async {
    let hub = Self.makeHub()

    await hub.emit(.minuteTick)
    await hub.emit(.secondTick)

    let stream = await hub.subscribe(
      eventNames: [AppEvent.secondTick.rawValue],
      replayLatest: true
    )

    let payload = await Self.next(from: stream)

    XCTAssertEqual(payload?.eventName, AppEvent.secondTick.rawValue)
  }

  /// Verifies that replay latest without event filter replays all cached events in stable order.
  func testReplayLatestWithoutEventFilterReplaysAllCachedEventsInStableOrder() async {
    let hub = Self.makeHub()

    await hub.emit(.secondTick)
    await hub.emit(.app(.networkChange, primaryInterfaceIsTunnel: true))

    let stream = await hub.subscribeAll(
      replayLatest: true,
      bufferingPolicy: .unbounded
    )

    let payloads = await Self.collect(
      from: stream,
      count: 2,
      timeoutNanoseconds: 1_000_000_000
    )

    XCTAssertEqual(
      payloads.map(\.eventName),
      [
        AppEvent.networkChange.rawValue,
        AppEvent.secondTick.rawValue,
      ]
    )
    XCTAssertEqual(payloads.first?.primaryInterfaceIsTunnel, true)
    XCTAssertNil(payloads.last?.primaryInterfaceIsTunnel)
  }

  /// Verifies that suspended metrics cannot reorder concurrent delivery or replay state.
  func testConcurrentEmissionsPreserveOrderWhileMetricsSuspend() async {
    let gate = SuspendedEventMetricsGate()
    let metricsRecorder = EventHub.MetricsRecorder(
      recordEmission: { _, _, _ in
        await gate.recordEmission()
      },
      recordBackpressure: { _ in }
    )
    let hub = Self.makeHub(metricsRecorder: metricsRecorder)
    let stream = await hub.subscribe(eventNames: [AppEvent.networkChange.rawValue])
    let deliveryTask = Task {
      await Self.collect(
        from: stream,
        count: 2,
        timeoutNanoseconds: 1_000_000_000
      )
    }

    let firstEmission = Task {
      await hub.emit(.app(.networkChange, source: "first"))
    }
    await gate.waitUntilSuspended()

    let secondEmission = Task {
      await hub.emit(.app(.networkChange, source: "second"))
    }

    let delivered = await deliveryTask.value
    let replayStream = await hub.subscribe(
      eventNames: [AppEvent.networkChange.rawValue],
      replayLatest: true
    )
    let replayed = await Self.next(from: replayStream)

    XCTAssertEqual(delivered.map(\.source), ["first", "second"])
    XCTAssertEqual(replayed?.source, "second")

    await gate.release()
    await firstEmission.value
    await secondEmission.value
  }

  /// Verifies that replay overflow is surfaced through backpressure metrics.
  func testReplayOverflowRecordsBackpressure() async {
    let capture = EventBackpressureCapture()
    let metricsRecorder = EventHub.MetricsRecorder(
      recordEmission: { _, _, _ in },
      recordBackpressure: { samples in
        for sample in samples {
          await capture.record(
            name: sample.name,
            count: sample.count,
            coalesced: sample.coalesced
          )
        }
      }
    )
    let hub = Self.makeHub(metricsRecorder: metricsRecorder)

    await hub.emit(.app(.networkChange, source: "network"))
    await hub.emit(.secondTick, source: "clock")

    let stream = await hub.subscribeAll(
      replayLatest: true,
      bufferingPolicy: .bufferingNewest(1)
    )

    await capture.waitForTotalCount(1)
    let samples = await capture.snapshot()
    let replayed = await Self.next(from: stream)

    XCTAssertEqual(samples.reduce(0, { $0 + $1.count }), 1)
    XCTAssertEqual(replayed?.eventName, AppEvent.secondTick.rawValue)
  }

  /// Verifies that replay latest does not emit when no cached payload exists.
  func testReplayLatestDoesNotEmitWhenNoCachedPayloadExists() async {
    let hub = Self.makeHub()

    let stream = await hub.subscribe(
      eventNames: [AppEvent.secondTick.rawValue],
      replayLatest: true
    )

    let payload = await Self.next(
      from: stream,
      timeoutNanoseconds: 100_000_000
    )

    XCTAssertNil(payload)
  }

  /// Verifies that replay latest does not replay non replayable widget event.
  func testReplayLatestDoesNotReplayNonReplayableWidgetEvent() async {
    let hub = Self.makeHub()

    await hub.emitWidgetEvent(
      .mouseClicked,
      widgetID: "clock",
      button: .left
    )

    let stream = await hub.subscribe(
      eventNames: [WidgetEvent.mouseClicked.rawValue],
      replayLatest: true
    )

    let payload = await Self.next(
      from: stream,
      timeoutNanoseconds: 100_000_000
    )

    XCTAssertNil(payload)
  }

  /// Verifies that emit replayable state emits requested replayable events in stable order.
  func testEmitReplayableStateEmitsRequestedReplayableEventsInStableOrder() async {
    let hub = Self.makeHub()

    let stream = await hub.subscribe(
      eventNames: [
        AppEvent.minuteTick.rawValue,
        AppEvent.secondTick.rawValue,
      ]
    )

    let task = Task {
      await Self.collect(
        from: stream,
        count: 2,
        timeoutNanoseconds: 1_000_000_000
      )
    }

    await hub.emitReplayableState(
      for: [
        AppEvent.minuteTick.rawValue,
        AppEvent.secondTick.rawValue,
      ]
    )

    let payloads = await task.value

    XCTAssertEqual(
      payloads.map(\.eventName),
      [
        AppEvent.minuteTick.rawValue,
        AppEvent.secondTick.rawValue,
      ]
    )
  }

  /// Verifies that emit replayable state ignores unknown event names.
  func testEmitReplayableStateIgnoresUnknownEventNames() async {
    let hub = Self.makeHub()

    let stream = await hub.subscribe(eventNames: ["unknown_event"])
    let task = Task {
      await Self.next(
        from: stream,
        timeoutNanoseconds: 100_000_000
      )
    }

    await hub.emitReplayableState(for: ["unknown_event"])

    let payload = await task.value

    XCTAssertNil(payload)
  }

  /// Verifies that widget events route only to matching target widget IDs.
  func testWidgetEventsRouteOnlyToMatchingTargetWidgetIDs() async {
    let hub = Self.makeHub()

    let matchingStream = await hub.subscribe(
      eventNames: [WidgetEvent.sliderPreview.rawValue],
      widgetTargetIDs: ["volume_slider"]
    )

    let nonMatchingStream = await hub.subscribe(
      eventNames: [WidgetEvent.sliderPreview.rawValue],
      widgetTargetIDs: ["other_widget"]
    )

    let matchingTask = Task { await Self.next(from: matchingStream) }
    let nonMatchingTask = Task {
      await Self.next(
        from: nonMatchingStream,
        timeoutNanoseconds: 100_000_000
      )
    }

    await hub.emitWidgetEvent(
      .sliderPreview,
      widgetID: "builtin_volume",
      targetWidgetID: "volume_slider",
      value: 0.5
    )

    let matchingPayload = await matchingTask.value
    let nonMatchingPayload = await nonMatchingTask.value

    XCTAssertEqual(matchingPayload?.eventName, WidgetEvent.sliderPreview.rawValue)
    XCTAssertEqual(matchingPayload?.targetWidgetID, "volume_slider")
    XCTAssertEqual(matchingPayload?.value, 0.5)
    XCTAssertNil(nonMatchingPayload)
  }

  /// Verifies that widget events route to matching source widget ID.
  func testWidgetEventsRouteToMatchingSourceWidgetID() async {
    let hub = Self.makeHub()

    let stream = await hub.subscribe(
      eventNames: [WidgetEvent.mouseClicked.rawValue],
      widgetTargetIDs: ["clock"]
    )

    let task = Task { await Self.next(from: stream) }

    await hub.emitWidgetEvent(
      .mouseClicked,
      widgetID: "clock",
      button: .left
    )

    let payload = await task.value

    XCTAssertEqual(payload?.eventName, WidgetEvent.mouseClicked.rawValue)
    XCTAssertEqual(payload?.widgetID, "clock")
    XCTAssertEqual(payload?.button, .left)
  }

  /// Verifies that widget subscription without target filter receives matching widget event.
  func testWidgetSubscriptionWithoutTargetFilterReceivesMatchingWidgetEvent() async {
    let hub = Self.makeHub()

    let stream = await hub.subscribe(
      eventNames: [WidgetEvent.mouseScrolled.rawValue]
    )

    let task = Task { await Self.next(from: stream) }

    await hub.emitWidgetEvent(
      .mouseScrolled,
      widgetID: "calendar",
      direction: .down,
      deltaX: 0,
      deltaY: -8
    )

    let payload = await task.value

    XCTAssertEqual(payload?.eventName, WidgetEvent.mouseScrolled.rawValue)
    XCTAssertEqual(payload?.widgetID, "calendar")
    XCTAssertEqual(payload?.direction, .down)
    XCTAssertEqual(payload?.deltaX, 0)
    XCTAssertEqual(payload?.deltaY, -8)
  }

  /// Verifies that empty widget target filter behaves like unfiltered widget subscription.
  func testEmptyWidgetTargetFilterBehavesLikeUnfilteredWidgetSubscription() async {
    let hub = Self.makeHub()

    let stream = await hub.subscribe(
      eventNames: [WidgetEvent.sliderPreview.rawValue],
      widgetTargetIDs: Set<String>()
    )

    let task = Task { await Self.next(from: stream) }

    await hub.emitWidgetEvent(
      .sliderPreview,
      widgetID: "builtin_volume",
      targetWidgetID: "volume_slider",
      value: 0.5
    )

    let payload = await task.value

    XCTAssertEqual(payload?.eventName, WidgetEvent.sliderPreview.rawValue)
    XCTAssertEqual(payload?.targetWidgetID, "volume_slider")
    XCTAssertEqual(payload?.value, 0.5)
  }

  /// Verifies that widget event filter still requires matching event name.
  func testWidgetEventFilterStillRequiresMatchingEventName() async {
    let hub = Self.makeHub()

    let stream = await hub.subscribe(
      eventNames: [WidgetEvent.sliderChanged.rawValue],
      widgetTargetIDs: ["volume_slider"]
    )

    let task = Task {
      await Self.next(
        from: stream,
        timeoutNanoseconds: 100_000_000
      )
    }

    await hub.emitWidgetEvent(
      .sliderPreview,
      widgetID: "builtin_volume",
      targetWidgetID: "volume_slider",
      value: 0.5
    )

    let payload = await task.value

    XCTAssertNil(payload)
  }

  /// Verifies that app events ignore widget target filter when event name matches.
  func testAppEventsIgnoreWidgetTargetFilterWhenEventNameMatches() async {
    let hub = Self.makeHub()

    let stream = await hub.subscribe(
      eventNames: [AppEvent.systemWoke.rawValue],
      widgetTargetIDs: ["some_widget"]
    )

    let task = Task { await Self.next(from: stream) }

    await hub.emit(.systemWoke)

    let payload = await task.value

    XCTAssertEqual(payload?.eventName, AppEvent.systemWoke.rawValue)
  }

  /// Verifies that app Lua payload includes nested context.
  func testAppLuaPayloadIncludesNestedContext() {
    let payload = EasyBarEventPayload.app(
      .networkChange,
      appName: "Finder",
      interfaceName: "utun4",
      charging: true,
      muted: false,
      primaryInterfaceIsTunnel: true
    )

    let luaPayload = payload.luaPayload

    XCTAssertEqual(luaPayload.name, AppEvent.networkChange.rawValue)
    XCTAssertEqual(luaPayload.appName, "Finder")

    XCTAssertEqual(luaPayload.network?.interfaceName, "utun4")
    XCTAssertEqual(luaPayload.network?.primaryInterfaceIsTunnel, true)

    XCTAssertEqual(luaPayload.power?.charging, true)
    XCTAssertEqual(luaPayload.audio?.muted, false)

    XCTAssertNil(luaPayload.widgetID)
    XCTAssertNil(luaPayload.targetWidgetID)
  }

  /// Verifies that widget Lua payload includes interaction context.
  func testWidgetLuaPayloadIncludesInteractionContext() {
    let payload = EasyBarEventPayload.widget(
      .mouseScrolled,
      widgetID: "calendar",
      targetWidgetID: "calendar_popup",
      button: .middle,
      direction: .down,
      value: 0.75,
      deltaX: 1.5,
      deltaY: -4.25
    )

    let luaPayload = payload.luaPayload

    XCTAssertEqual(luaPayload.name, WidgetEvent.mouseScrolled.rawValue)
    XCTAssertEqual(luaPayload.widgetID, "calendar")
    XCTAssertEqual(luaPayload.targetWidgetID, "calendar_popup")
    XCTAssertEqual(luaPayload.button, MouseButton.middle.rawValue)
    XCTAssertEqual(luaPayload.direction, ScrollDirection.down.rawValue)
    XCTAssertEqual(luaPayload.value, 0.75)
    XCTAssertEqual(luaPayload.deltaX, 1.5)
    XCTAssertEqual(luaPayload.deltaY, -4.25)

    XCTAssertEqual(luaPayload.audio?.value, 0.75)
  }

  /// Verifies that event replay catalog identifies replayable events.
  func testEventReplayCatalogIdentifiesReplayableEvents() {
    XCTAssertTrue(EventReplayCatalog.isReplayable(AppEvent.secondTick.rawValue))
    XCTAssertTrue(EventReplayCatalog.isReplayable(AppEvent.networkChange.rawValue))
    XCTAssertFalse(EventReplayCatalog.isReplayable(WidgetEvent.mouseClicked.rawValue))
    XCTAssertFalse(EventReplayCatalog.isReplayable("unknown_event"))
  }

  /// Verifies that event delivery policy routes only widget events directly to widgets.
  func testEventDeliveryPolicyRoutesOnlyWidgetEventsDirectlyToWidgets() {
    XCTAssertTrue(
      EventDeliveryPolicy.routesDirectlyToWidgets(
        WidgetEvent.mouseClicked.rawValue
      )
    )

    XCTAssertTrue(
      EventDeliveryPolicy.routesDirectlyToWidgets(
        WidgetEvent.sliderPreview.rawValue
      )
    )

    XCTAssertFalse(
      EventDeliveryPolicy.routesDirectlyToWidgets(
        AppEvent.systemWoke.rawValue
      )
    )
  }

  /// Verifies that event delivery policy classifies coalescing events.
  func testEventDeliveryPolicyClassifiesCoalescingEvents() {
    XCTAssertEqual(
      EventDeliveryPolicy.forEventName(AppEvent.secondTick.rawValue),
      .coalescing
    )

    XCTAssertEqual(
      EventDeliveryPolicy.forEventName(AppEvent.intervalTick.rawValue),
      .coalescing
    )

    XCTAssertEqual(
      EventDeliveryPolicy.forEventName(AppEvent.captureActivityChanged.rawValue),
      .coalescing
    )

    XCTAssertEqual(
      EventDeliveryPolicy.forEventName(WidgetEvent.mouseScrolled.rawValue),
      .coalescing
    )

    XCTAssertEqual(
      EventDeliveryPolicy.forEventName(WidgetEvent.sliderPreview.rawValue),
      .coalescing
    )
  }

  /// Verifies that event delivery policy classifies must-deliver events.
  func testEventDeliveryPolicyClassifiesMustDeliverEvents() {
    XCTAssertEqual(
      EventDeliveryPolicy.forEventName(AppEvent.systemWoke.rawValue),
      .mustDeliver
    )

    XCTAssertEqual(
      EventDeliveryPolicy.forEventName(AppEvent.powerSourceChange.rawValue),
      .mustDeliver
    )

    XCTAssertEqual(
      EventDeliveryPolicy.forEventName(WidgetEvent.mouseClicked.rawValue),
      .mustDeliver
    )

    XCTAssertEqual(
      EventDeliveryPolicy.forEventName("unknown_event"),
      .mustDeliver
    )
  }

  /// Verifies that default buffering policy uses smallest buffer for coalescing only subscriptions.
  func testDefaultBufferingPolicyUsesSmallestBufferForCoalescingOnlySubscriptions() {
    let policy = EventDeliveryPolicy.defaultBufferingPolicy(
      for: [
        AppEvent.secondTick.rawValue,
        WidgetEvent.sliderPreview.rawValue,
      ]
    )

    XCTAssertEqual(bufferSize(for: policy), 1)
  }

  /// Verifies that mixed subscriptions use the bounded must-deliver buffer.
  func testDefaultBufferingPolicyBoundsMixedSubscriptions() {
    let policy = EventDeliveryPolicy.defaultBufferingPolicy(
      for: [
        AppEvent.secondTick.rawValue,
        AppEvent.systemWoke.rawValue,
      ]
    )

    XCTAssertEqual(
      bufferSize(for: policy),
      EventDeliveryPolicy.maximumBufferedMustDeliverEvents
    )
  }

  /// Verifies that must-deliver-only subscriptions use the bounded action stream.
  func testDefaultBufferingPolicyBoundsMustDeliverSubscriptions() {
    let policy = EventDeliveryPolicy.defaultBufferingPolicy(
      for: [
        AppEvent.systemWoke.rawValue,
        AppEvent.powerSourceChange.rawValue,
      ]
    )

    XCTAssertEqual(
      bufferSize(for: policy),
      EventDeliveryPolicy.maximumBufferedMustDeliverEvents
    )
  }

  /// Verifies that must-deliver overflow terminates a stalled subscriber.
  func testMustDeliverOverflowTerminatesStalledSubscriber() async {
    let hub = Self.makeHub()
    let stream = await hub.subscribe(eventNames: [AppEvent.systemWoke.rawValue])

    for index in 0...EventDeliveryPolicy.maximumBufferedMustDeliverEvents {
      await hub.emit(.systemWoke, source: "event-\(index)")
    }

    let payloads = await Self.collect(
      from: stream,
      count: EventDeliveryPolicy.maximumBufferedMustDeliverEvents + 1,
      timeoutNanoseconds: 1_000_000_000
    )

    XCTAssertEqual(payloads.count, EventDeliveryPolicy.maximumBufferedMustDeliverEvents)
    XCTAssertEqual(payloads.first?.source, "event-0")
    XCTAssertEqual(
      payloads.last?.source,
      "event-\(EventDeliveryPolicy.maximumBufferedMustDeliverEvents - 1)"
    )
  }

  /// Waits for one payload, timing out instead of hanging the test.
  private static func next(
    from stream: AsyncStream<EasyBarEventPayload>,
    timeoutNanoseconds: UInt64 = 1_000_000_000
  ) async -> EasyBarEventPayload? {
    await collect(
      from: stream,
      count: 1,
      timeoutNanoseconds: timeoutNanoseconds
    ).first
  }

  /// Collects a bounded number of payloads before the timeout wins.
  private static func collect(
    from stream: AsyncStream<EasyBarEventPayload>,
    count: Int,
    timeoutNanoseconds: UInt64
  ) async -> [EasyBarEventPayload] {
    await withTaskGroup(of: [EasyBarEventPayload].self) { group in
      group.addTask {
        var iterator = stream.makeAsyncIterator()
        var payloads: [EasyBarEventPayload] = []
        payloads.reserveCapacity(count)

        while payloads.count < count {
          guard let payload = await iterator.next() else { break }

          payloads.append(payload)
        }

        return payloads
      }

      group.addTask {
        try? await Task.sleep(nanoseconds: timeoutNanoseconds)
        return []
      }

      let payloads = await group.next() ?? []
      group.cancelAll()
      return payloads
    }
  }

  /// Returns the concrete buffer size from an AsyncStream buffering policy.
  private func bufferSize(
    for policy: AsyncStream<EasyBarEventPayload>.Continuation.BufferingPolicy
  ) -> Int? {
    switch policy {
    case .unbounded:
      return nil
    case .bufferingOldest(let count), .bufferingNewest(let count):
      return count
    @unknown default:
      XCTFail("Unhandled buffering policy")
      return nil
    }
  }
}
