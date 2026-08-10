import SwiftUI

/// App-owned services needed by deeply nested SwiftUI widget views.
struct AppViewServices {
  let eventHub: EventHub
  let inboxStore: InboxStore
  let monthCalendarStore: NativeMonthCalendarStore
  let upcomingCalendarStore: NativeUpcomingCalendarStore
  let composerCalendarStore: NativeComposerCalendarStore
  let monthCalendarClient: MonthCalendarAgentClient
  let upcomingCalendarClient: UpcomingCalendarAgentClient
  let composerCalendarClient: ComposerCalendarAgentClient
}

private struct AppViewServicesKey: EnvironmentKey {
  static let defaultValue: AppViewServices? = nil
}

extension EnvironmentValues {
  var appViewServices: AppViewServices? {
    get { self[AppViewServicesKey.self] }
    set { self[AppViewServicesKey.self] = newValue }
  }
}
