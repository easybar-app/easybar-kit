import AppKit
import Combine
import EasyBarShared

/// Dependencies used by the native calendar event composer panel.
struct CalendarEventComposerDependencies {
  /// Fresh composer-calendar snapshot source.
  let snapshotPublisher: AnyPublisher<CalendarAgentSnapshot?, Never>
  /// Refreshes the composer-only calendar metadata snapshot.
  let refreshSnapshots: () -> Void
  /// Creates one calendar event through the calendar agent.
  let createEvent: (CalendarAgentCreateEvent, @escaping @MainActor @Sendable (Bool, String?) -> Void) -> Void
  /// Updates one calendar event through the calendar agent.
  let updateEvent: (CalendarAgentUpdateEvent, @escaping @MainActor @Sendable (Bool, String?) -> Void) -> Void
  /// Deletes one calendar event through the calendar agent.
  let deleteEvent: (CalendarAgentDeleteEvent, @escaping @MainActor @Sendable (Bool, String?) -> Void) -> Void
  /// Opens the system Calendar app.
  let openCalendarApp: () -> Void

  /// Builds the production composer dependency set from app-owned stores and clients.
  @MainActor
  static func live(services: AppViewServices) -> CalendarEventComposerDependencies {
    CalendarEventComposerDependencies(
      snapshotPublisher: services.composerCalendarStore.$snapshot.eraseToAnyPublisher(),
      refreshSnapshots: services.composerCalendarClient.refresh,
      createEvent: services.monthCalendarClient.createEvent(_:completion:),
      updateEvent: services.monthCalendarClient.updateEvent(_:completion:),
      deleteEvent: services.monthCalendarClient.deleteEvent(_:completion:),
      openCalendarApp: {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal")
        else { return }
        NSWorkspace.shared.open(appURL)
      }
    )
  }
}
