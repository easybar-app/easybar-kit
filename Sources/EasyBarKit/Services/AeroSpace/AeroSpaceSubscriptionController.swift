import EasyBarShared
import Foundation

/// Owns the long-lived AeroSpace socket subscription.
///
/// Sendability is guarded by `LockedState`; process session ownership,
/// generation checks, reconnect queue state, and stream buffering are serialized
/// before callbacks can observe or mutate them.
final class AeroSpaceSubscriptionController: AeroSpaceSubscriptionControlling, @unchecked Sendable {
  /// Default reconnect delays used after an existing AeroSpace subscription exits.
  private static let defaultReconnectDelays: [TimeInterval] = [0.25, 0.5, 1, 2, 5]

  /// Locked lifecycle state for the subscription.
  private struct State {
    var running = false
    var generation: UInt64 = 0
    var subscription: AeroSpaceSubscriptionSession?

    mutating func start() -> UInt64? {
      guard !running else { return nil }
      running = true
      generation &+= 1
      return generation
    }

    mutating func stop() -> AeroSpaceSubscriptionSession? {
      guard running else { return nil }
      running = false
      generation &+= 1

      let stoppedSubscription = subscription
      subscription = nil
      return stoppedSubscription
    }

    mutating func attach(
      _ newSubscription: AeroSpaceSubscriptionSession,
      generation: UInt64
    ) -> Bool {
      guard running, self.generation == generation else {
        return false
      }

      subscription = newSubscription
      return true
    }

    mutating func detach(
      subscription: AeroSpaceSubscriptionSession,
      generation: UInt64
    ) -> (wasActive: Bool, subscription: AeroSpaceSubscriptionSession?) {
      let matchedSubscription = self.subscription === subscription ? self.subscription : nil
      if matchedSubscription != nil {
        self.subscription = nil
      }

      return (running && self.generation == generation, matchedSubscription)
    }
  }

  /// Logger used for subscription diagnostics.
  private let logger: ProcessLogger
  /// Creates concrete subscription sessions.
  private let subscriptionLauncher: any AeroSpaceSubscriptionLaunching
  /// Scheduler used to reconnect after subscription exits.
  private let reconnectScheduler: any AeroSpaceReconnectScheduling
  /// Called for every decoded or fallback AeroSpace event line.
  private let handleEvent: (AeroSpaceSubscriptionEvent) -> Void
  /// Current locked controller state.
  private let state = LockedState(State())

  /// Creates one AeroSpace subscription controller.
  init(
    logger: ProcessLogger,
    subscriptionLauncher: (any AeroSpaceSubscriptionLaunching)? = nil,
    reconnectScheduler: (any AeroSpaceReconnectScheduling)? = nil,
    reconnectDelays: [TimeInterval] = AeroSpaceSubscriptionController.defaultReconnectDelays,
    sleeper: any AsyncSleeper = TaskSleeper(),
    handleEvent: @escaping (AeroSpaceSubscriptionEvent) -> Void
  ) {
    self.logger = logger
    self.subscriptionLauncher =
      subscriptionLauncher
      ?? AeroSpaceSocketSubscriptionLauncher()
    self.reconnectScheduler =
      reconnectScheduler
      ?? BackoffScheduler(
        label: "aerospace subscription reconnect",
        delays: reconnectDelays,
        logger: logger,
        sleeper: sleeper
      )
    self.handleEvent = handleEvent
  }

  /// Starts the long-lived AeroSpace subscription if possible.
  func start() {
    let generation = withLock { state in state.start() }

    guard let generation else { return }

    reconnectScheduler.cancel()
    startSubscription(generation: generation)
  }

  /// Stops the subscription.
  func stop() {
    let subscription = withLock { state in state.stop() }

    reconnectScheduler.cancel()
    subscription?.stop()

    logger.debug("aerospace subscription stopped")
  }

  /// Starts one concrete AeroSpace socket subscription session.
  private func startSubscription(generation: UInt64) {
    guard isActive(generation: generation) else { return }

    let subscription = subscriptionLauncher.makeSubscription()

    let shouldStart = withLock { state in
      state.attach(subscription, generation: generation)
    }

    guard shouldStart else {
      subscription.stop()
      return
    }

    DetachedTask.run(priority: .utility) { [weak self] in
      guard let self else { return }

      do {
        try subscription.start(
          onEventFrame: { [weak self] data in
            self?.handleEventFrame(data, generation: generation)
          },
          onDisconnect: { [weak self] subscription, errorMessage in
            self?.handleDisconnect(
              subscription: subscription,
              errorMessage: errorMessage,
              generation: generation
            )
          }
        )
      } catch {
        let result = self.withLock { state in
          state.detach(subscription: subscription, generation: generation)
        }
        result.subscription?.invalidate()
        guard result.wasActive else { return }
        self.logger.debug(
          "failed to start aerospace subscription",
          .field("error", error)
        )
        self.scheduleReconnect(generation: generation)
        return
      }

      guard self.isActive(generation: generation) else {
        subscription.stop()
        return
      }

      self.logger.debug(
        "aerospace subscription started",
        .field("events", AeroSpaceSubscriptionEvent.subscriptionDescription)
      )
    }
  }

  /// Decodes one complete length-prefixed event frame.
  private func handleEventFrame(_ data: Data, generation: UInt64) {
    guard isActive(generation: generation), !data.isEmpty else { return }

    let event: AeroSpaceSubscriptionEvent
    do {
      event = try JSONDecoder().decode(AeroSpaceSubscriptionEvent.self, from: data)
    } catch {
      event = AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.unknown)
      logger.debug(
        "aerospace subscription frame was not a known JSON event",
        .field("bytes", data.count),
        .field("error", error)
      )
    }

    logger.debug(
      "aerospace subscription event received",
      .field("event", event.name)
    )
    resetReconnectBackoff(generation: generation)
    handleEvent(event)
  }

  /// Handles a closed AeroSpace socket subscription.
  private func handleDisconnect(
    subscription: AeroSpaceSubscriptionSession,
    errorMessage: String?,
    generation: UInt64
  ) {
    let result = withLock { state in
      state.detach(subscription: subscription, generation: generation)
    }

    result.subscription?.invalidate()

    guard result.wasActive else { return }

    if let errorMessage {
      logger.warn(
        "aerospace subscription disconnected",
        .field("error", errorMessage)
      )
    } else {
      logger.debug("aerospace subscription ended")
    }

    scheduleReconnect(generation: generation)
  }

  /// Schedules a bounded reconnect attempt while the integration remains active.
  private func scheduleReconnect(generation: UInt64) {
    guard isActive(generation: generation) else { return }

    reconnectScheduler.schedule { [weak self] in
      guard let self else { return }
      guard self.isActive(generation: generation) else { return }
      self.startSubscription(generation: generation)
    }
  }

  /// Resets reconnect backoff after the event stream proves healthy.
  private func resetReconnectBackoff(generation: UInt64) {
    guard isActive(generation: generation) else { return }
    reconnectScheduler.resetDelay()
  }

  /// Returns whether callbacks for the given generation are still valid.
  private func isActive(generation: UInt64) -> Bool {
    withLock { state in
      state.running && state.generation == generation
    }
  }

  /// Runs one closure while holding the controller state lock.
  private func withLock<T>(_ body: (inout State) -> T) -> T {
    state.withLock(body)
  }
}
