import EasyBarCalendarConfig
import EasyBarCalendarPresentation
import Foundation

extension CalendarBuiltinConfig {
  var appointmentsCalendarUIStyle: CalendarAppointmentsStyle {
    CalendarAppointmentsStyle(
      secondaryTextColorHex: appointments.secondaryTextColorHex,
      emptyTextColorHex: appointments.emptyTextColorHex,
      eventTextColorHex: appointments.eventTextColorHex,
      travelTextColorHex: appointments.travelTextColorHex,
      locationIconColorHex: appointments.locationIconColorHex,
      travelIconColorHex: appointments.travelIconColorHex,
      alertIconColorHex: appointments.alertIconColorHex,
      showCalendarName: appointments.showCalendarName,
      showLocation: appointments.showLocation,
      showTravelTime: appointments.showTravelTime,
      showEndTime: appointments.showEndTime,
      showAlertIcon: appointments.showAlertIcon,
      showAllDayLabel: appointments.showAllDayLabel,
      allDayLabel: appointments.allDayLabel,
      showHolidayAllDayLabel: appointments.showHolidayAllDayLabel,
      locationIcon: appointments.locationIcon,
      alertIcon: appointments.alertIcon,
      travelIcon: appointments.travelIcon,
      itemIndent: appointments.itemIndent
    )
  }

  var birthdayCalendarUIStyle: CalendarBirthdayStyle {
    CalendarBirthdayStyle(
      birthdayIcon: birthdays.birthdayIcon,
      birthdayIconColorHex: birthdays.birthdayIconColorHex
    )
  }

  var calendarComposerUIConfig: CalendarComposerConfig {
    CalendarComposerConfig(
      createTitle: composer.createTitle,
      editTitle: composer.editTitle,
      saveLabel: composer.saveLabel,
      updateLabel: composer.updateLabel,
      removeLabel: composer.removeLabel,
      cancelLabel: composer.cancelLabel,
      deleteConfirmationTitle: composer.deleteConfirmationTitle,
      deleteConfirmationMessage: composer.deleteConfirmationMessage,
      openCalendarLabel: composer.openCalendarLabel,
      titleLabel: composer.titleLabel,
      titlePlaceholder: composer.titlePlaceholder,
      locationLabel: composer.locationLabel,
      locationPlaceholder: composer.locationPlaceholder,
      calendarLabel: composer.calendarLabel,
      allDayLabel: composer.allDayLabel,
      startLabel: composer.startLabel,
      endLabel: composer.endLabel,
      travelTimeLabel: composer.travelTimeLabel,
      alertLabel: composer.alertLabel,
      addAlertLabel: composer.addAlertLabel,
      defaultCalendarName: composer.defaultCalendarName,
      defaultAlert: composer.defaultAlert,
      defaultTravelTime: composer.defaultTravelTime,
      alertLabels: composer.alertLabels,
      travelTimeLabels: composer.travelTimeLabels,
      paddingX: composer.paddingX,
      paddingY: composer.paddingY,
      backgroundColorHex: composer.backgroundColorHex,
      borderColorHex: composer.borderColorHex,
      borderWidth: composer.borderWidth,
      cornerRadius: composer.cornerRadius,
      headerTextColorHex: composer.headerTextColorHex,
      secondaryTextColorHex: appointments.secondaryTextColorHex
    )
  }

