import Foundation

extension CalendarBuiltinConfig {
  static func parseMonth(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Month
  ) throws -> CalendarBuiltinConfig.Month {
    CalendarBuiltinConfig.Month(
      popup: try parseMonthPopup(reader: try reader.section("popup"), fallback: fallback.popup)
    )
  }

  private static func parseMonthPopup(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Month.Popup
  ) throws -> CalendarBuiltinConfig.Month.Popup {
    CalendarBuiltinConfig.Month.Popup(
      style: try parseMonthPopupStyle(
        reader: try reader.section("style"),
        fallback: fallback.style
      ),
      calendar: try parseMonthPopupCalendar(
        reader: try reader.section("calendar"),
        fallback: fallback.calendar
      ),
      selection: try parseMonthPopupSelection(
        reader: try reader.section("selection"),
        fallback: fallback.selection
      ),
      agenda: try parseMonthPopupAgenda(
        reader: try reader.section("agenda"),
        fallback: fallback.agenda
      ),
      anchor: try parseMonthPopupAnchor(
        reader: try reader.section("anchor"),
        fallback: fallback.anchor
      ),
      todayButton: try parseMonthPopupTodayButton(
        reader: try reader.section("today_button"),
        fallback: fallback.todayButton
      )
    )
  }

  private static func parseMonthPopupStyle(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Month.Popup.Style
  ) throws -> CalendarBuiltinConfig.Month.Popup.Style {
    CalendarBuiltinConfig.Month.Popup.Style(
      backgroundColorHex: try reader.string(
        "background_color", fallback: fallback.backgroundColorHex),
      borderColorHex: try reader.string("border_color", fallback: fallback.borderColorHex),
      borderWidth: try reader.double("border_width", fallback: fallback.borderWidth, minimum: 0),
      cornerRadius: try reader.double("corner_radius", fallback: fallback.cornerRadius, minimum: 0),
      paddingX: try reader.double("padding_x", fallback: fallback.paddingX, minimum: 0),
      paddingY: try reader.double("padding_y", fallback: fallback.paddingY, minimum: 0),
      spacing: try reader.double("spacing", fallback: fallback.spacing, minimum: 0),
      marginX: try reader.double("margin_x", fallback: fallback.marginX),
      marginY: try reader.double("margin_y", fallback: fallback.marginY)
    )
  }

  private static func parseMonthPopupCalendar(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Month.Popup.CalendarStyle
  ) throws -> CalendarBuiltinConfig.Month.Popup.CalendarStyle {
    let weekdayFormat = try validatedMonthWeekdayFormat(
      try reader.string("weekday_format", fallback: fallback.weekdayFormat),
      path: reader.path(for: "weekday_format")
    )

    let weekdaySymbols = try validatedMonthWeekdaySymbols(
      try reader.optionalStringArray("weekday_symbols", fallback: fallback.weekdaySymbols),
      path: reader.path(for: "weekday_symbols")
    )

    let firstWeekday = try reader.optionalInt(
      "first_weekday",
      fallback: fallback.firstWeekday,
      minimum: 1,
      maximum: 7
    )

    let resolvedWeekdaySymbols = CalendarBuiltinConfig.resolveMonthWeekdaySymbols(
      format: weekdayFormat,
      manualSymbols: weekdaySymbols
    )

    return CalendarBuiltinConfig.Month.Popup.CalendarStyle(
      showWeekNumbers: try reader.bool("show_week_numbers", fallback: fallback.showWeekNumbers),
      showEventIndicators: try reader.bool(
        "show_event_indicators",
        fallback: fallback.showEventIndicators
      ),
      headerTextColorHex: try reader.string(
        "header_text_color", fallback: fallback.headerTextColorHex),
      weekdayTextColorHex: try reader.string(
        "weekday_text_color",
        fallback: fallback.weekdayTextColorHex
      ),
      firstWeekday: firstWeekday,
      weekdayFormat: weekdayFormat,
      weekdaySymbols: weekdaySymbols,
      resolvedWeekdaySymbols: resolvedWeekdaySymbols,
      dayTextColorHex: try reader.string("day_text_color", fallback: fallback.dayTextColorHex),
      outsideMonthTextColorHex: try reader.string(
        "outside_month_text_color",
        fallback: fallback.outsideMonthTextColorHex
      ),
      todayCellBackgroundColorHex: try reader.string(
        "today_cell_background_color",
        fallback: fallback.todayCellBackgroundColorHex
      ),
      todayCellBorderColorHex: try reader.string(
        "today_cell_border_color",
        fallback: fallback.todayCellBorderColorHex
      ),
      todayCellBorderWidth: try reader.double(
        "today_cell_border_width",
        fallback: fallback.todayCellBorderWidth,
        minimum: 0
      ),
      todayMarkerVariant: try reader.enum(
        "today_marker_variant",
        fallback: fallback.todayMarkerVariant
      ),
      todayMarkerSize: try reader.double(
        "today_marker_size",
        fallback: fallback.todayMarkerSize,
        minimum: 12,
        maximum: 28
      ),
      indicatorColorHex: try reader.string("indicator_color", fallback: fallback.indicatorColorHex)
    )
  }

