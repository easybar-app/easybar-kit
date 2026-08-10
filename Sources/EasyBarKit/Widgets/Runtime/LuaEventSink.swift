import EasyBarShared
import Foundation

/// Serializes bounded event delivery into the Lua runtime off the EventHub hot path.
final class LuaEventSink: @unchecked Sendable {
  static let maximumMustDeliverPayloads = 512
  private static let mustDeliverBacklogWarningThreshold = 128
  private static let coalescingQueueLimit = 128

  private struct QueueEntry {
    let coalescingKey: String?
    var payload: EasyBarEventPayload
  }

  private enum QueuePressure {
    case mustDeliverBacklog(count: Int)
    case mustDeliverOverflow(count: Int, generation: UInt64)
    case coalesced(eventName: String)
  }

  private struct EnqueueOutcome {
    let shouldStartDraining: Bool
    let pressure: QueuePressure?
    let queueDepth: Int
    let generation: UInt64
  }

  private struct State {
    var payloadQueue: [QueueEntry] = []
    var coalescedPayloadIndices: [String: Int] = [:]
    var mustDeliverPayloadCount = 0
    var coalescingPayloadCount = 0
    var nextMustDeliverWarningCount = LuaEventSink.mustDeliverBacklogWarningThreshold
    var draining = false
    var suspendedAfterOverflow = false
    var generation: UInt64 = 0

    var isEmpty: Bool {
      payloadQueue.isEmpty
    }
  }

  private let logger: ProcessLogger
  private let maximumMustDeliverPayloads: Int
  private let sendPayload: @Sendable (String) async -> Void
  private let recordQueueDepth: @Sendable (Int) -> Void
  private let handleMustDeliverOverflow: @Sendable (Int, UInt64) -> Void
  private let recoveryGeneration: LockedState<UInt64>
  private let encoder = JSONEncoder()
  private let state = LockedState(State())

  /// Creates the production Lua event sink.
  init(
    runtime: LuaRuntime,
    logger: ProcessLogger,
    metricsCoordinator: MetricsCoordinator
  ) {
    let recoveryGeneration = LockedState<UInt64>(0)
    self.logger = logger
    self.maximumMustDeliverPayloads = Self.maximumMustDeliverPayloads
    self.recoveryGeneration = recoveryGeneration
    self.sendPayload = { encoded in
      await runtime.send(encoded)
    }
    self.recordQueueDepth = { depth in
      Task {
        await metricsCoordinator.recordLuaEventQueueDepth(depth)
      }
    }
    self.handleMustDeliverOverflow = { _, generation in
      Task {
        guard recoveryGeneration.withLock({ $0 }) == generation else { return }
        await metricsCoordinator.recordLuaEventQueueOverflow()
        await runtime.terminateForRecovery(reason: "must-deliver event queue overflow")
      }
    }
  }

  /// Creates an event sink with injected limits and side effects for focused tests.
  init(
    logger: ProcessLogger,
    maximumMustDeliverPayloads: Int,
    sendPayload: @escaping @Sendable (String) async -> Void,
    recordQueueDepth: @escaping @Sendable (Int) -> Void = { _ in },
    handleMustDeliverOverflow: @escaping @Sendable (Int, UInt64) -> Void
  ) {
    self.logger = logger
    self.maximumMustDeliverPayloads = max(1, maximumMustDeliverPayloads)
    self.recoveryGeneration = LockedState(0)
    self.sendPayload = sendPayload
    self.recordQueueDepth = recordQueueDepth
    self.handleMustDeliverOverflow = handleMustDeliverOverflow
  }

  /// Clears one failed runtime generation and permits delivery to the next runtime.
  func reset() {
    let generation = state.withLock { state -> UInt64 in
      state.generation &+= 1
      clearQueue(state: &state)
      state.draining = false
      state.suspendedAfterOverflow = false
      return state.generation
    }
    recoveryGeneration.withLock { $0 = generation }
    recordQueueDepth(0)
  }

