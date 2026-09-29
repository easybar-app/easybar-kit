import Foundation

extension CalendarBuiltinConfig {
  /// Parses composer.
  static func parseComposer(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Composer
  ) throws -> CalendarBuiltinConfig.Composer {
    CalendarBuiltinConfig.Composer(
      style: try parseComposerStyle(reader: try reader.section("style"), fallback: fallback.style),
      content: try parseComposerContent(reader: reader, fallback: fallback.content)
    )
  }

  /// Parses composer style.
  private static func parseComposerStyle(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Composer.Style
  ) throws -> CalendarBuiltinConfig.Composer.Style {
    CalendarBuiltinConfig.Composer.Style(
      backgroundColorHex: try reader.string(
        "background_color", fallback: fallback.backgroundColorHex),
      borderColorHex: try reader.string("border_color", fallback: fallback.borderColorHex),
      borderWidth: try reader.double("border_width", fallback: fallback.borderWidth, minimum: 0),
      cornerRadius: try reader.double("corner_radius", fallback: fallback.cornerRadius, minimum: 0),
      paddingX: try reader.double("padding_x", fallback: fallback.paddingX, minimum: 0),
      paddingY: try reader.double("padding_y", fallback: fallback.paddingY, minimum: 0),
      headerTextColorHex: try reader.string(
        "header_text_color", fallback: fallback.headerTextColorHex)
    )
  }

  /// Parses composer content.
  private static func parseComposerContent(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Composer.Content
  ) throws -> CalendarBuiltinConfig.Composer.Content {
    CalendarBuiltinConfig.Composer.Content(
      createTitle: try reader.string("create_title", fallback: fallback.createTitle),
      editTitle: try reader.string("edit_title", fallback: fallback.editTitle),
      titleLabel: try reader.string("title_label", fallback: fallback.titleLabel),
      locationLabel: try reader.string("location_label", fallback: fallback.locationLabel),
      calendarLabel: try reader.string("calendar_label", fallback: fallback.calendarLabel),
      titlePlaceholder: try reader.string("title_placeholder", fallback: fallback.titlePlaceholder),
      locationPlaceholder: try reader.string(
        "location_placeholder",
        fallback: fallback.locationPlaceholder
      ),
      defaultCalendarName: try reader.optionalString(
        "default_calendar_name",
        fallback: fallback.defaultCalendarName
      ),
      defaultAlert: try reader.string("default_alert", fallback: fallback.defaultAlert),
      defaultTravelTime: try reader.string(
        "default_travel_time", fallback: fallback.defaultTravelTime),
      alertLabels: try parseOptionLabels(
        reader: try reader.optionalSection("alert_labels"),
        fallback: fallback.alertLabels
      ),
      travelTimeLabels: try parseOptionLabels(
        reader: try reader.optionalSection("travel_time_labels"),
        fallback: fallback.travelTimeLabels
      ),
      startLabel: try reader.string("start_label", fallback: fallback.startLabel),
      endLabel: try reader.string("end_label", fallback: fallback.endLabel),
      allDayLabel: try reader.string("all_day_label", fallback: fallback.allDayLabel),
      travelTimeLabel: try reader.string("travel_time_label", fallback: fallback.travelTimeLabel),
      alertLabel: try reader.string("alert_label", fallback: fallback.alertLabel),
      addAlertLabel: try reader.string("add_alert_label", fallback: fallback.addAlertLabel),
      openCalendarLabel: try reader.string(
        "open_calendar_label", fallback: fallback.openCalendarLabel),
      cancelLabel: try reader.string("cancel_label", fallback: fallback.cancelLabel),
      saveLabel: try reader.string("save_label", fallback: fallback.saveLabel),
      updateLabel: try reader.string("update_label", fallback: fallback.updateLabel),
      removeLabel: try reader.string("remove_label", fallback: fallback.removeLabel),
      deleteConfirmationTitle: try reader.string(
        "delete_confirmation_title",
        fallback: fallback.deleteConfirmationTitle
      ),
      deleteConfirmationMessage: try reader.string(
        "delete_confirmation_message",
        fallback: fallback.deleteConfirmationMessage
      )
    )
  }

  /// Parses option labels.
  private static func parseOptionLabels(
    reader: Reader?,
    fallback: [String: String]
  ) throws -> [String: String] {
    guard let reader else { return fallback }
    return try reader.stringTable(fallback: fallback)
  }
}
