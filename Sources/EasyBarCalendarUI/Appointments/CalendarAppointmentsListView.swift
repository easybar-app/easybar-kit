import EasyBarCalendarPresentation
import EasyBarShared
import SwiftUI

/// One render row in a calendar appointments list.
public struct CalendarAppointmentsListRow: Identifiable {
  public enum Kind {
    case dayHeader(Date)
    case event(CalendarAgentEvent)
  }

  public let id: String
  public let kind: Kind

  public init(id: String, kind: Kind) {
    self.id = id
    self.kind = kind
  }
}

/// Shared appointments list used by calendar month and upcoming surfaces.
public struct CalendarAppointmentsListView: View {
  public let title: String?
  public let rows: [CalendarAppointmentsListRow]
  public let emptyText: String
  public let style: CalendarAppointmentsStyle
  public let birthdayIcon: String
  public let birthdayIconColorHex: String?
  public let defaultIndicatorColorHex: String
  public let calendar: Calendar
  public let dateHeaderText: (Date) -> String
  public let eventActions: CalendarEventActions?
  public let onEventTap: ((CalendarAgentEvent) -> Void)?

  public init(
    title: String?,
    rows: [CalendarAppointmentsListRow],
    emptyText: String,
    style: CalendarAppointmentsStyle,
    birthdayIcon: String,
    birthdayIconColorHex: String?,
    defaultIndicatorColorHex: String,
    calendar: Calendar,
    dateHeaderText: @escaping (Date) -> String,
    eventActions: CalendarEventActions? = nil,
    onEventTap: ((CalendarAgentEvent) -> Void)?
  ) {
    self.title = title
    self.rows = rows
    self.emptyText = emptyText
    self.style = style
    self.birthdayIcon = birthdayIcon
    self.birthdayIconColorHex = birthdayIconColorHex
    self.defaultIndicatorColorHex = defaultIndicatorColorHex
    self.calendar = calendar
    self.dateHeaderText = dateHeaderText
    self.eventActions = eventActions
    self.onEventTap = onEventTap
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let title, !title.isEmpty {
        Text(title)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(color(style.secondaryTextColorHex))
          .padding(.top, 2)
          .padding(.bottom, 1)
      }

      if rows.isEmpty {
        Text(emptyText)
          .foregroundStyle(color(style.emptyTextColorHex))
      } else {
        ForEach(rows) { row in
          switch row.kind {
          case .dayHeader(let date):
            Text(dateHeaderText(date))
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(color(style.secondaryTextColorHex))
              .padding(.top, 2)
              .padding(.bottom, 1)
          case .event(let event):
            appointmentRow(event)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func appointmentRow(_ event: CalendarAgentEvent) -> some View {
    let isBirthday = CalendarAgendaBuilder.isBirthdayEvent(event)
    let showsActions = !isBirthday && hasActionMenu(for: event)
    let content = appointmentRowContent(
      event,
      showsChevron: !showsActions && !isBirthday && onEventTap != nil,
      showsActions: showsActions
    )

    if let onEventTap, !isBirthday {
      return AnyView(
        content
          .contentShape(Rectangle())
          .onTapGesture { onEventTap(event) }
      )
    }

    return AnyView(content)
  }

  private func appointmentRowContent(
    _ event: CalendarAgentEvent,
    showsChevron: Bool,
    showsActions: Bool
  ) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Rectangle()
        .fill(color(indicatorColorHex(for: event)))
        .frame(width: 3)
        .clipShape(RoundedRectangle(cornerRadius: 1.5))

      VStack(alignment: .leading, spacing: 2) {
        appointmentMetaTopView(for: event)
        appointmentTitleView(for: event)
        appointmentEndTimeView(for: event)

        if style.showCalendarName, let calendarName = event.calendarName, !calendarName.isEmpty {
          Text(calendarName)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(color(style.secondaryTextColorHex))
        }

        if style.showLocation, let locationText = event.location, !locationText.isEmpty {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !style.locationIcon.isEmpty {
              Text(style.locationIcon)
                .font(CalendarUIPrimitives.iconFont(size: 10))
                .foregroundStyle(color(style.locationIconColorHex ?? style.secondaryTextColorHex))
            }

            Text(locationText)
              .font(.system(size: 11, weight: .regular))
              .foregroundStyle(color(style.secondaryTextColorHex))
              .lineLimit(1)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if showsActions {
        actionMenu(for: event)
          .padding(.top, 1)
      } else if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(color(style.secondaryTextColorHex).opacity(0.8))
          .padding(.top, 3)
      }
    }
    .padding(.leading, CGFloat(style.itemIndent))
    .padding(.vertical, 4)
  }

  private func hasActionMenu(for event: CalendarAgentEvent) -> Bool {
    onEventTap != nil || eventActions?.hasVisibleAction(for: event) == true
  }

  @ViewBuilder
  private func actionMenu(for event: CalendarAgentEvent) -> some View {
    Menu {
      if let onEventTap {
        Button(action: { onEventTap(event) }) {
          Label("Edit", systemImage: "pencil")
        }
      }

      if let copyDetails = eventActions?.copyDetails {
        Button(action: { copyDetails(event) }) {
          Label("Copy Details", systemImage: "doc.on.doc")
        }
      }

      if event.hasUsableURL, let actions = eventActions, let openURL = actions.openURL {
        Button(action: { openURL(event) }) {
          Label(actions.urlActionTitle(for: event), systemImage: "link")
        }
      }

      if let openCalendar = eventActions?.openCalendar {
        Button(action: { openCalendar(event) }) {
          Label("Open in Calendar", systemImage: "calendar")
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(color(style.secondaryTextColorHex).opacity(0.9))
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func appointmentTitleView(for event: CalendarAgentEvent) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      if event.isAllDay {
        let prefix = appointmentPrefix(for: event)

        if !prefix.isEmpty {
          Text(prefix)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color(style.secondaryTextColorHex))
        }
      } else {
        Text(
          CalendarDateFormatter.string(
            from: event.startDate,
            calendar: calendar,
            dateFormat: "HH:mm"
          )
        )
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(color(style.eventTextColorHex))
      }

      if CalendarAgendaBuilder.isBirthdayEvent(event) {
        Text(birthdayIcon)
          .font(CalendarUIPrimitives.iconFont(size: 13))
          .foregroundStyle(color(birthdayIconColorHex ?? style.eventTextColorHex))
      }

      Text(event.title)
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(color(style.eventTextColorHex))
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private func appointmentMetaTopView(for event: CalendarAgentEvent) -> some View {
    if shouldShowAlertIcon(for: event) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(style.alertIcon)
          .font(CalendarUIPrimitives.iconFont(size: 10))
          .foregroundStyle(color(style.alertIconColorHex ?? style.travelTextColorHex))
        Text("Alert")
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(color(style.travelTextColorHex))
      }
    }
  }

  @ViewBuilder
  private func appointmentEndTimeView(for event: CalendarAgentEvent) -> some View {
    if !event.isAllDay {
      if style.showEndTime,
        let endTime = CalendarEventFormatter.endTimeText(
          startDate: event.startDate,
          endDate: event.endDate,
          isAllDay: event.isAllDay,
          calendar: calendar
        )
      {
        Text("until \(endTime)")
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(color(style.secondaryTextColorHex))
      }

      if style.showTravelTime,
        let travelTimeSeconds = event.travelTimeSeconds,
        let travelText = CalendarEventFormatter.travelTimeText(travelTimeSeconds: travelTimeSeconds)
      {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(style.travelIcon)
            .font(CalendarUIPrimitives.iconFont(size: 11))
            .foregroundStyle(color(style.travelIconColorHex ?? style.travelTextColorHex))
          Text(travelText)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(color(style.travelTextColorHex))
        }
      }
    }
  }

  private func appointmentPrefix(for event: CalendarAgentEvent) -> String {
    guard event.isAllDay else { return "" }
    guard !CalendarAgendaBuilder.isBirthdayEvent(event) else { return "" }
    guard !event.isHoliday || style.showHolidayAllDayLabel else { return "" }

    return style.showAllDayLabel ? style.allDayLabel : ""
  }

  private func shouldShowAlertIcon(for event: CalendarAgentEvent) -> Bool {
    guard style.showAlertIcon else { return false }
    guard event.hasAlert else { return false }
    guard !event.isAllDay else { return false }

    return true
  }

  private func indicatorColorHex(for event: CalendarAgentEvent) -> String {
    if let hex = event.calendarColorHex?.trimmingCharacters(in: .whitespacesAndNewlines),
      !hex.isEmpty
    {
      return hex
    }

    return defaultIndicatorColorHex
  }

  private func color(_ hex: String) -> Color {
    Color(calendarHex: hex)
  }
}
