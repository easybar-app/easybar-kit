import EasyBarShared
import Foundation
import SwiftTOMLEdit

extension CalendarPopupMode: TOMLStringDecodable {
  public static let allowedValues = allCases.map(\.rawValue)
}

extension CalendarMonthPopupLayout: TOMLStringDecodable {
  public static let allowedValues = allCases.map(\.rawValue)
}

extension CalendarTodayMarkerVariant: TOMLStringDecodable {
  public static let allowedValues = allCases.map(\.rawValue)
}

extension CalendarAnchorLayout: TOMLStringDecodable {
  public static let allowedValues = allCases.map(\.rawValue)
}

extension CalendarAnchorFieldKind: TOMLStringDecodable {
  public static let allowedValues = allCases.map(\.rawValue)
}

extension CalendarAnchorFontWeight: TOMLStringDecodable {
  public static let allowedValues = allCases.map(\.rawValue)
}

extension CalendarBuiltinConfig {
  typealias Reader = TOMLConfigReader<CalendarConfigError>

  /// Parses the reusable calendar config from one TOML table.
  public static func parse(
    from table: TOMLTable,
    fallback: CalendarBuiltinConfig = .default,
    path: String = "calendar"
  ) throws -> CalendarBuiltinConfig {
    let reader = calendarReader(table: table, path: path)

    return CalendarBuiltinConfig(
      placement: try parsePlacement(reader: reader, fallback: fallback.placement),
      style: try parseWidgetStyle(reader: try reader.section("style"), fallback: fallback.style),
      popupMode: try reader.enum("popup_mode", fallback: fallback.popupMode),
      anchor: try parseAnchor(reader: try reader.section("anchor"), fallback: fallback.anchor),
      filters: try parseFilters(reader: try reader.section("filters"), fallback: fallback.filters),
      appointments: try parseAppointments(
        reader: try reader.section("appointments"),
        fallback: fallback.appointments
      ),
      birthdays: try parseBirthdays(
        reader: try reader.section("birthdays"),
        fallback: fallback.birthdays
      ),
      composer: try parseComposer(
        reader: try reader.section("composer"), fallback: fallback.composer),
      upcoming: try parseUpcoming(
        reader: try reader.section("upcoming"), fallback: fallback.upcoming),
      month: try parseMonth(reader: try reader.section("month"), fallback: fallback.month)
    )
  }

  private static func calendarReader(table: TOMLTable, path: String) -> Reader {
    Reader(
      table: table,
      path: path,
      makeInvalidTypeError: CalendarConfigError.invalidType,
      makeInvalidValueError: CalendarConfigError.invalidValue
    )
  }

  private static func parsePlacement(
    reader: Reader,
    fallback: CalendarWidgetPlacement
  ) throws -> CalendarWidgetPlacement {
    CalendarWidgetPlacement(
      enabled: try reader.bool("enabled", fallback: fallback.enabled),
      position: try reader.enum("position", fallback: fallback.position),
      order: try reader.int("order", fallback: fallback.order),
      group: try reader.optionalString("group", fallback: fallback.group)
    )
  }

  private static func parseWidgetStyle(
    reader: Reader,
    fallback: CalendarWidgetStyle
  ) throws -> CalendarWidgetStyle {
    CalendarWidgetStyle(
      icon: try reader.string("icon", fallback: fallback.icon),
      textColorHex: try reader.optionalString("text_color", fallback: fallback.textColorHex),
      backgroundColorHex: try reader.optionalString(
        "background_color",
        fallback: fallback.backgroundColorHex
      ),
      borderColorHex: try reader.optionalString("border_color", fallback: fallback.borderColorHex),
      borderWidth: try reader.double("border_width", fallback: fallback.borderWidth, minimum: 0),
      cornerRadius: try reader.double("corner_radius", fallback: fallback.cornerRadius, minimum: 0),
      marginX: try reader.double("margin_x", fallback: fallback.marginX),
      marginY: try reader.double("margin_y", fallback: fallback.marginY),
      paddingX: try reader.double("padding_x", fallback: fallback.paddingX, minimum: 0),
      paddingY: try reader.double("padding_y", fallback: fallback.paddingY, minimum: 0),
      spacing: try reader.double("spacing", fallback: fallback.spacing, minimum: 0),
      opacity: try reader.double("opacity", fallback: fallback.opacity, minimum: 0, maximum: 1)
    )
  }

  private static func parseAnchor(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Anchor
  ) throws -> CalendarBuiltinConfig.Anchor {
    CalendarBuiltinConfig.Anchor(
      layout: try reader.enum("layout", fallback: fallback.layout),
      fields: try reader.enumArray("fields", fallback: fallback.fields),
      spacing: try reader.double("spacing", fallback: fallback.spacing, minimum: 0),
      separator: try reader.string("separator", fallback: fallback.separator),
      time: try parseAnchorField(
        reader: try reader.section("time"), fallback: fallback.time),
      date: try parseAnchorField(
        reader: try reader.section("date"), fallback: fallback.date)
    )
  }

