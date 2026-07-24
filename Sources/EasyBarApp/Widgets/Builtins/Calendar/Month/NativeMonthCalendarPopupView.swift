import EasyBarCalendarUI
import SwiftUI

/// EasyBar adapter for the reusable month-calendar popup.
struct NativeMonthCalendarPopupView: View {
  @EnvironmentObject private var configStore: ConfigSnapshotStore
  @StateObject private var composerPanel: CalendarEventComposerPanelController
  private let services: AppViewServices

  init(services: AppViewServices) {
    self.services = services
    _composerPanel = StateObject(
      wrappedValue: CalendarEventComposerPanelController(services: services)
    )
  }

  /// Renders the EasyBar-wired month-calendar popup.
  var body: some View {
    let config = configStore.snapshot.builtins.calendar

    CalendarMonthPopupView(
      store: services.monthCalendarStore,
      logger: services.monthCalendarStore.logger,
      config: config.calendarMonthPopupUIConfig,
      appointmentsStyle: config.appointmentsCalendarUIStyle,
      birthdays: config.birthdayCalendarUIStyle,
      emptyText: config.appointments.emptyText,
      eventActions: CalendarEventActionFactory.makeActions(
        meetingURLPatterns: config.appointments.meetingURLPatterns
      ),
      onVisibleMonthChanged: { visibleMonth in
        services.monthCalendarClient.focusVisibleMonth(visibleMonth)
      },
      onCreateEvent: { defaultDate, onChanged in
        composerPanel.present(
          defaultDate: defaultDate,
          config: config,
          onChanged: onChanged
        )
      },
      onEditEvent: { event, onChanged in
        composerPanel.present(
          event: event,
          config: config,
          onChanged: onChanged
        )
      },
      onRefreshRequested: {
        services.monthCalendarClient.refresh()
        services.upcomingCalendarClient.refresh()
      }
    )
  }
}
