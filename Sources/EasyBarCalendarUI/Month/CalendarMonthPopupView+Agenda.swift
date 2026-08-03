import EasyBarCalendarPresentation
import EasyBarShared
import SwiftUI

// MARK: - Selection And Agenda

extension CalendarMonthPopupView {
  /// Builds the appointments container, optionally scrollable.
  @ViewBuilder
  var appointmentsContainerView: some View {
    VStack(alignment: .leading, spacing: 8) {
      appointmentsHeaderView

      if config.appointmentsScrollable {
        ScrollView(.vertical, showsIndicators: true) {
          appointmentsContentView
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(
          maxWidth: .infinity,
          minHeight: appointmentsScrollableHeight,
          idealHeight: appointmentsScrollableHeight,
          maxHeight: appointmentsScrollableHeight,
          alignment: .topLeading
        )
        .clipped()
      } else {
        appointmentsContentView
          .frame(
            maxWidth: .infinity,
            minHeight: appointmentsMinHeight,
            maxHeight: appointmentsMaxHeight,
            alignment: .topLeading
          )
      }
    }
  }

  /// Builds the appointments header row with section title and create action.
  var appointmentsHeaderView: some View {
    HStack(alignment: .center, spacing: 10) {
      Text(config.agendaTitle)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(color(config.headerTextColorHex))

      Spacer()

      Button("Create event", systemImage: "plus", action: openComposer)
        .labelStyle(.iconOnly)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(color(config.headerTextColorHex))
        .frame(width: 24, height: 24)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(0.05))
        )
        .overlay {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(color(config.borderColorHex).opacity(0.8), lineWidth: 1)
        }
        .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, agendaTitleTopPadding)
  }

  /// Builds the selected appointments content.
  @ViewBuilder
  var appointmentsContentView: some View {
    CalendarAppointmentsListView(
      title: nil,
      rows: appointmentListRows,
      emptyText: emptyText,
      style: appointmentsStyle,
      birthdayIcon: birthdays.birthdayIcon,
      birthdayIconColorHex: birthdays.birthdayIconColorHex,
      defaultIndicatorColorHex: config.indicatorColorHex,
      calendar: resolvedCalendar,
      dateHeaderText: formattedSelectionDate,
      eventActions: eventActions,
      onEventTap: { event in
        openComposer(for: event)
      }
    )
  }

  /// Returns the extra top padding for the agenda title in vertical layouts.
  var agendaTitleTopPadding: CGFloat {
    switch config.layout {
    case .calendarAppointmentsVertical, .appointmentsCalendarVertical:
      return 2
    case .calendarAppointmentsHorizontal, .appointmentsCalendarHorizontal:
      return 0
    }
  }

  /// Returns the shared appointment rows rendered in the month popup.
  var appointmentListRows: [CalendarAppointmentsListRow] {
    visibleAgendaRows.map { row in
      switch row.kind {
      case .dayHeader(let date):
        return CalendarAppointmentsListRow(
          id: row.id,
          kind: .dayHeader(date)
        )
      case .event(let event):
        return CalendarAppointmentsListRow(
          id: row.id,
          kind: .event(event)
        )
      }
    }
  }

  /// Returns the currently selected events.
  var selectedEvents: [CalendarAgentEvent] {
    store.eventsInRange(from: selectedStartDate, to: selectedEndDate)
      .sorted { lhs, rhs in
        let lhsDate = displayDate(for: lhs)
        let rhsDate = displayDate(for: rhs)

        if lhsDate != rhsDate {
          return lhsDate < rhsDate
        }

        return CalendarAgendaBuilder.eventSortOrder(lhs: lhs, rhs: rhs)
      }
  }

  /// Returns the visible agenda rows, grouped by date for multi-day selections.
  var visibleAgendaRows: [AgendaRow] {
    let rows = agendaRows

    guard !config.appointmentsScrollable else {
      return rows
    }

    return CalendarAgendaBuilder.limitedVisibleEntries(
      rows,
      maxVisibleEvents: config.maxVisibleAppointments
    )
  }

  /// Returns all agenda rows for the current selection.
  var agendaRows: [AgendaRow] {
    return CalendarAgendaBuilder.build(
      events: selectedEvents,
      selectionSpansMultipleDays: selectionSpansMultipleDays,
      calendar: resolvedCalendar,
      displayedDate: { event in
        displayDate(for: event)
      }
    )
  }

  /// Starts one pointer interaction.
  func beginPointerInteraction(on date: Date) {
    isDragSelecting = true
    dragAnchorDate = date
    dragDidCrossIntoAnotherDay = false
    lastResolvedDragDate = date

    logger.debug(
      "month calendar popup pointer_begin",
      .field("date", "\(debugDate(date))"),
    )
  }

  /// Updates the current drag selection.
  func updateDragSelection(to date: Date) {
    guard let dragAnchorDate else { return }

    if date != dragAnchorDate {
      dragDidCrossIntoAnotherDay = true
    }

    guard lastResolvedDragDate != date else { return }
    lastResolvedDragDate = date

    selectedStartDate = min(dragAnchorDate, date)
    selectedEndDate = max(dragAnchorDate, date)

    logger.debug(
      "month calendar popup drag_update",
      .field("anchor", "\(debugDate(dragAnchorDate))"),
      .field("current", "\(debugDate(date))"),
      .field("start", "\(debugDate(selectedStartDate))"),
      .field("end", "\(debugDate(selectedEndDate))"),
    )
  }

  /// Handles one grid drag change.
  func handleGridDragChanged(_ value: DragGesture.Value) {
    let startLocation = value.startLocation
    let currentLocation = value.location

    guard let startDate = resolvedDay(at: startLocation) else { return }

    if !isDragSelecting {
      beginPointerInteraction(on: startDate)
      selectedStartDate = startDate
      selectedEndDate = startDate
    }

    guard config.allowsRangeSelection else { return }
    guard let currentDate = resolvedDay(at: currentLocation) else { return }

    updateDragSelection(to: currentDate)
  }

  /// Handles one grid drag end.
  func handleGridDragEnded(_ value: DragGesture.Value, clickCount: Int) {
    defer {
      isDragSelecting = false
      dragAnchorDate = nil
      lastResolvedDragDate = nil
      dragDidCrossIntoAnotherDay = false
    }

    guard let startDate = resolvedDay(at: value.startLocation) else { return }
    let endDate = resolvedDay(at: value.location) ?? startDate
    let shouldOpenComposer = shouldOpenComposerAfterGridInteraction(
      clickCount: clickCount,
      startDate: startDate,
      endDate: endDate,
      didCrossIntoAnotherDay: dragDidCrossIntoAnotherDay
    )

    if shouldCollapseDragSelection(startDate: startDate, endDate: endDate) {
      selectedStartDate = startDate
      selectedEndDate = startDate
      logger.debug(
        "month calendar popup click_select",
        .field("date", "\(debugDate(startDate))"),
      )

      if shouldOpenComposer {
        openComposer(on: startDate)
      }

      return
    }

    selectedStartDate = min(startDate, endDate)
    selectedEndDate = max(startDate, endDate)

    logger.debug(
      "month calendar popup drag_end",
      .field("start", "\(debugDate(selectedStartDate))"),
      .field("end", "\(debugDate(selectedEndDate))"),
    )
  }

  /// Returns whether the finished drag should collapse back to a single selected day.
  func shouldCollapseDragSelection(startDate: Date, endDate: Date) -> Bool {
    return !dragDidCrossIntoAnotherDay || startDate == endDate
  }

  /// Returns whether a completed pointer interaction is an unambiguous date double-click.
  func shouldOpenComposerAfterGridInteraction(
    clickCount: Int,
    startDate: Date,
    endDate: Date,
    didCrossIntoAnotherDay: Bool
  ) -> Bool {
    clickCount == 2
      && !didCrossIntoAnotherDay
      && startDate == endDate
  }

  /// Formats one grouped selection date header.
  func formattedSelectionDate(_ date: Date) -> String {
    CalendarDateFormatter.string(
      from: date,
      calendar: resolvedCalendar,
      dateFormat: config.selectionDateFormat
    )
  }

  /// Returns whether the active selection spans more than one day.
  var selectionSpansMultipleDays: Bool {
    resolvedCalendar.startOfDay(for: selectedStartDate)
      != resolvedCalendar.startOfDay(for: selectedEndDate)
  }

  /// Returns the display date used to group one event in the agenda.
  func displayDate(for event: CalendarAgentEvent) -> Date {
    let eventStartDay = resolvedCalendar.startOfDay(for: event.startDate)
    let selectionStartDay = resolvedCalendar.startOfDay(
      for: min(selectedStartDate, selectedEndDate))
    return max(eventStartDay, selectionStartDay)
  }
}
