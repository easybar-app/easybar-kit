extension Config {
  /// Applies the selected theme as defaults before user widget config is parsed.
  func applyThemeDefaults() {
    applyThemeBarDefaults()
    applyThemeBuiltinDefaults()
  }
}

extension Config {
  /// Describes one string color default copied from the active theme into config.
  private typealias ThemeColorDefault = (
    target: ReferenceWritableKeyPath<Config, String>,
    color: KeyPath<Config, String>
  )

  /// Describes one optional string color default copied from the active theme into config.
  private typealias OptionalThemeColorDefault = (
    target: ReferenceWritableKeyPath<Config, String?>,
    color: KeyPath<Config, String>
  )

  /// Applies a set of theme color defaults to string-backed config values.
  private func applyThemeColorDefaults(_ defaults: [ThemeColorDefault]) {
    for entry in defaults {
      self[keyPath: entry.target] = self[keyPath: entry.color]
    }
  }

  /// Applies a set of theme color defaults to optional string-backed config values.
  private func applyOptionalThemeColorDefaults(_ defaults: [OptionalThemeColorDefault]) {
    for entry in defaults {
      self[keyPath: entry.target] = self[keyPath: entry.color]
    }
  }
}

extension Config {
  /// Applies the standard transparent built-in chrome.
  private func applyTransparentBuiltinStyle(
    _ style: inout BuiltinWidgetStyle,
    textColorHex: String? = nil
  ) {
    style.textColorHex = textColorHex ?? themeTextColorHex
    style.backgroundColorHex = themeTransparentColorHex
    style.borderColorHex = themeTransparentColorHex
  }

  /// Applies transparent theme chrome to a built-in with custom-rendered content.
  private func applyTransparentBuiltinStyle(_ style: inout BuiltinWidgetChromeStyle) {
    style.backgroundColorHex = themeTransparentColorHex
    style.borderColorHex = themeTransparentColorHex
  }

  /// Applies transparent theme styling to dynamic-icon content.
  private func applyTransparentBuiltinStyle(
    _ style: inout BuiltinWidgetTextStyle,
    textColorHex: String? = nil
  ) {
    style.textColorHex = textColorHex ?? themeTextColorHex
    applyTransparentBuiltinStyle(&style.chrome)
  }

  /// Applies the standard surface-style built-in chrome.
  private func applySurfaceBuiltinStyle(
    _ style: inout BuiltinWidgetStyle,
    textColorHex: String? = nil
  ) {
    style.textColorHex = textColorHex ?? themeTextColorHex
    style.backgroundColorHex = themeSurfaceHex
    style.borderColorHex = themeBorderColorHex
  }

  /// Applies surface theme styling to dynamic-icon content.
  private func applySurfaceBuiltinStyle(
    _ style: inout BuiltinWidgetTextStyle,
    textColorHex: String? = nil
  ) {
    style.textColorHex = textColorHex ?? themeTextColorHex
    style.chrome.backgroundColorHex = themeSurfaceHex
    style.chrome.borderColorHex = themeBorderColorHex
  }

  /// Applies theme defaults to the bar.
  private func applyThemeBarDefaults() {
    barSection.backgroundHex = themeBackgroundHex
    barSection.borderHex = themeTransparentColorHex
  }

  /// Applies component-specific theme defaults to every native built-in.
  private func applyThemeBuiltinDefaults() {
    applyThemeInboxDefaults()
    applyThemeCPUSparklineDefaults()
    applyThemeBatteryDefaults()
    applyThemeSpacesDefaults()
    applyThemeFrontAppDefaults()
    applyThemeAeroSpaceModeDefaults()
    applyThemeVolumeDefaults()
    applyThemeWiFiDefaults()
    applyThemeCalendarDefaults()
    applyThemeTimeDefaults()
    applyThemeDateDefaults()
  }

  private func applyThemeInboxDefaults() {
    builtinInbox.style.chrome.backgroundColorHex = themeTransparentColorHex
    builtinInbox.style.chrome.borderColorHex = themeTransparentColorHex
    switch builtInSurfacePolicy {
    case .inboxOnly:
      builtinInbox.style.unreadIconColorHex = themeTextColorHex
      builtinInbox.style.readIconColorHex = themeTextColorHex
    case .all, .none:
      builtinInbox.style.unreadIconColorHex = themeTextSecondaryColorHex
      builtinInbox.style.readIconColorHex = themeMutedColorHex
    }
    builtinInbox.style.unreadCountColorHex = themeAccentColorHex
    builtinInbox.popupBackgroundColorHex = themeBackgroundHex
    builtinInbox.popupBorderColorHex = themeBorderStrongColorHex
    builtinInbox.popupTitleColorHex = themeTextColorHex
    builtinInbox.popupTextColorHex = themeTextSecondaryColorHex
    builtinInbox.popupMutedColorHex = themeMutedColorHex
    builtinInbox.popupItemBackgroundColorHex = themeSurfaceHex
    builtinInbox.popupActionColorHex = themeAccentColorHex
    builtinInbox.infoColorHex = themeAccentColorHex
    builtinInbox.successColorHex = themeSuccessColorHex
    builtinInbox.warningColorHex = themeWarningColorHex
    builtinInbox.errorColorHex = themeErrorColorHex
  }

