import SwiftUI

extension CalendarMonthPopupView {
  /// Builds the popup month header.
  var headerView: some View {
    VStack(spacing: 10) {
      monthTitleRowView
      monthControlsRowView
    }
    .padding(.top, monthHeaderTopPadding)
  }

  /// Returns the top inset above the month title.
  var monthHeaderTopPadding: CGFloat {
    return 14
  }

  /// Shows the current month and selects today.
  func showToday() {
    let today = resolvedCalendar.startOfDay(for: nowProvider())
    let targetMonth = Self.startOfMonth(today, calendar: resolvedCalendar)
    visibleMonth = targetMonth
    selectedStartDate = today
    selectedEndDate = today

    logger.debug(
      "month calendar popup show_today",
      .field("visible_month", "\(debugDate(visibleMonth))"),
    )
  }

  /// Shows the previous visible month.
  func showPreviousMonth() {
    guard let newMonth = resolvedCalendar.date(byAdding: .month, value: -1, to: visibleMonth) else {
      return
    }

    let targetMonth = Self.startOfMonth(newMonth, calendar: resolvedCalendar)
    let targetSelectionDate = matchingSelectionDate(in: targetMonth)
    visibleMonth = targetMonth
    selectedStartDate = targetSelectionDate
    selectedEndDate = targetSelectionDate
    shouldAutoSelectVisibleMonthEvent = true

    logger.debug(
      "month calendar popup show_previous_month",
      .field("visible_month", "\(debugDate(visibleMonth))"),
    )
  }

  /// Shows the next visible month.
  func showNextMonth() {
    guard let newMonth = resolvedCalendar.date(byAdding: .month, value: 1, to: visibleMonth) else {
      return
    }

    let targetMonth = Self.startOfMonth(newMonth, calendar: resolvedCalendar)
    let targetSelectionDate = matchingSelectionDate(in: targetMonth)
    visibleMonth = targetMonth
    selectedStartDate = targetSelectionDate
    selectedEndDate = targetSelectionDate
    shouldAutoSelectVisibleMonthEvent = true

    logger.debug(
      "month calendar popup show_next_month",
      .field("visible_month", "\(debugDate(visibleMonth))"),
    )
  }

  private var monthTitleRowView: some View {
    HStack {
      Spacer()

      Button(action: openYearPicker) {
        HStack(spacing: 8) {
          Text(visibleMonthTitle)
            .font(.system(size: 18, weight: .semibold))
            .lineLimit(1)

          Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color(config.headerTextColorHex))
      }
      .buttonStyle(.plain)

      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var monthControlsRowView: some View {
    HStack(spacing: 18) {
      Button("Previous month", systemImage: "chevron.left", action: showPreviousMonth)
        .labelStyle(.iconOnly)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(color(config.headerTextColorHex))
        .frame(minWidth: 18)
        .buttonStyle(.plain)

      Button(action: showToday) {
        HStack(spacing: 4) {
          let icon = config.todayButtonIcon.trimmingCharacters(in: .whitespacesAndNewlines)

          if !icon.isEmpty {
            Text(icon)
              .font(CalendarUIPrimitives.iconFont(size: 11))
              .foregroundStyle(color(config.headerTextColorHex))
          }

          Text(config.todayButtonTitle)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color(config.headerTextColorHex))
        }
      }
      .buttonStyle(.plain)

      Button("Next month", systemImage: "chevron.right", action: showNextMonth)
        .labelStyle(.iconOnly)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(color(config.headerTextColorHex))
        .frame(minWidth: 18)
        .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }
}
