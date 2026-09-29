import SwiftUI

/// App-owned services needed by deeply nested SwiftUI widget views.
struct AppViewServices {
  /// The event hub for this app view services.
  let eventHub: EventHub
  /// The inbox store for this app view services.
  let inboxStore: InboxStore
  /// The month calendar store for this app view services.
  let monthCalendarStore: NativeMonthCalendarStore
  /// The upcoming calendar store for this app view services.
  let upcomingCalendarStore: NativeUpcomingCalendarStore
  /// The composer calendar store for this app view services.
  let composerCalendarStore: NativeComposerCalendarStore
  /// The month calendar client for this app view services.
  let monthCalendarClient: MonthCalendarAgentClient
  /// The upcoming calendar client for this app view services.
  let upcomingCalendarClient: UpcomingCalendarAgentClient
  /// The composer calendar client for this app view services.
  let composerCalendarClient: ComposerCalendarAgentClient
}

/// Stores app view services key data.
private struct AppViewServicesKey: EnvironmentKey {
  /// The default value for this app view services key.
  static let defaultValue: AppViewServices? = nil
}

extension EnvironmentValues {
  var appViewServices: AppViewServices? {
    get { self[AppViewServicesKey.self] }
    set { self[AppViewServicesKey.self] = newValue }
  }
}
