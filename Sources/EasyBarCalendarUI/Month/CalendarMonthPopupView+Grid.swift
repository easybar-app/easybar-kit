import EasyBarShared
import SwiftUI

extension CalendarMonthPopupView {
  /// Builds the weekday header row.
  var weekdayHeaderView: some View {
    HStack(spacing: 6) {
      if config.showWeekNumbers {
        Color.clear
          .frame(width: 20)
      }

      ForEach(weekdaySymbols, id: \.self) { symbol in
        Text(symbol)
          .font(.system(size: 10, weight: .semibold))
          .frame(maxWidth: .infinity)
          .foregroundStyle(color(config.weekdayTextColorHex))
      }
    }
  }

  /// Returns the weekday symbols in calendar order.
  var weekdaySymbols: [String] {
    return reorderMondayFirstWeekdaySymbolsToCalendarOrder(config.resolvedWeekdaySymbols)
  }

  /// Reorders Monday-first weekday symbols into the current calendar order.
  func reorderMondayFirstWeekdaySymbolsToCalendarOrder(_ symbols: [String]) -> [String] {
    guard symbols.count == 7 else { return symbols }

    let mondayFirstIndex = mondayFirstWeekdayIndex(for: resolvedCalendar.firstWeekday)
    return Array(symbols[mondayFirstIndex...]) + Array(symbols[..<mondayFirstIndex])
  }

  /// Converts `Calendar.firstWeekday` into a Monday-first zero-based index.
  func mondayFirstWeekdayIndex(for firstWeekday: Int) -> Int {
    let normalized = ((firstWeekday - 1) % 7 + 7) % 7

    if normalized == 0 {
      return 6
    }

    return normalized - 1
  }

