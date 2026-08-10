import EasyBarShared
import Foundation

/// Small helper for observing typed EasyBar events in native widgets.
final class EasyBarEventObserver: Sendable {
  private let eventHub: EventHub
  private let task = LockedState<Task<Void, Never>?>(nil)

  /// Creates one EasyBar event observer.
  init(eventHub: EventHub) {
    self.eventHub = eventHub
  }

  /// Starts observing a filtered subset of EasyBar events.
  ///
  /// The handler receives the already typed payload on the main actor.
  func start(
    eventNames: Set<String>,
    widgetTargetIDs: Set<String>? = nil,
    replayLatest: Bool = false,
    bufferingPolicy: AsyncStream<EasyBarEventPayload>.Continuation.BufferingPolicy? = nil,
    handler: @escaping @MainActor @Sendable (EasyBarEventPayload) -> Void
  ) {
    start(
      eventNames: Optional(eventNames),
      widgetTargetIDs: widgetTargetIDs,
      replayLatest: replayLatest,
      bufferingPolicy: bufferingPolicy,
      handler: handler
    )
  }

  /// Starts observing EasyBar events.
  ///
  /// The handler receives the already typed payload on the main actor.
  func start(handler: @escaping @MainActor @Sendable (EasyBarEventPayload) -> Void) {
    start(
      eventNames: nil,
      widgetTargetIDs: nil,
      replayLatest: false,
      bufferingPolicy: nil,
      handler: handler
    )
  }

  /// Starts observing EasyBar events with an optional event-name filter.
  ///
  /// The handler receives the already typed payload on the main actor.
  private func start(
    eventNames: Set<String>?,
    widgetTargetIDs: Set<String>?,
    replayLatest: Bool,
    bufferingPolicy: AsyncStream<EasyBarEventPayload>.Continuation.BufferingPolicy?,
    handler: @escaping @MainActor @Sendable (EasyBarEventPayload) -> Void
  ) {
    let nextTask = Task {
      let stream: AsyncStream<EasyBarEventPayload>
      if let eventNames {
        stream = await eventHub.subscribe(
          eventNames: eventNames,
          widgetTargetIDs: widgetTargetIDs,
          replayLatest: replayLatest,
          bufferingPolicy: bufferingPolicy
        )
      } else {
        stream = await eventHub.subscribeAll(
          widgetTargetIDs: widgetTargetIDs,
          replayLatest: replayLatest,
          bufferingPolicy:
            bufferingPolicy
            ?? .bufferingOldest(EventDeliveryPolicy.maximumBufferedMustDeliverEvents)
        )
      }

      for await payload in stream {
        guard !Task.isCancelled else { break }

        await handler(payload)
      }
    }

    let previousTask = task.withLock { task -> Task<Void, Never>? in
      let previousTask = task
      task = nextTask
      return previousTask
    }
    previousTask?.cancel()
  }

  /// Stops observing EasyBar events.
  func stop() {
    let activeTask = task.withLock { task -> Task<Void, Never>? in
      let activeTask = task
      task = nil
      return activeTask
    }
    activeTask?.cancel()
  }
}