  private static func parseMonthPopupSelection(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Month.Popup.SelectionStyle
  ) throws -> CalendarBuiltinConfig.Month.Popup.SelectionStyle {
    CalendarBuiltinConfig.Month.Popup.SelectionStyle(
      selectedTextColorHex: try reader.string(
        "selected_text_color",
        fallback: fallback.selectedTextColorHex
      ),
      selectedBackgroundColorHex: try reader.string(
        "selected_background_color",
        fallback: fallback.selectedBackgroundColorHex
      ),
      selectionDateFormat: try reader.string(
        "selection_date_format",
        fallback: fallback.selectionDateFormat
      ),
      selectionDateSeparator: try reader.string(
        "selection_date_separator",
        fallback: fallback.selectionDateSeparator
      ),
      allowsRangeSelection: try reader.bool(
        "allows_range_selection",
        fallback: fallback.allowsRangeSelection
      ),
      resetSelectionOnThirdTap: try reader.bool(
        "reset_selection_on_third_tap",
        fallback: fallback.resetSelectionOnThirdTap
      )
    )
  }

  private static func parseMonthPopupAgenda(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Month.Popup.AgendaStyle
  ) throws -> CalendarBuiltinConfig.Month.Popup.AgendaStyle {
    let minHeight = try reader.double(
      "appointments_min_height",
      fallback: fallback.appointmentsMinHeight,
      minimum: 0
    )
    let maxHeight = try reader.double(
      "appointments_max_height",
      fallback: fallback.appointmentsMaxHeight,
      minimum: 0
    )

    guard minHeight <= maxHeight else {
      throw CalendarConfigError.invalidValue(
        path: reader.path(for: "appointments_min_height"),
        message: "must be less than or equal to appointments_max_height"
      )
    }

    return CalendarBuiltinConfig.Month.Popup.AgendaStyle(
      layout: try reader.enum("layout", fallback: fallback.layout),
      appointmentsScrollable: try reader.bool(
        "appointments_scrollable",
        fallback: fallback.appointmentsScrollable
      ),
      appointmentsMinHeight: minHeight,
      appointmentsMaxHeight: maxHeight,
      agendaTitle: try reader.string("agenda_title", fallback: fallback.agendaTitle),
      maxVisibleAppointments: try reader.int(
        "max_visible_appointments",
        fallback: fallback.maxVisibleAppointments,
        minimum: 1
      )
    )
  }

  private static func parseMonthPopupAnchor(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Month.Popup.AnchorStyle
  ) throws -> CalendarBuiltinConfig.Month.Popup.AnchorStyle {
    CalendarBuiltinConfig.Month.Popup.AnchorStyle(
      dateFormat: try reader.string("date_format", fallback: fallback.dateFormat),
      textColorHex: try reader.optionalString("text_color", fallback: fallback.textColorHex),
      showDateText: try reader.bool("show_date_text", fallback: fallback.showDateText)
    )
  }

  private static func parseMonthPopupTodayButton(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Month.Popup.TodayButtonStyle
  ) throws -> CalendarBuiltinConfig.Month.Popup.TodayButtonStyle {
    CalendarBuiltinConfig.Month.Popup.TodayButtonStyle(
      title: try reader.string("title", fallback: fallback.title),
      icon: try reader.string("icon", fallback: fallback.icon),
      paddingX: try reader.double("padding_x", fallback: fallback.paddingX, minimum: 0),
      paddingY: try reader.double("padding_y", fallback: fallback.paddingY, minimum: 0),
      marginX: try reader.double("margin_x", fallback: fallback.marginX, minimum: 0),
      marginY: try reader.double("margin_y", fallback: fallback.marginY, minimum: 0)
    )
  }

  private static func validatedMonthWeekdayFormat(_ value: String, path: String) throws -> String {
    switch value {
    case "d", "dd", "ddd":
      return value
    case "dddd":
      throw CalendarConfigError.invalidValue(
        path: path,
        message:
          "dddd is not allowed because full weekday names are too wide; use d, dd, ddd, or weekday_symbols"
      )
    default:
      throw CalendarConfigError.invalidValue(path: path, message: "expected one of d, dd, or ddd")
    }
  }

  private static func validatedMonthWeekdaySymbols(_ value: [String]?, path: String) throws
    -> [String]?
  {
    guard let value else { return nil }

    guard value.count == 7 else {
      throw CalendarConfigError.invalidValue(
        path: path,
        message: "expected exactly 7 weekday symbols ordered Monday through Sunday"
      )
    }

    let trimmed = value.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard trimmed.allSatisfy({ !$0.isEmpty }) else {
      throw CalendarConfigError.invalidValue(
        path: path, message: "weekday symbols must not be empty")
    }

    return trimmed
  }
}
