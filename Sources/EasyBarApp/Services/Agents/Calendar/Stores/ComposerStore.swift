import Combine
import EasyBarShared
import Foundation

/// Shared fresh calendar snapshot store used only by the event composer.
@MainActor
final class NativeComposerCalendarStore: ObservableObject {
  /// Latest fresh snapshot used for composer calendar choices.
  @Published private(set) var snapshot: EasyBarShared.CalendarAgentSnapshot?

  /// Logger used for composer-calendar diagnostics.
  let logger: ProcessLogger

  /// Creates one composer-calendar snapshot store.
  init(logger: ProcessLogger) {
    self.logger = logger
  }

  /// Applies one fresh calendar snapshot to the shared composer store.
  func apply(snapshot: EasyBarShared.CalendarAgentSnapshot) {
    self.snapshot = snapshot

    logger.debug(
      "composer calendar store applied snapshot",
      .field("access_granted", "\(snapshot.accessGranted)"),
      .field("permission_state", snapshot.permissionState),
      .field("writable_calendars", "\(snapshot.writableCalendars.count)")
    )
  }

  /// Clears the current composer-calendar snapshot.
  func clear() {
    snapshot = nil
    logger.debug("composer calendar store cleared")
  }
}
