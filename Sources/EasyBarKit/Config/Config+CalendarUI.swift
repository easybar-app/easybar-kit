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
      createTitle: composer.content.createTitle,
      editTitle: composer.content.editTitle,
      saveLabel: composer.content.saveLabel,
      updateLabel: composer.content.updateLabel,
      removeLabel: composer.content.removeLabel,
      cancelLabel: composer.content.cancelLabel,
      deleteConfirmationTitle: composer.content.deleteConfirmationTitle,
      deleteConfirmationMessage: composer.content.deleteConfirmationMessage,
      openCalendarLabel: composer.content.openCalendarLabel,
      titleLabel: composer.content.titleLabel,
      titlePlaceholder: composer.content.titlePlaceholder,
      locationLabel: composer.content.locationLabel,
      locationPlaceholder: composer.content.locationPlaceholder,
      calendarLabel: composer.content.calendarLabel,
      allDayLabel: composer.content.allDayLabel,
      startLabel: composer.content.startLabel,
      endLabel: composer.content.endLabel,
      travelTimeLabel: composer.content.travelTimeLabel,
      alertLabel: composer.content.alertLabel,
      addAlertLabel: composer.content.addAlertLabel,
      defaultCalendarName: composer.content.defaultCalendarName,
      defaultAlert: composer.content.defaultAlert,
      defaultTravelTime: composer.content.defaultTravelTime,
      alertLabels: composer.content.alertLabels,
      travelTimeLabels: composer.content.travelTimeLabels,
      paddingX: composer.style.paddingX,
      paddingY: composer.style.paddingY,
      backgroundColorHex: composer.style.backgroundColorHex,
      borderColorHex: composer.style.borderColorHex,
      borderWidth: composer.style.borderWidth,
      cornerRadius: composer.style.cornerRadius,
      headerTextColorHex: composer.style.headerTextColorHex,
      secondaryTextColorHex: appointments.secondaryTextColorHex
    )
  }

  var calendarMonthPopupUIConfig: CalendarMonthPopupConfig {
    CalendarMonthPopupConfig(
      backgroundColorHex: month.popup.style.backgroundColorHex,
      borderColorHex: month.popup.style.borderColorHex,
      borderWidth: month.popup.style.borderWidth,
      cornerRadius: month.popup.style.cornerRadius,
      paddingX: month.popup.style.paddingX,
      paddingY: month.popup.style.paddingY,
      spacing: month.popup.style.spacing,
      marginX: month.popup.style.marginX,
      marginY: month.popup.style.marginY,
      showWeekNumbers: month.popup.calendar.showWeekNumbers,
      showEventIndicators: month.popup.calendar.showEventIndicators,
      headerTextColorHex: month.popup.calendar.headerTextColorHex,
      weekdayTextColorHex: month.popup.calendar.weekdayTextColorHex,
      firstWeekday: month.popup.calendar.firstWeekday,
      resolvedWeekdaySymbols: month.popup.calendar.resolvedWeekdaySymbols,
      dayTextColorHex: month.popup.calendar.dayTextColorHex,
      outsideMonthTextColorHex: month.popup.calendar.outsideMonthTextColorHex,
      todayCellBackgroundColorHex: month.popup.calendar.todayCellBackgroundColorHex,
      todayCellBorderColorHex: month.popup.calendar.todayCellBorderColorHex,
      todayCellBorderWidth: month.popup.calendar.todayCellBorderWidth,
      todayMarkerVariant: month.popup.calendar.todayMarkerVariant,
      todayMarkerSize: month.popup.calendar.todayMarkerSize,
      indicatorColorHex: month.popup.calendar.indicatorColorHex,
      selectedTextColorHex: month.popup.selection.selectedTextColorHex,
      selectedBackgroundColorHex: month.popup.selection.selectedBackgroundColorHex,
      selectionDateFormat: month.popup.selection.selectionDateFormat,
      selectionDateSeparator: month.popup.selection.selectionDateSeparator,
      allowsRangeSelection: month.popup.selection.allowsRangeSelection,
      resetSelectionOnThirdTap: month.popup.selection.resetSelectionOnThirdTap,
      layout: month.popup.agenda.layout,
      appointmentsScrollable: month.popup.agenda.appointmentsScrollable,
      appointmentsMinHeight: month.popup.agenda.appointmentsMinHeight,
      appointmentsMaxHeight: month.popup.agenda.appointmentsMaxHeight,
      agendaTitle: month.popup.agenda.agendaTitle,
      maxVisibleAppointments: month.popup.agenda.maxVisibleAppointments,
      anchorDateFormat: month.popup.anchor.dateFormat,
      anchorTextColorHex: month.popup.anchor.textColorHex,
      anchorShowDateText: month.popup.anchor.showDateText,
      todayButtonTitle: month.popup.todayButton.title,
      todayButtonIcon: month.popup.todayButton.icon,
      todayButtonPaddingX: month.popup.todayButton.paddingX,
      todayButtonPaddingY: month.popup.todayButton.paddingY,
      todayButtonMarginX: month.popup.todayButton.marginX,
      todayButtonMarginY: month.popup.todayButton.marginY
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
      firstWeekday: month.popup.calendar.firstWeekday,
      selectionDateFormat: month.popup.selection.selectionDateFormat,
      defaultIndicatorColorHex: month.popup.calendar.indicatorColorHex
    )
  }
}
