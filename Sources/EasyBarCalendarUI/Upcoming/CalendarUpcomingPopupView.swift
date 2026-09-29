import EasyBarCalendarPresentation
import EasyBarShared
import SwiftUI

/// Stores calendar upcoming popup view data.
public struct CalendarUpcomingPopupView<Store: CalendarUpcomingPopupStore>: View {

  /// The resolved calendar for this calendar upcoming popup view.
  private var resolvedCalendar: Calendar {
    var calendar = Calendar.current

    if let firstWeekday = config.firstWeekday {
      calendar.firstWeekday = firstWeekday
    }

    return calendar
  }

  @ObservedObject private var store: Store
  /// The config for this calendar upcoming popup view.
  private let config: CalendarUpcomingPopupConfig
  /// The appointments style for this calendar upcoming popup view.
  private let appointmentsStyle: CalendarAppointmentsStyle
  /// The birthdays for this calendar upcoming popup view.
  private let birthdays: CalendarBirthdayStyle
  /// The empty text for this calendar upcoming popup view.
  private let emptyText: String
  /// The event actions for this calendar upcoming popup view.
  private let eventActions: CalendarEventActions?
  /// The now provider for this calendar upcoming popup view.
  private let nowProvider: () -> Date
  /// The on event tap for this calendar upcoming popup view.
  private let onEventTap: (CalendarAgentEvent) -> Void

  /// Creates a calendar upcoming popup view.
  public init(
    store: Store,
    config: CalendarUpcomingPopupConfig,
    appointmentsStyle: CalendarAppointmentsStyle,
    birthdays: CalendarBirthdayStyle,
    emptyText: String,
    eventActions: CalendarEventActions? = nil,
    nowProvider: @escaping () -> Date = Date.init,
    onEventTap: @escaping (CalendarAgentEvent) -> Void
  ) {
    self.store = store
    self.config = config
    self.appointmentsStyle = appointmentsStyle
    self.birthdays = birthdays
    self.emptyText = emptyText
    self.eventActions = eventActions
    self.nowProvider = nowProvider
    self.onEventTap = onEventTap
  }

  /// Renders the reusable upcoming-calendar popup content.
  public var body: some View {
    VStack(alignment: .leading, spacing: config.spacing) {
      ForEach(upcomingDates, id: \.self) { date in
        CalendarAppointmentsListView(
          title: title(for: date),
          rows: appointmentRows(for: date),
          emptyText: emptyText,
          style: appointmentsStyle,
          birthdayIcon: birthdays.birthdayIcon,
          birthdayIconColorHex: birthdays.birthdayIconColorHex,
          defaultIndicatorColorHex: config.defaultIndicatorColorHex,
          calendar: resolvedCalendar,
          dateHeaderText: formattedDayHeader,
          eventActions: eventActions,
          onEventTap: onEventTap
        )
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, config.paddingX)
    .padding(.vertical, config.paddingY)
    .background(color(config.backgroundColorHex))
    .overlay {
      RoundedRectangle(cornerRadius: config.cornerRadius)
        .stroke(
          color(config.borderColorHex),
          lineWidth: config.borderWidth
        )
    }
    .clipShape(
      RoundedRectangle(cornerRadius: config.cornerRadius)
    )
    .padding(.horizontal, config.marginX)
    .padding(.vertical, config.marginY)
    .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
  }

  /// Returns the dates rendered by the upcoming popup.
  private var upcomingDates: [Date] {
    let start = resolvedCalendar.startOfDay(for: nowProvider())

    return (0..<max(1, config.days)).compactMap { offset in
      resolvedCalendar.date(byAdding: .day, value: offset, to: start)
    }
  }

  /// Returns one formatted section title for the given date.
  private func title(for date: Date) -> String {
    if resolvedCalendar.isDateInToday(date) {
      return "Today:"
    }

    if resolvedCalendar.isDateInTomorrow(date) {
      return "Tomorrow:"
    }

    let dateText = CalendarDateFormatter.string(
      from: date,
      calendar: resolvedCalendar,
      dateFormat: "dd.MM.yyyy"
    )
    return "\(dateText):"
  }

  /// Returns the event rows displayed for one upcoming day.
  private func appointmentRows(for date: Date) -> [CalendarAppointmentsListRow] {
    events(for: date).map { event in
      CalendarAppointmentsListRow(id: event.id, kind: .event(event))
    }
  }

  /// Returns the visible events for one day using the current upcoming filtering mode.
  private func events(for date: Date) -> [CalendarAgentEvent] {
    let startOfDay = resolvedCalendar.startOfDay(for: date)

    guard let endOfDay = resolvedCalendar.date(byAdding: .day, value: 1, to: startOfDay) else {
      return []
    }

    let now = nowProvider()
    let effectiveStart =
      config.excludePastEvents && resolvedCalendar.isDateInToday(date)
      ? max(startOfDay, now)
      : startOfDay

    return store.events
      .filter { event in
        event.startDate < endOfDay && event.endDate > effectiveStart
      }
      .sorted { lhs, rhs in
        CalendarAgendaBuilder.eventSortOrder(lhs: lhs, rhs: rhs)
      }
  }

  /// Formats one day header using the month popup selection format.
  private func formattedDayHeader(_ date: Date) -> String {
    CalendarDateFormatter.string(
      from: date,
      calendar: resolvedCalendar,
      dateFormat: config.selectionDateFormat
    )
  }

  /// Converts one hex string into SwiftUI color.
  private func color(_ hex: String) -> Color {
    Color(calendarHex: hex)
  }
}