  private static func parseAnchorField(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Anchor.Field
  ) throws -> CalendarBuiltinConfig.Anchor.Field {
    CalendarBuiltinConfig.Anchor.Field(
      format: try reader.string("format", fallback: fallback.format),
      textColorHex: try reader.optionalString("text_color", fallback: fallback.textColorHex),
      fontFamily: try reader.optionalString("font_family", fallback: fallback.fontFamily),
      fontSize: try reader.optionalDouble("font_size", fallback: fallback.fontSize, minimum: 1),
      fontWeight: try reader.enum("font_weight", fallback: fallback.fontWeight)
    )
  }

  private static func parseFilters(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Filters
  ) throws -> CalendarBuiltinConfig.Filters {
    CalendarBuiltinConfig.Filters(
      includedCalendarNames: try reader.stringArray(
        "included_calendar_names",
        fallback: fallback.includedCalendarNames
      ),
      excludedCalendarNames: try reader.stringArray(
        "excluded_calendar_names",
        fallback: fallback.excludedCalendarNames
      ),
      includedCalendarIDs: try reader.stringArray(
        "included_calendar_ids",
        fallback: fallback.includedCalendarIDs
      ),
      excludedCalendarIDs: try reader.stringArray(
        "excluded_calendar_ids",
        fallback: fallback.excludedCalendarIDs
      ),
      includedCalendarSourceIDs: try reader.stringArray(
        "included_calendar_source_ids",
        fallback: fallback.includedCalendarSourceIDs
      ),
      excludedCalendarSourceIDs: try reader.stringArray(
        "excluded_calendar_source_ids",
        fallback: fallback.excludedCalendarSourceIDs
      )
    )
  }

  private static func parseAppointments(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Appointments
  ) throws -> CalendarBuiltinConfig.Appointments {
    CalendarBuiltinConfig.Appointments(
      itemIndent: try reader.double("item_indent", fallback: fallback.itemIndent, minimum: 0),
      eventTextColorHex: try reader.string(
        "event_text_color", fallback: fallback.eventTextColorHex),
      emptyTextColorHex: try reader.string(
        "empty_text_color", fallback: fallback.emptyTextColorHex),
      secondaryTextColorHex: try reader.string(
        "secondary_text_color",
        fallback: fallback.secondaryTextColorHex
      ),
      travelTextColorHex: try reader.string(
        "travel_text_color", fallback: fallback.travelTextColorHex),
      emptyText: try reader.string("empty_text", fallback: fallback.emptyText),
      showCalendarName: try reader.bool("show_calendar_name", fallback: fallback.showCalendarName),
      showAllDayLabel: try reader.bool("show_all_day_label", fallback: fallback.showAllDayLabel),
      showHolidayAllDayLabel: try reader.bool(
        "show_holiday_all_day_label",
        fallback: fallback.showHolidayAllDayLabel
      ),
      allDayLabel: try reader.string("all_day_label", fallback: fallback.allDayLabel),
      meetingURLPatterns: CalendarMeetingURLMatcher.normalizedPatterns(
        try reader.stringArray(
          "meeting_url_patterns",
          fallback: fallback.meetingURLPatterns
        )
      ),
      showLocation: try reader.bool("show_location", fallback: fallback.showLocation),
      locationIcon: try reader.string("location_icon", fallback: fallback.locationIcon),
      locationIconColorHex: try reader.optionalString(
        "location_icon_color",
        fallback: fallback.locationIconColorHex
      ),
      showTravelTime: try reader.bool("show_travel_time", fallback: fallback.showTravelTime),
      showEndTime: try reader.bool("show_end_time", fallback: fallback.showEndTime),
      travelIcon: try reader.string("travel_icon", fallback: fallback.travelIcon),
      travelIconColorHex: try reader.optionalString(
        "travel_icon_color",
        fallback: fallback.travelIconColorHex
      ),
      showAlertIcon: try reader.bool("show_alert_icon", fallback: fallback.showAlertIcon),
      alertIcon: try reader.string("alert_icon", fallback: fallback.alertIcon),
      alertIconColorHex: try reader.optionalString(
        "alert_icon_color",
        fallback: fallback.alertIconColorHex
      )
    )
  }

  private static func parseBirthdays(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Birthdays
  ) throws -> CalendarBuiltinConfig.Birthdays {
    CalendarBuiltinConfig.Birthdays(
      showBirthdays: try reader.bool("show_birthdays", fallback: fallback.showBirthdays),
      birthdaysShowAge: try reader.bool("birthdays_show_age", fallback: fallback.birthdaysShowAge),
      birthdayIcon: try reader.string("birthday_icon", fallback: fallback.birthdayIcon),
      birthdayIconColorHex: try reader.optionalString(
        "birthday_icon_color",
        fallback: fallback.birthdayIconColorHex
      )
    )
  }

}