  /// Builds the visible month grid.
  var monthGridView: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(weekRows) { row in
        HStack(spacing: 6) {
          if config.showWeekNumbers {
            Text("\(row.weekNumber)")
              .font(.system(size: 10, weight: .medium))
              .frame(width: 20, alignment: .trailing)
              .foregroundStyle(color(config.outsideMonthTextColorHex))
          }

          ForEach(row.days) { day in
            dayCellView(day)
          }
        }
      }
    }
    .background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: MonthCalendarGridFramePreferenceKey.self,
          value: proxy.frame(in: .named("month-calendar-grid"))
        )
      }
    )
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          handleGridDragChanged(value)
        }
        .onEnded { value in
          handleGridDragEnded(value)
        }
    )
    .onPreferenceChange(MonthCalendarGridFramePreferenceKey.self) { frame in
      monthGridFrame = frame
    }
    .onPreferenceChange(MonthCalendarDayFramePreferenceKey.self) { frames in
      dayCellFrames = frames
    }
    .coordinateSpace(name: "month-calendar-grid")
  }

  /// Builds one interactive day cell.
  func dayCellView(_ day: DayCell) -> some View {
    let normalizedDate = resolvedCalendar.startOfDay(for: day.date)

    return VStack(spacing: 2) {
      Text("\(resolvedCalendar.component(.day, from: day.date))")
        .font(.system(size: 12, weight: fontWeight(for: day)))
        .frame(width: 28, height: 22)
        .background(dayBackground(day))
        .overlay {
          if resolvedCalendar.isDateInToday(day.date) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .inset(by: 1.5)
              .stroke(
                color(config.todayCellBorderColorHex).opacity(0.9),
                lineWidth: CGFloat(max(config.todayCellBorderWidth, 0.8))
              )
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

      dayIndicatorBar(for: day.date)
    }
    .frame(maxWidth: .infinity, minHeight: 30)
    .foregroundStyle(dayForeground(day))
    .contentShape(Rectangle())
    .background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: MonthCalendarDayFramePreferenceKey.self,
          value: [normalizedDate: proxy.frame(in: .named("month-calendar-grid"))]
        )
      }
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(day.date, format: .dateTime.weekday(.wide).month(.wide).day().year())
    )
    .accessibilityValue(Text(verbatim: dayAccessibilityValue(for: day)))
    .accessibilityHint("Selects this date")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction {
      selectDayForAccessibility(day.date)
    }
  }

  /// Returns the selection and event state announced for one day cell.
  func dayAccessibilityValue(for day: DayCell) -> String {
    var values: [String] = []

    if isSelected(day.date) {
      values.append("Selected")
    }

    if resolvedCalendar.isDateInToday(day.date) {
      values.append("Today")
    }

    let eventCount = store.eventsForDay(day.date).count
    if eventCount == 1 {
      values.append("1 event")
    } else if eventCount > 1 {
      values.append("\(eventCount) events")
    }

    return values.joined(separator: ", ")
  }

  /// Selects one day when an assistive technology activates its cell.
  func selectDayForAccessibility(_ date: Date) {
    let normalizedDate = resolvedCalendar.startOfDay(for: date)
    selectedStartDate = normalizedDate
    selectedEndDate = normalizedDate

    logger.debug(
      "month calendar popup accessibility_select",
      .field("date", "\(debugDate(normalizedDate))"),
    )
  }

  /// Returns the font weight for one day cell.
  func fontWeight(for day: DayCell) -> Font.Weight {
    if shouldEmphasizeDay(day.date) {
      return .semibold
    }

    return .medium
  }

  /// Returns whether the day should render with emphasized typography.
  func shouldEmphasizeDay(_ date: Date) -> Bool {
    return isSelected(date) || resolvedCalendar.isDateInToday(date)
  }

  /// Builds the appointment-indicator bar for one day.
  @ViewBuilder
  func dayIndicatorBar(for date: Date) -> some View {
    let segments = dayIndicatorSegments(for: date)

    if config.showEventIndicators, !segments.isEmpty {
      HStack(spacing: 1) {
        ForEach(segments) { segment in
          RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(color(segment.colorHex))
            .frame(
              width: max(1, floor(18 * segment.fraction)),
              height: 3
            )
        }
      }
      .frame(width: 18, height: 3, alignment: .center)
      .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
      .opacity(1)
    } else {
      RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        .fill(Color.clear)
        .frame(width: 18, height: 3)
        .opacity(0)
    }
  }

  /// Returns the per-calendar indicator segments for one day.
  func dayIndicatorSegments(for date: Date) -> [DayIndicatorSegment] {
    let events = store.eventsForDay(date)
    guard !events.isEmpty else { return [] }

    var countsByColor: [String: Int] = [:]
    var orderedColors: [String] = []

    for event in events {
      let colorHex = normalizedIndicatorColorHex(for: event)

      if countsByColor[colorHex] == nil {
        orderedColors.append(colorHex)
        countsByColor[colorHex] = 0
      }

      countsByColor[colorHex, default: 0] += 1
    }

    let total = max(1, countsByColor.values.reduce(0, +))

    return orderedColors.compactMap { colorHex in
      guard let count = countsByColor[colorHex], count > 0 else { return nil }

      return DayIndicatorSegment(
        id: "\(resolvedCalendar.startOfDay(for: date).timeIntervalSince1970)-\(colorHex)",
        colorHex: colorHex,
        fraction: CGFloat(count) / CGFloat(total)
      )
    }
  }

  /// Returns the indicator color for one event, falling back to the configured default.
  func normalizedIndicatorColorHex(for event: CalendarAgentEvent) -> String {
    if let hex = event.calendarColorHex?.trimmingCharacters(in: .whitespacesAndNewlines),
      !hex.isEmpty
    {
      return hex
    }

    return config.indicatorColorHex
  }

  /// Returns the computed week rows for the visible month.
  var weekRows: [WeekRow] {
    guard let monthRange = resolvedCalendar.dateInterval(of: .month, for: visibleMonth) else {
      return []
    }

    let firstWeekStart =
      resolvedCalendar.dateInterval(of: .weekOfMonth, for: monthRange.start)?.start
      ?? monthRange.start

    let lastVisibleDay =
      resolvedCalendar.date(byAdding: .day, value: -1, to: monthRange.end)
      ?? monthRange.end

    let lastWeekEnd =
      resolvedCalendar.dateInterval(of: .weekOfMonth, for: lastVisibleDay)?.end
      ?? monthRange.end

    var rows: [WeekRow] = []
    var currentWeekStart = firstWeekStart

    while currentWeekStart < lastWeekEnd {
      let weekNumber = resolvedCalendar.component(.weekOfYear, from: currentWeekStart)

      let days = (0..<7).compactMap { offset -> DayCell? in
        guard let date = resolvedCalendar.date(byAdding: .day, value: offset, to: currentWeekStart)
        else {
          return nil
        }

        return DayCell(
          id: "\(resolvedCalendar.startOfDay(for: date).timeIntervalSince1970)",
          date: date,
          isCurrentMonth: resolvedCalendar.isDate(
            date,
            equalTo: visibleMonth,
            toGranularity: .month
          )
        )
      }

      rows.append(
        WeekRow(
          id: "\(resolvedCalendar.startOfDay(for: currentWeekStart).timeIntervalSince1970)",
          weekStartDate: currentWeekStart,
          weekNumber: weekNumber,
          days: days
        )
      )

      guard let nextWeek = resolvedCalendar.date(byAdding: .day, value: 7, to: currentWeekStart)
      else {
        break
      }

      currentWeekStart = nextWeek
    }

    return rows
  }
}