  /// Enqueues one event payload for Lua delivery.
  func enqueue(_ payload: EasyBarEventPayload) {
    let outcome = state.withLock { state -> EnqueueOutcome in
      guard !state.suspendedAfterOverflow else {
        return EnqueueOutcome(
          shouldStartDraining: false,
          pressure: nil,
          queueDepth: 0,
          generation: state.generation
        )
      }

      let pressure: QueuePressure?
      switch EventDeliveryPolicy.forEventName(payload.eventName) {
      case .mustDeliver:
        pressure = enqueueMustDeliver(payload, state: &state)
      case .coalescing:
        pressure = enqueueCoalescing(payload, state: &state)
      }

      if case .mustDeliverOverflow = pressure {
        return EnqueueOutcome(
          shouldStartDraining: false,
          pressure: pressure,
          queueDepth: 0,
          generation: state.generation
        )
      }

      let shouldStartDraining = !state.draining
      state.draining = true
      return EnqueueOutcome(
        shouldStartDraining: shouldStartDraining,
        pressure: pressure,
        queueDepth: state.payloadQueue.count,
        generation: state.generation
      )
    }

    recordQueueDepth(outcome.queueDepth)
    report(outcome.pressure)
    guard outcome.shouldStartDraining else { return }

    Task { [weak self] in
      await self?.drainLoop(generation: outcome.generation)
    }
  }

  /// Current queued payload count exposed for focused tests.
  var queuedPayloadCount: Int {
    state.withLock { $0.payloadQueue.count }
  }

  /// Whether delivery is suspended until a new runtime session begins.
  var isSuspendedAfterOverflow: Bool {
    state.withLock(\.suspendedAfterOverflow)
  }

  /// Appends one must-deliver payload or rejects the unhealthy runtime generation.
  private func enqueueMustDeliver(
    _ payload: EasyBarEventPayload,
    state: inout State
  ) -> QueuePressure? {
    guard state.mustDeliverPayloadCount < maximumMustDeliverPayloads else {
      let overflowCount = state.mustDeliverPayloadCount + 1
      state.generation &+= 1
      clearQueue(state: &state)
      state.draining = false
      state.suspendedAfterOverflow = true
      return .mustDeliverOverflow(count: overflowCount, generation: state.generation)
    }

    state.payloadQueue.append(QueueEntry(coalescingKey: nil, payload: payload))
    state.mustDeliverPayloadCount += 1

    guard state.mustDeliverPayloadCount >= state.nextMustDeliverWarningCount else {
      return nil
    }

    let warningCount = state.mustDeliverPayloadCount
    if state.nextMustDeliverWarningCount <= Int.max / 2 {
      state.nextMustDeliverWarningCount *= 2
    } else {
      state.nextMustDeliverWarningCount = Int.max
    }
    return .mustDeliverBacklog(count: warningCount)
  }

  /// Stores only the newest state payload for each event and widget target.
  private func enqueueCoalescing(
    _ payload: EasyBarEventPayload,
    state: inout State
  ) -> QueuePressure? {
    let key = coalescingKey(for: payload)
    var pressure: QueuePressure?

    if let existingIndex = state.coalescedPayloadIndices[key] {
      _ = removeQueuedPayload(at: existingIndex, state: &state)
    } else if state.coalescingPayloadCount >= Self.coalescingQueueLimit,
      let droppedIndex = state.payloadQueue.firstIndex(where: { $0.coalescingKey != nil })
    {
      let dropped = removeQueuedPayload(at: droppedIndex, state: &state)
      pressure = .coalesced(eventName: dropped.payload.eventName)
    }

    state.coalescedPayloadIndices[key] = state.payloadQueue.count
    state.payloadQueue.append(QueueEntry(coalescingKey: key, payload: payload))
    state.coalescingPayloadCount += 1
    return pressure
  }

