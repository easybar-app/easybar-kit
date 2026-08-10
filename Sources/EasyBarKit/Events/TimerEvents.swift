import EasyBarShared
import Foundation

/// Widget-scoped interval schedule requested by the Lua runtime.
struct WidgetIntervalSchedule: Hashable, Sendable {
  let widgetID: String
  let interval: TimeInterval
}

/// Owns app event timers and serializes their emissions on the main actor.
@MainActor
final class TimerEvents {
  /// Logger used for timer diagnostics.
  private let logger: ProcessLogger
  private let eventHub: EventHub

  /// Timer for minute ticks.
  private var minuteTimer: Timer?
  /// Timer for second ticks.
  private var secondTimer: Timer?
  /// Timers for widget-scoped Lua interval callbacks.
  private var intervalTimers: [WidgetIntervalSchedule: Timer] = [:]

  /// Coalesced timer payloads waiting for the event hub.
  private var pendingEmissions: [String: EasyBarEventPayload] = [:]
  /// Stable insertion order for pending timer payloads.
  private var pendingEmissionKeys: [String] = []
  /// Single task draining timer emissions in order.
  private var emissionTask: Task<Void, Never>?

  /// Active widget interval schedules retained by the timer source.
  var activeIntervalSchedules: Set<WidgetIntervalSchedule> {
    Set(intervalTimers.keys)
  }

  /// Creates one timer event source.
  init(logger: ProcessLogger, eventHub: EventHub) {
    self.logger = logger
    self.eventHub = eventHub
  }

  /// Starts the minute timer used by Lua `minute_tick` subscriptions.
  func startMinuteTimer() {
    minuteTimer?.invalidate()
    minuteTimer = makeAlignedTimer(
      interval: 60,
      tolerance: 1,
      event: .minuteTick
    )

    logger.debug("minute timer started")
  }

  /// Stops the minute timer.
  func stopMinuteTimer() {
    minuteTimer?.invalidate()
    minuteTimer = nil
    removePendingEmission(forKey: appEmissionKey(.minuteTick))
  }

  /// Starts the second timer used by explicit `second_tick` subscriptions.
  func startSecondTimer() {
    secondTimer?.invalidate()
    secondTimer = makeAlignedTimer(
      interval: 1,
      tolerance: 0.05,
      event: .secondTick
    )

    logger.debug("second timer started")
  }

  /// Stops the second timer.
  func stopSecondTimer() {
    secondTimer?.invalidate()
    secondTimer = nil
    removePendingEmission(forKey: appEmissionKey(.secondTick))
  }

  /// Replaces every widget-scoped interval timer used by Lua `interval` callbacks.
  func replaceIntervalTimers(schedules: Set<WidgetIntervalSchedule>) {
    stopIntervalTimers()

    for schedule in schedules {
      let timer = makeRepeatingTimer(
        interval: schedule.interval,
        tolerance: min(1, max(0.05, schedule.interval * 0.05))
      ) { [weak self] in
        self?.enqueueEmission(
          .app(.intervalTick, widgetID: schedule.widgetID),
          key: self?.intervalEmissionKey(schedule) ?? ""
        )
      }

      intervalTimers[schedule] = timer

      logger.debug(
        "interval timer started",
        .field("widget_id", schedule.widgetID),
        .field("interval", schedule.interval),
      )
    }
  }

  /// Stops every widget-scoped interval timer.
  func stopIntervalTimers() {
    let keys = Set(intervalTimers.keys.map(intervalEmissionKey))

    for timer in intervalTimers.values {
      timer.invalidate()
    }

    intervalTimers.removeAll()
    removePendingEmissions(forKeys: keys)
  }

  /// Stops and clears all active timers and queued ticks.
  func stopAll() {
    minuteTimer?.invalidate()
    minuteTimer = nil
    secondTimer?.invalidate()
    secondTimer = nil

    for timer in intervalTimers.values {
      timer.invalidate()
    }
    intervalTimers.removeAll()

    pendingEmissions.removeAll()
    pendingEmissionKeys.removeAll()
    emissionTask?.cancel()
    emissionTask = nil
  }

