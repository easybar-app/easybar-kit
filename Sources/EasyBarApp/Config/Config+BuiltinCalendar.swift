import EasyBarCalendarConfig

extension Config {
  /// Parses the built-in calendar widget.
  func parseCalendarBuiltin(from builtins: ConfigReader) throws {
    guard let calendar = try builtins.optionalSection("calendar") else { return }

    do {
      builtinCalendar = try CalendarBuiltinConfig.parse(
        from: calendar.rawTable,
        fallback: builtinCalendar,
        path: "builtins.calendar"
      ).resolvingThemeColorReferences { [self] value, path in
        try resolvedConfigColor(value, path: path)
      }
    } catch let error as CalendarConfigError {
      throw error.asConfigError
    }
  }
}

extension CalendarConfigError {
  fileprivate var asConfigError: ConfigError {
    switch self {
    case .invalidType(let path, let expected, let actual):
      return .invalidType(path: path, expected: expected, actual: actual)
    case .invalidValue(let path, let message):
      return .invalidValue(path: path, message: message)
    }
  }
}

/// Resolves one calendar color reference and writes the validated concrete value back.
private struct CalendarColorReferenceResolver {
  let resolve: (String, String) throws -> String

  /// Resolves a required color value in place.
  func required(_ value: inout String, path: String) throws {
    value = try resolve(value, path)
  }

  /// Resolves an optional color value in place.
  func optional(_ value: inout String?, path: String) throws {
    guard let current = value else { return }
    value = try resolve(current, path)
  }
}

extension CalendarBuiltinConfig {
  /// Returns a copy with all calendar color references validated and resolved to concrete hex values.
  fileprivate func resolvingThemeColorReferences(
    using resolve: @escaping (String, String) throws -> String
  ) throws -> CalendarBuiltinConfig {
    var config = self
    let resolver = CalendarColorReferenceResolver(resolve: resolve)

    try config.resolveRootColors(using: resolver)
    try config.resolveAnchorColors(using: resolver)
    try config.resolveAppointmentColors(using: resolver)
    try config.resolveBirthdayColors(using: resolver)
    try config.resolveComposerColors(using: resolver)
    try config.resolveUpcomingColors(using: resolver)
    try config.resolveMonthColors(using: resolver)

    return config
  }

  /// Resolves top-level calendar widget colors.
  private mutating func resolveRootColors(using resolver: CalendarColorReferenceResolver) throws {
    try resolver.optional(
      &style.textColorHex,
      path: "builtins.calendar.style.text_color"
    )
    try resolver.optional(
      &style.backgroundColorHex,
      path: "builtins.calendar.style.background_color"
    )
    try resolver.optional(
      &style.borderColorHex,
      path: "builtins.calendar.style.border_color"
    )
  }

  /// Resolves calendar anchor colors.
  private mutating func resolveAnchorColors(using resolver: CalendarColorReferenceResolver) throws {
    try resolver.optional(
      &anchor.time.textColorHex,
      path: "builtins.calendar.anchor.time.text_color"
    )
    try resolver.optional(
      &anchor.date.textColorHex,
      path: "builtins.calendar.anchor.date.text_color"
    )
  }

  /// Resolves appointment row colors.
  private mutating func resolveAppointmentColors(
    using resolver: CalendarColorReferenceResolver
  ) throws {
    try resolver.required(
      &appointments.eventTextColorHex,
      path: "builtins.calendar.appointments.event_text_color"
    )
    try resolver.required(
      &appointments.emptyTextColorHex,
      path: "builtins.calendar.appointments.empty_text_color"
    )
    try resolver.required(
      &appointments.secondaryTextColorHex,
      path: "builtins.calendar.appointments.secondary_text_color"
    )
    try resolver.required(
      &appointments.travelTextColorHex,
      path: "builtins.calendar.appointments.travel_text_color"
    )
    try resolver.optional(
      &appointments.locationIconColorHex,
      path: "builtins.calendar.appointments.location_icon_color"
    )
    try resolver.optional(
      &appointments.travelIconColorHex,
      path: "builtins.calendar.appointments.travel_icon_color"
    )
    try resolver.optional(
      &appointments.alertIconColorHex,
      path: "builtins.calendar.appointments.alert_icon_color"
    )
  }