  /// Removes one queued payload and keeps coalescing indices and counts consistent.
  private func removeQueuedPayload(at index: Int, state: inout State) -> QueueEntry {
    let removed = state.payloadQueue.remove(at: index)

    if let key = removed.coalescingKey {
      state.coalescedPayloadIndices.removeValue(forKey: key)
      state.coalescingPayloadCount -= 1
    } else {
      state.mustDeliverPayloadCount -= 1
    }

    let shiftedIndices = state.coalescedPayloadIndices.compactMap { entry -> (String, Int)? in
      entry.value > index ? (entry.key, entry.value - 1) : nil
    }
    for (key, shiftedIndex) in shiftedIndices {
      state.coalescedPayloadIndices[key] = shiftedIndex
    }
    return removed
  }

  /// Clears all queue bookkeeping while preserving allocated storage.
  private func clearQueue(state: inout State) {
    state.payloadQueue.removeAll(keepingCapacity: true)
    state.coalescedPayloadIndices.removeAll(keepingCapacity: true)
    state.mustDeliverPayloadCount = 0
    state.coalescingPayloadCount = 0
    state.nextMustDeliverWarningCount = Self.mustDeliverBacklogWarningThreshold
  }

  /// Reports pressure without performing callbacks while the state lock is held.
  private func report(_ pressure: QueuePressure?) {
    switch pressure {
    case .mustDeliverBacklog(let count):
      logger.warn(
        "lua must-deliver event backlog is growing",
        .field("queued_actions", count),
        .field("maximum_actions", maximumMustDeliverPayloads)
      )
    case .mustDeliverOverflow(let count, let generation):
      logger.error(
        "lua must-deliver event queue overflowed; suspending delivery",
        .field("attempted_actions", count),
        .field("maximum_actions", maximumMustDeliverPayloads)
      )
      recoveryGeneration.withLock { $0 = generation }
      handleMustDeliverOverflow(count, generation)
    case .coalesced(let eventName):
      logger.warn(
        "coalescing oldest lua state event due to backpressure",
        .field("name", eventName)
      )
    case nil:
      break
    }
  }

  /// Drains queued payloads until the generation is empty or invalidated.
  private func drainLoop(generation: UInt64) async {
    while true {
      let batch = takeNextBatch(generation: generation)
      guard !batch.isEmpty else { return }

      for payload in batch {
        guard isCurrentGeneration(generation) else { return }
        await send(payload)
      }
    }
  }

  /// Takes one stable ordered batch for the expected runtime generation.
  private func takeNextBatch(generation: UInt64) -> [EasyBarEventPayload] {
    let result = state.withLock { state -> ([EasyBarEventPayload], Int) in
      guard state.generation == generation, !state.suspendedAfterOverflow else {
        return ([], state.payloadQueue.count)
      }
      guard !state.isEmpty else {
        state.draining = false
        return ([], 0)
      }

      let payloads = state.payloadQueue.map(\.payload)
      clearQueue(state: &state)
      return (payloads, 0)
    }
    recordQueueDepth(result.1)
    return result.0
  }

  private func isCurrentGeneration(_ generation: UInt64) -> Bool {
    state.withLock { state in
      state.generation == generation && !state.suspendedAfterOverflow
    }
  }

  /// Encodes and sends one payload to the Lua runtime.
  private func send(_ payload: EasyBarEventPayload) async {
    guard let encoded = encodeJSON(payload.luaPayload) else {
      logger.error("failed to encode lua event payload", .field("name", payload.eventName))
      return
    }
    await sendPayload(encoded)
  }

  private func encodeJSON(_ payload: LuaEventPayload) -> String? {
    guard
      let data = try? encoder.encode(payload),
      let string = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return string
  }

  private func coalescingKey(for payload: EasyBarEventPayload) -> String {
    [payload.eventName, payload.widgetID ?? "", payload.targetWidgetID ?? ""]
      .joined(separator: "\u{1f}")
  }
}
