import Combine
import EasyBarCalendarUI
import EasyBarShared
import Foundation

/// Shared upcoming-calendar snapshot store used by the native upcoming popup.
@MainActor
final class NativeUpcomingCalendarStore: CalendarUpcomingPopupStore {
  @Published private(set) var snapshot: EasyBarShared.CalendarAgentSnapshot?
  @Published private(set) var events: [EasyBarShared.CalendarAgentEvent] = []

  let logger: ProcessLogger

  init(logger: ProcessLogger) {
    self.logger = logger
  }

  /// Applies one calendar snapshot to the shared store.
  func apply(snapshot: EasyBarShared.CalendarAgentSnapshot) {
    logger.debug(
      "upcoming calendar popup applied snapshot",
      .field("access_granted", "\(snapshot.accessGranted)"),
      .field("permission_state", "\(snapshot.permissionState)"),
      .field("events", "\(snapshot.events.count)"),
    )
    self.snapshot = snapshot
    events = snapshot.events
  }

  /// Clears the current calendar snapshot.
  func clear() {
    logger.debug("upcoming calendar popup cleared")
    snapshot = nil
    events = []
  }
}