  /// Applies theme defaults to the CPU built-in.
  private func applyThemeCPUSparklineDefaults() {
    applyTransparentBuiltinStyle(&builtinCPU.style)
    builtinCPU.colorHex = themeSuccessSecondaryColorHex
  }

  /// Applies theme defaults to the battery built-in.
  private func applyThemeBatteryDefaults() {
    applyTransparentBuiltinStyle(&builtinBattery.style)

    builtinBattery.fixedColorHex = themeTextColorHex
    applyThemeColorDefaults([
      (\.builtinBattery.colors.highColorHex, \.themeSuccessColorHex),
      (\.builtinBattery.colors.mediumColorHex, \.themeWarningColorHex),
      (\.builtinBattery.colors.lowColorHex, \.themeOrangeColorHex),
      (\.builtinBattery.colors.criticalColorHex, \.themeDangerColorHex),
      (\.builtinBattery.colors.frameColorHex, \.themeMutedColorHex),
      (\.builtinBattery.colors.overlayOutlineColorHex, \.themeOverlayOutlineColorHex),
      (\.builtinBattery.colors.chargingOverlayColorHex, \.themeOverlayTextColorHex),
      (\.builtinBattery.colors.externalPowerOverlayColorHex, \.themeOverlayTextColorHex),
      (\.builtinBattery.colors.onHoldOverlayColorHex, \.themeOverlayTextColorHex),
      (\.builtinBattery.colors.unavailableColorHex, \.themeMutedColorHex),
    ])

    builtinBattery.popup = defaultBuiltinPopupStyle()
  }

  /// Applies theme defaults to the spaces built-in.
  private func applyThemeSpacesDefaults() {
    applyTransparentBuiltinStyle(&builtinSpaces.style)

    applyThemeColorDefaults([
      (\.builtinSpaces.text.focusedColorHex, \.themeTextColorHex),
      (\.builtinSpaces.text.inactiveColorHex, \.themeTextSecondaryColorHex),
      (\.builtinSpaces.colors.activeBackgroundHex, \.themeSurfaceElevatedHex),
      (\.builtinSpaces.colors.inactiveBackgroundHex, \.themeSurfaceHex),
      (\.builtinSpaces.colors.activeBorderHex, \.themeBorderStrongColorHex),
      (\.builtinSpaces.colors.inactiveBorderHex, \.themeBorderSubtleColorHex),
      (\.builtinSpaces.colors.focusedAppBorderHex, \.themeBorderSubtleColorHex),
    ])
  }

  /// Applies theme defaults to the front app built-in.
  private func applyThemeFrontAppDefaults() {
    applySurfaceBuiltinStyle(&builtinFrontApp.style)
  }

  /// Applies theme defaults to the AeroSpace mode built-in.
  private func applyThemeAeroSpaceModeDefaults() {
    applySurfaceBuiltinStyle(&builtinAeroSpaceMode.style)
  }

  /// Applies theme defaults to the volume built-in.
  private func applyThemeVolumeDefaults() {
    applyTransparentBuiltinStyle(&builtinVolume.style)
  }

  /// Applies theme defaults to the Wi-Fi built-in.
  private func applyThemeWiFiDefaults() {
    applyTransparentBuiltinStyle(&builtinWiFi.style)

    applyThemeColorDefaults([
      (\.builtinWiFi.activeColorHex, \.themeTextColorHex),
      (\.builtinWiFi.inactiveColorHex, \.themeMutedColorHex),
      (\.builtinWiFi.inlineTextColorHex, \.themeTextColorHex),
    ])
    builtinWiFi.popup = defaultBuiltinPopupStyle()
  }

  /// Applies theme defaults to the calendar built-in.
  private func applyThemeCalendarDefaults() {
    applyThemeCalendarAnchorDefaults()
    applyThemeCalendarAppointmentDefaults()
    applyThemeCalendarBirthdayDefaults()
    applyThemeCalendarComposerDefaults()
    applyThemeCalendarUpcomingDefaults()
    applyThemeCalendarMonthDefaults()
  }

  /// Applies theme defaults to the calendar bar anchor.
  private func applyThemeCalendarAnchorDefaults() {
    builtinCalendar.style.textColorHex = themeTextColorHex
    builtinCalendar.style.backgroundColorHex = themeSurfaceHex
    builtinCalendar.style.borderColorHex = themeBorderColorHex

    applyOptionalThemeColorDefaults([
      (\.builtinCalendar.anchor.time.textColorHex, \.themeTextColorHex),
      (\.builtinCalendar.anchor.date.textColorHex, \.themeTextSecondaryColorHex),
    ])
  }