  /// Starts one repeating timer aligned to the next real wall-clock boundary.
  private func makeAlignedTimer(
    interval: TimeInterval,
    tolerance: TimeInterval,
    event: AppEvent
  ) -> Timer {
    makeTimer(
      fireDate: nextBoundary(after: Date(), interval: interval),
      interval: interval,
      tolerance: tolerance
    ) { [weak self] in
      self?.enqueueEmission(.app(event), key: self?.appEmissionKey(event) ?? "")
    }
  }

  /// Starts one repeating timer relative to its creation time.
  private func makeRepeatingTimer(
    interval: TimeInterval,
    tolerance: TimeInterval,
    onFire: @escaping @MainActor @Sendable () -> Void
  ) -> Timer {
    makeTimer(
      fireDate: Date().addingTimeInterval(interval),
      interval: interval,
      tolerance: tolerance,
      onFire: onFire
    )
  }

  /// Creates one timer explicitly bound to the main run loop.
  private func makeTimer(
    fireDate: Date,
    interval: TimeInterval,
    tolerance: TimeInterval,
    onFire: @escaping @MainActor @Sendable () -> Void
  ) -> Timer {
    let timer = Timer(
      fire: fireDate,
      interval: interval,
      repeats: true
    ) { _ in
      MainActor.assumeIsolated {
        onFire()
      }
    }

    timer.tolerance = tolerance
    RunLoop.main.add(timer, forMode: .common)
    return timer
  }

  /// Queues or replaces one timer state payload and starts the single drain task.
  private func enqueueEmission(_ payload: EasyBarEventPayload, key: String) {
    guard !key.isEmpty else { return }

    if pendingEmissions.updateValue(payload, forKey: key) == nil {
      pendingEmissionKeys.append(key)
    }

    guard emissionTask == nil else { return }

    emissionTask = Task { @MainActor [weak self] in
      await self?.drainEmissionQueue()
    }
  }

  /// Delivers queued timer payloads serially, coalescing duplicate pending ticks.
  private func drainEmissionQueue() async {
    defer { emissionTask = nil }

    while !Task.isCancelled, let payload = takeNextEmission() {
      await eventHub.emit(payload)
    }
  }

  /// Removes and returns the next pending timer payload.
  private func takeNextEmission() -> EasyBarEventPayload? {
    while let key = pendingEmissionKeys.first {
      pendingEmissionKeys.removeFirst()
      if let payload = pendingEmissions.removeValue(forKey: key) {
        return payload
      }
    }

    return nil
  }

  /// Removes one pending timer payload.
  private func removePendingEmission(forKey key: String) {
    pendingEmissions.removeValue(forKey: key)
    pendingEmissionKeys.removeAll { $0 == key }
  }

  /// Removes a set of pending timer payloads.
  private func removePendingEmissions(forKeys keys: Set<String>) {
    guard !keys.isEmpty else { return }

    for key in keys {
      pendingEmissions.removeValue(forKey: key)
    }
    pendingEmissionKeys.removeAll { keys.contains($0) }
  }

  /// Returns the queue key for one app timer.
  private func appEmissionKey(_ event: AppEvent) -> String {
    "app:\(event.rawValue)"
  }

  /// Returns the queue key for one widget interval timer.
  private func intervalEmissionKey(_ schedule: WidgetIntervalSchedule) -> String {
    "interval:\(schedule.widgetID):\(schedule.interval.bitPattern)"
  }

  /// Returns the next whole second or minute boundary after the given time.
  private func nextBoundary(after date: Date, interval: TimeInterval) -> Date {
    let current = date.timeIntervalSinceReferenceDate
    let nextStep = floor(current / interval) + 1

    return Date(timeIntervalSinceReferenceDate: nextStep * interval)
  }
}
