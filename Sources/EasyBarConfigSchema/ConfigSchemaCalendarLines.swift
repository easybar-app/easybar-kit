extension ConfigSchemaRegistry {
  static let calendarLines: [Line] = [
    section(name: "builtins.calendar"),
    entry(
      key: "enabled",
      value: "true",
      description: "Shows or hides the unified calendar widget.",
    ),
    entry(
      key: "position",
      value: "\"right\"",
      description: "Places the widget on the left, center, or right side of the bar.",
    ),
    entry(
      key: "order",
      value: "60",
      description: "Sort order among widgets in the same position.",
    ),
    entry(
      key: "popup_mode",
      value: "\"month\"",
      description: "Popup mode: none | upcoming | month.",
    ),
    .blank,
    section(name: "builtins.calendar.style"),
    entry(
      key: "icon",
      value: "\"\"",
      description: "Optional leading icon for the calendar anchor.",
    ),
    entry(
      key: "text_color",
      value: "\"theme.text\"",
      description: "Default text color of the anchor.",
    ),
    entry(
      key: "background_color",
      value: "\"theme.surface\"",
      description: "Background color of the anchor widget.",
    ),
    entry(
      key: "border_color",
      value: "\"theme.border\"",
      description: "Border color of the anchor widget.",
    ),
    entry(
      key: "border_width",
      value: "1",
      description: "Border width of the anchor widget.",
    ),
    entry(
      key: "corner_radius",
      value: "8",
      description: "Corner radius of the anchor widget.",
    ),
    entry(
      key: "margin_x",
      value: "0",
      description: "Horizontal outer margin around the anchor widget.",
    ),
    entry(
      key: "margin_y",
      value: "0",
      description: "Vertical outer margin around the anchor widget.",
    ),
    entry(
      key: "padding_x",
      value: "8",
      description: "Horizontal inner padding of the anchor widget.",
    ),
    entry(
      key: "padding_y",
      value: "4",
      description: "Vertical inner padding of the anchor widget.",
    ),
    entry(
      key: "spacing",
      value: "6",
      description: "Gap between anchor contents.",
    ),
    entry(
      key: "opacity",
      value: "1.0",
      description: "Overall opacity of the anchor widget.",
    ),
    .blank,
    section(name: "builtins.calendar.anchor"),
    entry(
      key: "layout",
      value: "\"row\"",
      description: "Field layout: row | column.",
    ),
    entry(
      key: "fields",
      value: "[\"date\", \"time\"]",
      description: "Ordered anchor fields: time and/or date.",
    ),
    optionalEntry(
      key: "spacing", value: "2", description: "Optional gap between configured fields."),
    entry(
      key: "separator",
      value: "\" \"",
      description: "Text inserted between fields in row layout.",
    ),
    .blank,
    section(name: "builtins.calendar.anchor.time"),
    entry(
      key: "format",
      value: "\"HH:mm\"",
      description: "DateFormatter pattern for the time field.",
    ),
    entry(
      key: "text_color",
      value: "\"theme.text\"",
      description: "Text color of the time field.",
    ),
    optionalEntry(key: "font_family", value: "\"SF Pro\"", description: "Optional font family."),
    optionalEntry(key: "font_size", value: "13", description: "Optional font size in points."),
    entry(
      key: "font_weight",
      value: "\"regular\"",
      description:
        "Font weight: ultralight | thin | light | regular | medium | semibold | bold | heavy | black.",
    ),
    .blank,
    section(name: "builtins.calendar.anchor.date"),
    entry(
      key: "format",
      value: "\"E, d. MMM\"",
      description: "DateFormatter pattern for the date field.",
    ),
    entry(
      key: "text_color",
      value: "\"theme.text_secondary\"",
      description: "Text color of the date field.",
    ),
    optionalEntry(key: "font_family", value: "\"SF Pro\"", description: "Optional font family."),
    optionalEntry(key: "font_size", value: "12", description: "Optional font size in points."),
    entry(
      key: "font_weight",
      value: "\"regular\"",
      description:
        "Font weight: ultralight | thin | light | regular | medium | semibold | bold | heavy | black.",
    ),
    .blank,
    section(name: "builtins.calendar.composer"),
    entry(
      key: "create_title",
      value: "\"New Appointment\"",
      description: "Panel title shown when creating an appointment.",
    ),
    entry(
      key: "edit_title",
      value: "\"Edit Appointment\"",
      description: "Panel title shown when editing an appointment.",
    ),
    entry(
      key: "title_label",
      value: "\"Title\"",
      description: "Label shown above the title field.",
    ),
    entry(
      key: "location_label",
      value: "\"Location\"",
      description: "Label shown above the location field.",
    ),
    entry(
      key: "calendar_label",
      value: "\"Calendar\"",
      description: "Label shown above the calendar picker.",
    ),
    entry(
      key: "start_label",
      value: "\"Begin\"",
      description: "Label shown for the start time.",
    ),
    entry(
      key: "end_label",
      value: "\"End\"",
      description: "Label shown for the end time.",
    ),
    entry(
      key: "all_day_label",
      value: "\"All day\"",
      description: "Label shown for all-day events.",
    ),
    entry(
      key: "travel_time_label",
      value: "\"Travel time\"",
      description: "Label shown for the travel-time picker.",
    ),
    entry(
      key: "alert_label",
      value: "\"Alert\"",
      description: "Label shown above the alerts section.",
    ),
    entry(
      key: "add_alert_label",
      value: "\"Add alert\"",
      description: "Button label used to add another alert row.",
    ),
    entry(
      key: "open_calendar_label",
      value: "\"Calendar\"",
      description: "Footer button label used to open Calendar.app.",
    ),
    entry(
      key: "cancel_label",
      value: "\"Cancel\"",
      description: "Footer cancel button label.",
    ),
    entry(
      key: "save_label",
      value: "\"Save\"",
      description: "Footer primary button label when creating.",
    ),
    entry(
      key: "update_label",
      value: "\"Update\"",
      description: "Footer primary button label when editing.",
    ),
    entry(
      key: "remove_label",
      value: "\"Remove\"",
      description: "Footer destructive button label.",
    ),
    entry(
      key: "delete_confirmation_title",
      value: "\"Remove appointment?\"",
      description: "Delete confirmation title.",
    ),
    entry(
      key: "delete_confirmation_message",
      value: "\"This action cannot be undone.\"",
      description: "Delete confirmation message.",
    ),
    entry(
      key: "title_placeholder",
      value: "\"What are you doing?\"",
      description: "Placeholder text for the composer title field.",
    ),
    entry(
      key: "location_placeholder",
      value: "\"Where are you going?\"",
      description: "Placeholder text for the composer location field.",
    ),
    entry(
      key: "default_calendar_name",
      value: "\"\"",
      description:
        "Default calendar name used when creating new appointments. Empty selects the first available writable calendar.",
    ),
    entry(
      key: "default_alert",
      value: "\"1_hour\"",
      description:
        "Default alert lead time: none | at_time | 5_minutes | 10_minutes | 15_minutes | 30_minutes | 1_hour | 1_day.",
    ),
    entry(
      key: "default_travel_time",
      value: "\"none\"",
      description:
        "Default travel time: none | 5_minutes | 10_minutes | 15_minutes | 20_minutes | 30_minutes | 45_minutes | 1_hour | 90_minutes | 2_hours.",
    ),
    .blank,
    section(name: "builtins.calendar.composer.style"),
    entry(
      key: "background_color",
      value: "\"theme.background\"",
      description: "Background color of the appointment composer panel.",
    ),
    entry(
      key: "border_color",
      value: "\"theme.border_strong\"",
      description: "Border and divider color of the appointment composer panel.",
    ),
    entry(
      key: "border_width",
      value: "1",
      description: "Border width of the appointment composer panel.",
    ),
    entry(
      key: "corner_radius",
      value: "10",
      description: "Corner radius of the appointment composer panel.",
    ),
    entry(
      key: "padding_x",
      value: "14",
      description: "Horizontal inner padding of the appointment composer panel.",
    ),
    entry(
      key: "padding_y",
      value: "14",
      description: "Vertical inner padding of the appointment composer panel.",
    ),
    entry(
      key: "header_text_color",
      value: "\"theme.text\"",
      description: "Header title color of the appointment composer panel.",
    ),
    .blank,
    .comment(
      "# Optional composer label overrides. Leave these commented to use the system language."),
    .comment("# Uncomment only the labels you want to override manually."),
    section(
      name: "builtins.calendar.composer.alert_labels",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "none",
      value: "\"None\"",
      description: "Label shown for no alert.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "at_time",
      value: "\"At time of event\"",
      description: "Label shown for alerts at event time.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "5_minutes",
      value: "\"5 minutes before\"",
      description: "Label shown for a 5-minute alert.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "10_minutes",
      value: "\"10 minutes before\"",
      description: "Label shown for a 10-minute alert.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "15_minutes",
      value: "\"15 minutes before\"",
      description: "Label shown for a 15-minute alert.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "30_minutes",
      value: "\"30 minutes before\"",
      description: "Label shown for a 30-minute alert.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "1_hour",
      value: "\"1 hour before\"",
      description: "Label shown for a 1-hour alert.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "1_day",
      value: "\"1 day before\"",
      description: "Label shown for a 1-day alert.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "custom",
      value: "\"Custom\"",
      description: "Label shown for a custom alert lead time.",
      commented: true,
      prefix: "#",
    ),
    .blank,
    section(
      name: "builtins.calendar.composer.travel_time_labels",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "none",
      value: "\"None\"",
      description: "Label shown when no travel time is set.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "5_minutes",
      value: "\"5 minutes\"",
      description: "Label shown for 5 minutes of travel time.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "10_minutes",
      value: "\"10 minutes\"",
      description: "Label shown for 10 minutes of travel time.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "15_minutes",
      value: "\"15 minutes\"",
      description: "Label shown for 15 minutes of travel time.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "20_minutes",
      value: "\"20 minutes\"",
      description: "Label shown for 20 minutes of travel time.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "30_minutes",
      value: "\"30 minutes\"",
      description: "Label shown for 30 minutes of travel time.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "45_minutes",
      value: "\"45 minutes\"",
      description: "Label shown for 45 minutes of travel time.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "1_hour",
      value: "\"1 hour\"",
      description: "Label shown for 1 hour of travel time.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "90_minutes",
      value: "\"1.5 hours\"",
      description: "Label shown for 90 minutes of travel time.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "2_hours",
      value: "\"2 hours\"",
      description: "Label shown for 2 hours of travel time.",
      commented: true,
      prefix: "#",
    ),
    entry(
      key: "custom",
      value: "\"Custom\"",
      description: "Label shown for a custom travel time.",
      commented: true,
      prefix: "#",
    ),
    .blank,
    section(name: "builtins.calendar.upcoming.events"),
    entry(
      key: "days",
      value: "3",
      description: "Number of days of upcoming events shown in the popup.",
    ),
    entry(
      key: "exclude_past_events",
      value: "false",
      description:
        "Hides already-finished or already-started items from today's section when true.",
    ),
    .blank,
    section(name: "builtins.calendar.upcoming.popup"),
    entry(
      key: "background_color",
      value: "\"theme.background\"",
      description: "Background color of the upcoming popup.",
    ),
    entry(
      key: "border_color",
      value: "\"theme.border_strong\"",
      description: "Border color of the upcoming popup.",
    ),
    entry(
      key: "border_width",
      value: "1",
      description: "Border width of the upcoming popup.",
    ),
    entry(
      key: "corner_radius",
      value: "10",
      description: "Corner radius of the upcoming popup.",
    ),
    entry(
      key: "padding_x",
      value: "10",
      description: "Horizontal inner padding of the upcoming popup.",
    ),
    entry(
      key: "padding_y",
      value: "8",
      description: "Vertical inner padding of the upcoming popup.",
    ),
    entry(
      key: "margin_x",
      value: "8",
      description: "Horizontal outer margin around the whole popup.",
    ),
    entry(
      key: "margin_y",
      value: "8",
      description: "Vertical outer margin around the whole popup.",
    ),
    entry(
      key: "spacing",
      value: "8",
      description: "Vertical spacing between popup sections.",
    ),
    .blank,
    section(name: "builtins.calendar.appointments"),
    entry(
      key: "item_indent",
      value: "8",
      description: "Left indent for appointment rows.",
    ),
    entry(
      key: "event_text_color",
      value: "\"theme.text_secondary\"",
      description: "Text color of appointment rows.",
    ),
    entry(
      key: "empty_text_color",
      value: "\"theme.text_tertiary\"",
      description: "Text color of the appointments empty state.",
    ),
    entry(
      key: "secondary_text_color",
      value: "\"theme.accent\"",
      description: "Text color of secondary appointment details and section headings.",
    ),
    entry(
      key: "travel_text_color",
      value: "\"theme.muted_secondary\"",
      description: "Muted text color used for travel-time and end-time rows.",
    ),
    entry(
      key: "empty_text",
      value: "\"No appointments\"",
      description: "Text shown when an appointment section has no events.",
    ),
    entry(
      key: "show_calendar_name",
      value: "false",
      description: "Shows the source calendar name for appointments.",
    ),
    entry(
      key: "show_all_day_label",
      value: "true",
      description: "Shows \"All day\" for all-day events except birthdays, which omit it.",
    ),
    entry(
      key: "show_holiday_all_day_label",
      value: "false",
      description: "Shows \"All day\" for all-day holiday-calendar events.",
    ),
    entry(
      key: "all_day_label",
      value: "\"All day\"",
      description: "Text shown for all-day events when show_all_day_label is true.",
    ),
    optionalEntry(
      key: "meeting_url_patterns",
      value:
        "[\"zoom.us\", \"meet.google.com\", \"teams.microsoft.com\", \"webex.com\", \"whereby.com\", \"jitsi\", \"gotomeeting.com\", \"bluejeans.com\"]",
      description:
        "Optional case-insensitive URL substrings used to label event links as Join Meeting. When omitted, the built-in list shown here is used; a configured list replaces it, and [] disables matching.",
    ),
    entry(
      key: "show_location",
      value: "true",
      description: "Shows the event location line when present.",
    ),
    entry(
      key: "location_icon",
      value: "\"\"",
      description: "Leading icon shown for location rows. Set to an empty string to hide the icon.",
    ),
    entry(
      key: "location_icon_color",
      value: "\"theme.accent\"",
      description: "Color of the location icon. When omitted, secondary_text_color is used.",
    ),
    entry(
      key: "show_travel_time",
      value: "true",
      description: "Shows the travel-time line when present.",
    ),
    entry(
      key: "show_end_time",
      value: "true",
      description: "Shows the end-time line for timed appointments.",
    ),
    entry(
      key: "travel_icon",
      value: "\"\"",
      description: "Leading icon shown for travel-time rows.",
    ),
    entry(
      key: "travel_icon_color",
      value: "\"theme.muted_secondary\"",
      description: "Color of the travel-time icon.",
    ),
    entry(
      key: "show_alert_icon",
      value: "false",
      description:
        "Shows a small alert icon on timed appointments with at least one non-travel alert.",
    ),
    entry(
      key: "alert_icon",
      value: "\"\"",
      description: "Optional icon shown when show_alert_icon is true and the event has an alert.",
    ),
    entry(
      key: "alert_icon_color",
      value: "\"theme.muted_secondary\"",
      description: "Color of the alert icon.",
    ),
    .blank,
    section(name: "builtins.calendar.birthdays"),
    entry(
      key: "show_birthdays",
      value: "true",
      description: "Includes birthday calendars in both month and upcoming appointment lists.",
    ),
    entry(
      key: "birthdays_show_age",
      value: "true",
      description: "Shows parsed ages for birthday appointments when available.",
    ),
    entry(
      key: "birthday_icon",
      value: "\"\"",
      description: "Leading icon shown for birthday appointments.",
    ),
    entry(
      key: "birthday_icon_color",
      value: "\"theme.accent_soft\"",
      description: "Color of the birthday icon. When omitted, event_text_color is used.",
    ),
    .blank,
    section(name: "builtins.calendar.filters"),
    entry(
      key: "included_calendar_names",
      value: "[]",
      description:
        "Optional allowlist of visible Calendar.app names. Empty means all calendars are eligible.",
    ),
    entry(
      key: "excluded_calendar_names",
      value: "[]",
      description: "Optional denylist of visible Calendar.app names applied after the allowlist.",
    ),
    entry(
      key: "included_calendar_source_names",
      value: "[]",
      description: "Optional allowlist of human-readable calendar source names.",
    ),
    entry(
      key: "excluded_calendar_source_names",
      value: "[]",
      description: "Optional denylist of human-readable calendar source names applied after the allowlist.",
    ),
    entry(
      key: "included_calendar_ids",
      value: "[]",
      description: "Optional advanced allowlist of exact calendar identifiers.",
    ),
    entry(
      key: "excluded_calendar_ids",
      value: "[]",
      description: "Optional advanced denylist of exact calendar identifiers.",
    ),
    entry(
      key: "included_calendar_source_ids",
      value: "[]",
      description: "Optional advanced allowlist of exact calendar source identifiers.",
    ),
    entry(
      key: "excluded_calendar_source_ids",
      value: "[]",
      description: "Optional advanced denylist of exact calendar source identifiers.",
    ),
    .blank,
    section(name: "builtins.calendar.month.popup.style"),
    entry(
      key: "background_color",
      value: "\"theme.background\"",
      description: "Background color of the month popup.",
    ),
    entry(
      key: "border_color",
      value: "\"theme.border_strong\"",
      description: "Border color of the month popup.",
    ),
    entry(
      key: "border_width",
      value: "1",
      description: "Border width of the month popup.",
    ),
    entry(
      key: "corner_radius",
      value: "14",
      description: "Corner radius of the month popup. Set to 0 for square corners.",
    ),
    entry(
      key: "padding_x",
      value: "10",
      description: "Horizontal inner padding of the month popup.",
    ),
    entry(
      key: "padding_y",
      value: "8",
      description: "Vertical inner padding of the month popup.",
    ),
    entry(
      key: "spacing",
      value: "8",
      description: "Gap between the calendar and appointments sections.",
    ),
    entry(
      key: "margin_x",
      value: "8",
      description: "Horizontal outer margin around the whole month popup.",
    ),
    entry(
      key: "margin_y",
      value: "8",
      description: "Vertical outer margin around the whole month popup.",
    ),
    .blank,
    section(name: "builtins.calendar.month.popup.calendar"),
    entry(
      key: "show_week_numbers",
      value: "true",
      description: "Shows week numbers in the calendar grid.",
    ),
    entry(
      key: "show_event_indicators",
      value: "true",
      description: "Shows dots under days that contain events.",
    ),
    entry(
      key: "header_text_color",
      value: "\"theme.text\"",
      description: "Text color of the month header and appointments title.",
    ),
    entry(
      key: "weekday_text_color",
      value: "\"theme.accent\"",
      description: "Text color of the weekday labels.",
    ),
    entry(
      key: "first_weekday",
      value: "2",
      description:
        "Optional first weekday override. 1 = Sunday, 2 = Monday, ... 7 = Saturday. When omitted, EasyBar uses the current calendar setting.",
      commented: true,
      prefix: "# ",
    ),
    entry(
      key: "weekday_format",
      value: "\"dd\"",
      description: "Weekday label format: d | dd | ddd. dddd is not allowed.",
    ),
    entry(
      key: "weekday_symbols",
      value: "[\"M\", \"T\", \"W\", \"T\", \"F\", \"S\", \"S\"]",
      description:
        "Optional custom weekday labels in Monday-first order. Must contain exactly 7 entries from Monday to Sunday.",
      commented: true,
      prefix: "# ",
    ),
    entry(
      key: "day_text_color",
      value: "\"theme.text_secondary\"",
      description: "Text color of days in the current month.",
    ),
    entry(
      key: "outside_month_text_color",
      value: "\"theme.outside_month\"",
      description: "Text color of leading and trailing days outside the current month.",
    ),
    entry(
      key: "today_cell_background_color",
      value: "\"theme.transparent\"",
      description: "Background color of today's day cell when it is not selected.",
    ),
    entry(
      key: "today_cell_border_color",
      value: "\"theme.danger\"",
      description: "Border color of today's day cell when it is not selected.",
    ),
    entry(
      key: "today_cell_border_width",
      value: "1.4",
      description: "Border width of today's day cell when it is not selected.",
    ),
    entry(
      key: "today_marker_variant",
      value: "\"double_sketch\"",
      description:
        "Today's marker style: regular_rounded_rectangle | soft_wobble | double_sketch | open_loop.",
    ),
    entry(
      key: "today_marker_size",
      value: "28",
      description: "Size of today's marker in points. Valid range: 12...28.",
    ),
    entry(
      key: "indicator_color",
      value: "\"theme.accent_soft\"",
      description: "Default color of day event indicators when an event has no calendar color.",
    ),
    .blank,
    section(name: "builtins.calendar.month.popup.selection"),
    entry(
      key: "selected_text_color",
      value: "\"theme.selection_text\"",
      description: "Text color of selected day cells.",
    ),
    entry(
      key: "selected_background_color",
      value: "\"theme.selection_background\"",
      description: "Background color of selected day cells.",
    ),
    entry(
      key: "selection_date_format",
      value: "\"yyyy-MM-dd\"",
      description: "Date header format used when a multi-day range is selected.",
    ),
    entry(
      key: "selection_date_separator",
      value: "\" - \"",
      description: "Separator used between start and end dates when a date range is selected.",
    ),
    entry(
      key: "allows_range_selection",
      value: "true",
      description: "Allows selecting a date range by dragging across days.",
    ),
    entry(
      key: "reset_selection_on_third_tap",
      value: "true",
      description: "Reserved selection behavior flag for the month popup.",
    ),
    .blank,
    section(name: "builtins.calendar.month.popup.agenda"),
    entry(
      key: "layout",
      value: "\"calendar_appointments_vertical\"",
      description:
        "Popup layout: calendar_appointments_horizontal | appointments_calendar_horizontal | calendar_appointments_vertical | appointments_calendar_vertical.",
    ),
    entry(
      key: "appointments_scrollable",
      value: "true",
      description: "Makes the appointments area scroll vertically when true.",
    ),
    entry(
      key: "appointments_min_height",
      value: "180",
      description:
        "Minimum height of the appointments area. Set equal to appointments_max_height for a fixed height.",
    ),
    entry(
      key: "appointments_max_height",
      value: "240",
      description:
        "Maximum height of the appointments area. Set equal to appointments_min_height for a fixed height.",
    ),
    entry(
      key: "agenda_title",
      value: "\"Appointments\"",
      description: "Title shown above the appointments list.",
    ),
    entry(
      key: "max_visible_appointments",
      value: "8",
      description: "Maximum number of visible appointments when scrolling is disabled.",
    ),
    .blank,
    section(name: "builtins.calendar.month.popup.anchor"),
    entry(
      key: "date_format",
      value: "\"EEE d MMM\"",
      description: "Date format used by the month popup agenda anchor.",
    ),
    entry(
      key: "text_color",
      value: "\"theme.text\"",
      description: "Text color used when popup_mode = \"month\".",
    ),
    entry(
      key: "show_date_text",
      value: "true",
      description: "Shows the date text when popup_mode = \"month\".",
    ),
    .blank,
    section(name: "builtins.calendar.month.popup.today_button"),
    entry(
      key: "title",
      value: "\"Today\"",
      description: "Title of the Today button.",
    ),
    entry(
      key: "padding_x",
      value: "7",
      description: "Horizontal inner padding of the Today button.",
    ),
    entry(
      key: "padding_y",
      value: "2",
      description: "Vertical inner padding of the Today button.",
    ),
    entry(
      key: "margin_x",
      value: "0",
      description: "Horizontal outer margin around the Today button.",
    ),
    entry(
      key: "margin_y",
      value: "0",
      description: "Vertical outer margin around the Today button.",
    ),
    entry(
      key: "icon",
      value: "\"\"",
      description: "Optional leading icon of the Today button, for example 󰃭.",
    ),
    .blank,
  ]
}
