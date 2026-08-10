import EasyBarCalendarUI
import SwiftUI

/// EasyBar adapter for the reusable upcoming-calendar popup.
struct NativeUpcomingCalendarPopupView: View {
  @EnvironmentObject private var configStore: ConfigSnapshotStore
  @StateObject private var composerPanel: CalendarEventComposerPanelController
  private let services: AppViewServices

  init(services: AppViewServices) {
    self.services = services
    _composerPanel = StateObject(
      wrappedValue: CalendarEventComposerPanelController(services: services)
    )
  }

  /// Renders the EasyBar-wired upcoming-calendar popup.
  var body: some View {
    let config = configStore.snapshot.builtins.calendar

    CalendarUpcomingPopupView(
      store: services.upcomingCalendarStore,
      config: config.calendarUpcomingPopupUIConfig,
      appointmentsStyle: config.appointmentsCalendarUIStyle,
      birthdays: config.birthdayCalendarUIStyle,
      emptyText: config.appointments.emptyText,
      eventActions: CalendarEventActionFactory.makeActions(
        meetingURLPatterns: config.appointments.meetingURLPatterns
      ),
      onEventTap: { event in
        composerPanel.present(event: event, config: config) {
          services.monthCalendarClient.refresh()
          services.upcomingCalendarClient.refresh()
        }
      }
    )
  }
}
