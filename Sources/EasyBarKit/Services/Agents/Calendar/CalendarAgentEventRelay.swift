import EasyBarShared
import Foundation

/// Coalesces calendar-agent snapshot updates into a single app-wide calendar event.
///
/// Sendability is guarded by `LockedState`; running state and generation checks
/// are serialized, and the debounced scheduler owns its own locked state.
final class CalendarAgentEventRelay: @unchecked Sendable {
  private struct State {
    var running = false
    var generation: UInt64 = 0
  }

  /// Logger used for relay diagnostics.
  private let logger: ProcessLogger
  let eventHub: EventHub
  /// Locked relay state.
  private let state = LockedState(State())

  /// Scheduler that coalesces snapshot updates.
  private lazy var scheduler = DebouncedActionScheduler(
    label: "calendar agent event relay",
    delay: 0.05,
    logger: logger.child("scheduler")
  )

  /// Creates the shared calendar-agent event relay.
  init(logger: ProcessLogger, eventHub: EventHub) {
    self.logger = logger
    self.eventHub = eventHub
  }

  /// Activates the relay for runtime event delivery.
  func start() {
    state.withLock { state in
      state.running = true
      state.generation &+= 1
    }
  }

  /// Cancels pending emissions and disables the relay.
  func stop() {
    state.withLock { state in
      state.running = false
      state.generation &+= 1
    }
    scheduler.cancel()
  }

  /// Schedules one debounced `calendar_change` emission.
  ///
  /// Both month and upcoming calendar clients may receive snapshots for the same
  /// underlying EventKit change. This relay collapses those near-simultaneous
  /// updates into one app-wide event.
  func noteSnapshotUpdate() {
    let generation = state.withLock { state -> UInt64? in
      guard state.running else { return nil }
      return state.generation
    }

    guard let generation else { return }

    scheduler.schedule { [weak self] in
      guard let self else { return }
      let shouldEmit = self.state.withLock { state in
        state.running && state.generation == generation
      }
      guard shouldEmit else { return }

      Task {
        await self.eventHub.emit(.calendarChange)
      }
    }
  }
}