  /// Resolves birthday row colors.
  private mutating func resolveBirthdayColors(using resolver: CalendarColorReferenceResolver) throws {
    try resolver.optional(
      &birthdays.birthdayIconColorHex,
      path: "builtins.calendar.birthdays.birthday_icon_color"
    )
  }

  /// Resolves composer panel colors.
  private mutating func resolveComposerColors(using resolver: CalendarColorReferenceResolver) throws {
    try resolver.required(
      &composer.style.backgroundColorHex,
      path: "builtins.calendar.composer.style.background_color"
    )
    try resolver.required(
      &composer.style.borderColorHex,
      path: "builtins.calendar.composer.style.border_color"
    )
    try resolver.required(
      &composer.style.headerTextColorHex,
      path: "builtins.calendar.composer.style.header_text_color"
    )
  }

  /// Resolves upcoming popup colors.
  private mutating func resolveUpcomingColors(using resolver: CalendarColorReferenceResolver) throws {
    try resolver.required(
      &upcoming.popup.backgroundColorHex,
      path: "builtins.calendar.upcoming.popup.background_color"
    )
    try resolver.required(
      &upcoming.popup.borderColorHex,
      path: "builtins.calendar.upcoming.popup.border_color"
    )
  }

  /// Resolves month popup colors.
  private mutating func resolveMonthColors(using resolver: CalendarColorReferenceResolver) throws {
    try resolveMonthPopupFrameColors(using: resolver)
    try resolveMonthCalendarGridColors(using: resolver)
    try resolveMonthSelectionColors(using: resolver)
    try resolveMonthAnchorColors(using: resolver)
  }

  /// Resolves month popup frame colors.
  private mutating func resolveMonthPopupFrameColors(
    using resolver: CalendarColorReferenceResolver
  ) throws {
    try resolver.required(
      &month.popup.style.backgroundColorHex,
      path: "builtins.calendar.month.popup.style.background_color"
    )
    try resolver.required(
      &month.popup.style.borderColorHex,
      path: "builtins.calendar.month.popup.style.border_color"
    )
  }

  /// Resolves month calendar grid colors.
  private mutating func resolveMonthCalendarGridColors(
    using resolver: CalendarColorReferenceResolver
  ) throws {
    try resolver.required(
      &month.popup.calendar.headerTextColorHex,
      path: "builtins.calendar.month.popup.calendar.header_text_color"
    )
    try resolver.required(
      &month.popup.calendar.weekdayTextColorHex,
      path: "builtins.calendar.month.popup.calendar.weekday_text_color"
    )
    try resolver.required(
      &month.popup.calendar.dayTextColorHex,
      path: "builtins.calendar.month.popup.calendar.day_text_color"
    )
    try resolver.required(
      &month.popup.calendar.outsideMonthTextColorHex,
      path: "builtins.calendar.month.popup.calendar.outside_month_text_color"
    )
    try resolver.required(
      &month.popup.calendar.todayCellBackgroundColorHex,
      path: "builtins.calendar.month.popup.calendar.today_cell_background_color"
    )
    try resolver.required(
      &month.popup.calendar.todayCellBorderColorHex,
      path: "builtins.calendar.month.popup.calendar.today_cell_border_color"
    )
    try resolver.required(
      &month.popup.calendar.indicatorColorHex,
      path: "builtins.calendar.month.popup.calendar.indicator_color"
    )
  }

  /// Resolves month popup selection colors.
  private mutating func resolveMonthSelectionColors(
    using resolver: CalendarColorReferenceResolver
  ) throws {
    try resolver.required(
      &month.popup.selection.selectedTextColorHex,
      path: "builtins.calendar.month.popup.selection.selected_text_color"
    )
    try resolver.required(
      &month.popup.selection.selectedBackgroundColorHex,
      path: "builtins.calendar.month.popup.selection.selected_background_color"
    )
  }

  /// Resolves month popup anchor colors.
  private mutating func resolveMonthAnchorColors(
    using resolver: CalendarColorReferenceResolver
  ) throws {
    try resolver.optional(
      &month.popup.anchor.textColorHex,
      path: "builtins.calendar.month.popup.anchor.text_color"
    )
  }
}