  /// Applies theme defaults to calendar appointment rows.
  private func applyThemeCalendarAppointmentDefaults() {
    applyThemeColorDefaults([
      (\.builtinCalendar.appointments.eventTextColorHex, \.themeTextSecondaryColorHex),
      (\.builtinCalendar.appointments.emptyTextColorHex, \.themeTextTertiaryColorHex),
      (\.builtinCalendar.appointments.secondaryTextColorHex, \.themeAccentColorHex),
      (\.builtinCalendar.appointments.travelTextColorHex, \.themeMutedSecondaryColorHex),
    ])

    applyOptionalThemeColorDefaults([
      (\.builtinCalendar.appointments.locationIconColorHex, \.themeAccentColorHex),
      (\.builtinCalendar.appointments.travelIconColorHex, \.themeMutedSecondaryColorHex),
      (\.builtinCalendar.appointments.alertIconColorHex, \.themeMutedSecondaryColorHex),
    ])
  }

  /// Applies theme defaults to calendar birthday indicators.
  private func applyThemeCalendarBirthdayDefaults() {
    applyOptionalThemeColorDefaults([
      (\.builtinCalendar.birthdays.birthdayIconColorHex, \.themeAccentSoftColorHex)
    ])
  }

  /// Applies theme defaults to the calendar event composer.
  private func applyThemeCalendarComposerDefaults() {
    applyThemeColorDefaults([
      (\.builtinCalendar.composer.style.backgroundColorHex, \.themeBackgroundHex),
      (\.builtinCalendar.composer.style.borderColorHex, \.themeBorderStrongColorHex),
      (\.builtinCalendar.composer.style.headerTextColorHex, \.themeTextColorHex),
    ])
  }

  /// Applies theme defaults to the upcoming calendar popup.
  private func applyThemeCalendarUpcomingDefaults() {
    applyThemeColorDefaults([
      (\.builtinCalendar.upcoming.popup.backgroundColorHex, \.themeBackgroundHex),
      (\.builtinCalendar.upcoming.popup.borderColorHex, \.themeBorderStrongColorHex),
    ])
  }

  /// Applies theme defaults to the month calendar popup.
  private func applyThemeCalendarMonthDefaults() {
    applyThemeColorDefaults([
      (\.builtinCalendar.month.popup.style.backgroundColorHex, \.themeBackgroundHex),
      (\.builtinCalendar.month.popup.style.borderColorHex, \.themeBorderStrongColorHex),
      (\.builtinCalendar.month.popup.calendar.headerTextColorHex, \.themeTextColorHex),
      (\.builtinCalendar.month.popup.calendar.weekdayTextColorHex, \.themeAccentColorHex),
      (\.builtinCalendar.month.popup.calendar.dayTextColorHex, \.themeTextSecondaryColorHex),
      (\.builtinCalendar.month.popup.calendar.outsideMonthTextColorHex, \.themeOutsideMonthColorHex),
      (\.builtinCalendar.month.popup.calendar.todayCellBackgroundColorHex, \.themeTransparentColorHex),
      (\.builtinCalendar.month.popup.calendar.todayCellBorderColorHex, \.themeDangerColorHex),
      (\.builtinCalendar.month.popup.calendar.indicatorColorHex, \.themeAccentSoftColorHex),
      (\.builtinCalendar.month.popup.selection.selectedTextColorHex, \.themeSelectionTextColorHex),
      (\.builtinCalendar.month.popup.selection.selectedBackgroundColorHex, \.themeSelectionBackgroundColorHex),
    ])

    applyOptionalThemeColorDefaults([
      (\.builtinCalendar.month.popup.anchor.textColorHex, \.themeTextColorHex)
    ])
  }

  /// Applies theme defaults to the time built-in.
  private func applyThemeTimeDefaults() {
    applySurfaceBuiltinStyle(&builtinTime.style)
  }

  /// Applies theme defaults to the date built-in.
  private func applyThemeDateDefaults() {
    applySurfaceBuiltinStyle(&builtinDate.style)
  }

  /// Returns the default tooltip popup style derived from the active theme.
  private func defaultBuiltinPopupStyle() -> BuiltinPopupStyle {
    BuiltinPopupStyle(
      textColorHex: themeTextColorHex,
      backgroundColorHex: themeBackgroundHex,
      borderColorHex: themeBorderStrongColorHex,
      borderWidth: Self.builtinPopupDefaultBorderWidth,
      cornerRadius: Self.builtinPopupDefaultCornerRadius,
      paddingX: Self.builtinPopupDefaultPaddingX,
      paddingY: Self.builtinPopupDefaultPaddingY,
      marginX: Self.builtinPopupDefaultMarginX,
      marginY: Self.builtinPopupDefaultMarginY
    )
  }
}