  var calendarMonthPopupUIConfig: CalendarMonthPopupConfig {
    CalendarMonthPopupConfig(
      backgroundColorHex: month.popup.backgroundColorHex,
      borderColorHex: month.popup.borderColorHex,
      borderWidth: month.popup.borderWidth,
      cornerRadius: month.popup.cornerRadius,
      paddingX: month.popup.paddingX,
      paddingY: month.popup.paddingY,
      spacing: month.popup.spacing,
      marginX: month.popup.marginX,
      marginY: month.popup.marginY,
      showWeekNumbers: month.popup.showWeekNumbers,
      showEventIndicators: month.popup.showEventIndicators,
      headerTextColorHex: month.popup.headerTextColorHex,
      weekdayTextColorHex: month.popup.weekdayTextColorHex,
      firstWeekday: month.popup.firstWeekday,
      resolvedWeekdaySymbols: month.popup.resolvedWeekdaySymbols,
      dayTextColorHex: month.popup.dayTextColorHex,
      outsideMonthTextColorHex: month.popup.outsideMonthTextColorHex,
      todayCellBackgroundColorHex: month.popup.todayCellBackgroundColorHex,
      todayCellBorderColorHex: month.popup.todayCellBorderColorHex,
      todayCellBorderWidth: month.popup.todayCellBorderWidth,
      todayMarkerVariant: month.popup.todayMarkerVariant.calendarTodayMarkerVariant,
      todayMarkerSize: month.popup.todayMarkerSize,
      indicatorColorHex: month.popup.indicatorColorHex,
      selectedTextColorHex: month.popup.selectedTextColorHex,
      selectedBackgroundColorHex: month.popup.selectedBackgroundColorHex,
      selectionDateFormat: month.popup.selectionDateFormat,
      selectionDateSeparator: month.popup.selectionDateSeparator,
      allowsRangeSelection: month.popup.allowsRangeSelection,
      resetSelectionOnThirdTap: month.popup.resetSelectionOnThirdTap,
      layout: month.popup.layout.calendarMonthPopupLayout,
      appointmentsScrollable: month.popup.appointmentsScrollable,
      appointmentsMinHeight: month.popup.appointmentsMinHeight,
      appointmentsMaxHeight: month.popup.appointmentsMaxHeight,
      agendaTitle: month.popup.agendaTitle,
      maxVisibleAppointments: month.popup.maxVisibleAppointments,
      anchorDateFormat: month.popup.anchor.dateFormat,
      anchorTextColorHex: month.popup.anchor.textColorHex,
      anchorShowDateText: month.popup.anchor.showDateText,
      todayButtonTitle: month.popup.todayButtonTitle,
      todayButtonIcon: month.popup.todayButtonIcon,
      todayButtonPaddingX: month.popup.todayButtonPaddingX,
      todayButtonPaddingY: month.popup.todayButtonPaddingY,
      todayButtonMarginX: month.popup.todayButtonMarginX,
      todayButtonMarginY: month.popup.todayButtonMarginY
    )
  }

  var calendarUpcomingPopupUIConfig: CalendarUpcomingPopupConfig {
    CalendarUpcomingPopupConfig(
      days: upcoming.events.days,
      excludePastEvents: upcoming.events.excludePastEvents,
      backgroundColorHex: upcoming.popup.backgroundColorHex,
      borderColorHex: upcoming.popup.borderColorHex,
      borderWidth: upcoming.popup.borderWidth,
      cornerRadius: upcoming.popup.cornerRadius,
      paddingX: upcoming.popup.paddingX,
      paddingY: upcoming.popup.paddingY,
      spacing: upcoming.popup.spacing,
      marginX: upcoming.popup.marginX,
      marginY: upcoming.popup.marginY,
      firstWeekday: month.popup.firstWeekday,
      selectionDateFormat: month.popup.selectionDateFormat,
      defaultIndicatorColorHex: month.popup.indicatorColorHex
    )
  }
}

extension MonthCalendarPopupLayout {
  fileprivate var calendarMonthPopupLayout: CalendarMonthPopupLayout {
    switch self {
    case .calendarAppointmentsHorizontal:
      return .calendarAppointmentsHorizontal
    case .appointmentsCalendarHorizontal:
      return .appointmentsCalendarHorizontal
    case .calendarAppointmentsVertical:
      return .calendarAppointmentsVertical
    case .appointmentsCalendarVertical:
      return .appointmentsCalendarVertical
    }
  }
}

extension CalendarTodayMarkerVariant {
  fileprivate var calendarTodayMarkerVariant: TodayMarkerVariant {
    switch self {
    case .regularRoundedRectangle: .regularRoundedRectangle
    case .softWobble: .softWobble
    case .doubleSketch: .doubleSketch
    case .openLoop: .openLoop
    }
  }
}
