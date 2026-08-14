import EasyBarShared
import Foundation

/// Reusable style values for calendar appointments lists.
public struct CalendarAppointmentsStyle: Sendable {
  public let secondaryTextColorHex: String
  public let emptyTextColorHex: String
  public let eventTextColorHex: String
  public let travelTextColorHex: String
  public let locationIconColorHex: String?
  public let travelIconColorHex: String?
  public let alertIconColorHex: String?
  public let showCalendarName: Bool
  public let showLocation: Bool
  public let showTravelTime: Bool
  public let showEndTime: Bool
  public let showAlertIcon: Bool
  public let showAllDayLabel: Bool
  public let allDayLabel: String
  public let showHolidayAllDayLabel: Bool
  public let locationIcon: String
  public let alertIcon: String
  public let travelIcon: String
  public let itemIndent: Double

  public init(
    secondaryTextColorHex: String,
    emptyTextColorHex: String,
    eventTextColorHex: String,
    travelTextColorHex: String,
    locationIconColorHex: String?,
    travelIconColorHex: String?,
    alertIconColorHex: String?,
    showCalendarName: Bool,
    showLocation: Bool,
    showTravelTime: Bool,
    showEndTime: Bool,
    showAlertIcon: Bool,
    showAllDayLabel: Bool,
    allDayLabel: String,
    showHolidayAllDayLabel: Bool,
    locationIcon: String,
    alertIcon: String,
    travelIcon: String,
    itemIndent: Double
  ) {
    self.secondaryTextColorHex = secondaryTextColorHex
    self.emptyTextColorHex = emptyTextColorHex
    self.eventTextColorHex = eventTextColorHex
    self.travelTextColorHex = travelTextColorHex
    self.locationIconColorHex = locationIconColorHex
    self.travelIconColorHex = travelIconColorHex
    self.alertIconColorHex = alertIconColorHex
    self.showCalendarName = showCalendarName
    self.showLocation = showLocation
    self.showTravelTime = showTravelTime
    self.showEndTime = showEndTime
    self.showAlertIcon = showAlertIcon
    self.showAllDayLabel = showAllDayLabel
    self.allDayLabel = allDayLabel
    self.showHolidayAllDayLabel = showHolidayAllDayLabel
    self.locationIcon = locationIcon
    self.alertIcon = alertIcon
    self.travelIcon = travelIcon
    self.itemIndent = itemIndent
  }
}

/// Reusable birthday display values for calendar popups.
public struct CalendarBirthdayStyle: Sendable {
  public let birthdayIcon: String
  public let birthdayIconColorHex: String?

  public init(birthdayIcon: String, birthdayIconColorHex: String?) {
    self.birthdayIcon = birthdayIcon
    self.birthdayIconColorHex = birthdayIconColorHex
  }
}

/// Reusable configuration for the calendar composer UI and view model.
public struct CalendarComposerConfig: Sendable {
  public let createTitle: String
  public let editTitle: String
  public let saveLabel: String
  public let updateLabel: String
  public let removeLabel: String
  public let cancelLabel: String
  public let deleteConfirmationTitle: String
  public let deleteConfirmationMessage: String
  public let openCalendarLabel: String
  public let titleLabel: String
  public let titlePlaceholder: String
  public let locationLabel: String
  public let locationPlaceholder: String
  public let calendarLabel: String
  public let allDayLabel: String
  public let startLabel: String
  public let endLabel: String
  public let travelTimeLabel: String
  public let alertLabel: String
  public let addAlertLabel: String
  public let defaultCalendarName: String?
  public let defaultAlert: String
  public let defaultTravelTime: String
  public let alertLabels: [String: String]
  public let travelTimeLabels: [String: String]
  public let paddingX: Double
  public let paddingY: Double
  public let backgroundColorHex: String
  public let borderColorHex: String
  public let borderWidth: Double
  public let cornerRadius: Double
  public let headerTextColorHex: String
  public let secondaryTextColorHex: String

  public init(
    createTitle: String,
    editTitle: String,
    saveLabel: String,
    updateLabel: String,
    removeLabel: String,
    cancelLabel: String,
    deleteConfirmationTitle: String,
    deleteConfirmationMessage: String,
    openCalendarLabel: String,
    titleLabel: String,
    titlePlaceholder: String,
    locationLabel: String,
    locationPlaceholder: String,
    calendarLabel: String,
    allDayLabel: String,
    startLabel: String,
    endLabel: String,
    travelTimeLabel: String,
    alertLabel: String,
    addAlertLabel: String,
    defaultCalendarName: String?,
    defaultAlert: String,
    defaultTravelTime: String,
    alertLabels: [String: String],
    travelTimeLabels: [String: String],
    paddingX: Double,
    paddingY: Double,
    backgroundColorHex: String,
    borderColorHex: String,
    borderWidth: Double,
    cornerRadius: Double,
    headerTextColorHex: String,
    secondaryTextColorHex: String
  ) {
    self.createTitle = createTitle
    self.editTitle = editTitle
    self.saveLabel = saveLabel
    self.updateLabel = updateLabel
    self.removeLabel = removeLabel
    self.cancelLabel = cancelLabel
    self.deleteConfirmationTitle = deleteConfirmationTitle
    self.deleteConfirmationMessage = deleteConfirmationMessage
    self.openCalendarLabel = openCalendarLabel
    self.titleLabel = titleLabel
    self.titlePlaceholder = titlePlaceholder
    self.locationLabel = locationLabel
    self.locationPlaceholder = locationPlaceholder
    self.calendarLabel = calendarLabel
    self.allDayLabel = allDayLabel
    self.startLabel = startLabel
    self.endLabel = endLabel
    self.travelTimeLabel = travelTimeLabel
    self.alertLabel = alertLabel
    self.addAlertLabel = addAlertLabel
    self.defaultCalendarName = defaultCalendarName
    self.defaultAlert = defaultAlert
    self.defaultTravelTime = defaultTravelTime
    self.alertLabels = alertLabels
    self.travelTimeLabels = travelTimeLabels
    self.paddingX = paddingX
    self.paddingY = paddingY
    self.backgroundColorHex = backgroundColorHex
    self.borderColorHex = borderColorHex
    self.borderWidth = borderWidth
    self.cornerRadius = cornerRadius
    self.headerTextColorHex = headerTextColorHex
    self.secondaryTextColorHex = secondaryTextColorHex
  }
}

/// Reusable configuration for the month-calendar popup.
public struct CalendarMonthPopupConfig: Sendable {
  public let backgroundColorHex: String
  public let borderColorHex: String
  public let borderWidth: Double
  public let cornerRadius: Double
  public let paddingX: Double
  public let paddingY: Double
  public let spacing: Double
  public let marginX: Double
  public let marginY: Double
  public let showWeekNumbers: Bool
  public let showEventIndicators: Bool
  public let headerTextColorHex: String
  public let weekdayTextColorHex: String
  public let firstWeekday: Int?
  public let resolvedWeekdaySymbols: [String]
  public let dayTextColorHex: String
  public let outsideMonthTextColorHex: String
  public let todayCellBackgroundColorHex: String
  public let todayCellBorderColorHex: String
  public let todayCellBorderWidth: Double
  public let todayMarkerVariant: CalendarTodayMarkerVariant
  public let todayMarkerSize: Double
  public let indicatorColorHex: String
  public let selectedTextColorHex: String
  public let selectedBackgroundColorHex: String
  public let selectionDateFormat: String
  public let selectionDateSeparator: String
  public let allowsRangeSelection: Bool
  public let resetSelectionOnThirdTap: Bool
  public let layout: CalendarMonthPopupLayout
  public let appointmentsScrollable: Bool
  public let appointmentsMinHeight: Double
  public let appointmentsMaxHeight: Double
  public let agendaTitle: String
  public let maxVisibleAppointments: Int
  public let anchorDateFormat: String
  public let anchorTextColorHex: String?
  public let anchorShowDateText: Bool
  public let todayButtonTitle: String
  public let todayButtonIcon: String
  public let todayButtonPaddingX: Double
  public let todayButtonPaddingY: Double
  public let todayButtonMarginX: Double
  public let todayButtonMarginY: Double

  public init(
    backgroundColorHex: String,
    borderColorHex: String,
    borderWidth: Double,
    cornerRadius: Double,
    paddingX: Double,
    paddingY: Double,
    spacing: Double,
    marginX: Double,
    marginY: Double,
    showWeekNumbers: Bool,
    showEventIndicators: Bool,
    headerTextColorHex: String,
    weekdayTextColorHex: String,
    firstWeekday: Int?,
    resolvedWeekdaySymbols: [String],
    dayTextColorHex: String,
    outsideMonthTextColorHex: String,
    todayCellBackgroundColorHex: String,
    todayCellBorderColorHex: String,
    todayCellBorderWidth: Double,
    todayMarkerVariant: CalendarTodayMarkerVariant,
    todayMarkerSize: Double,
    indicatorColorHex: String,
    selectedTextColorHex: String,
    selectedBackgroundColorHex: String,
    selectionDateFormat: String,
    selectionDateSeparator: String,
    allowsRangeSelection: Bool,
    resetSelectionOnThirdTap: Bool,
    layout: CalendarMonthPopupLayout,
    appointmentsScrollable: Bool,
    appointmentsMinHeight: Double,
    appointmentsMaxHeight: Double,
    agendaTitle: String,
    maxVisibleAppointments: Int,
    anchorDateFormat: String,
    anchorTextColorHex: String?,
    anchorShowDateText: Bool,
    todayButtonTitle: String,
    todayButtonIcon: String,
    todayButtonPaddingX: Double,
    todayButtonPaddingY: Double,
    todayButtonMarginX: Double,
    todayButtonMarginY: Double
  ) {
    self.backgroundColorHex = backgroundColorHex
    self.borderColorHex = borderColorHex
    self.borderWidth = borderWidth
    self.cornerRadius = cornerRadius
    self.paddingX = paddingX
    self.paddingY = paddingY
    self.spacing = spacing
    self.marginX = marginX
    self.marginY = marginY
    self.showWeekNumbers = showWeekNumbers
    self.showEventIndicators = showEventIndicators
    self.headerTextColorHex = headerTextColorHex
    self.weekdayTextColorHex = weekdayTextColorHex
    self.firstWeekday = firstWeekday
    self.resolvedWeekdaySymbols = resolvedWeekdaySymbols
    self.dayTextColorHex = dayTextColorHex
    self.outsideMonthTextColorHex = outsideMonthTextColorHex
    self.todayCellBackgroundColorHex = todayCellBackgroundColorHex
    self.todayCellBorderColorHex = todayCellBorderColorHex
    self.todayCellBorderWidth = todayCellBorderWidth
    self.todayMarkerVariant = todayMarkerVariant
    self.todayMarkerSize = todayMarkerSize
    self.indicatorColorHex = indicatorColorHex
    self.selectedTextColorHex = selectedTextColorHex
    self.selectedBackgroundColorHex = selectedBackgroundColorHex
    self.selectionDateFormat = selectionDateFormat
    self.selectionDateSeparator = selectionDateSeparator
    self.allowsRangeSelection = allowsRangeSelection
    self.resetSelectionOnThirdTap = resetSelectionOnThirdTap
    self.layout = layout
    self.appointmentsScrollable = appointmentsScrollable
    self.appointmentsMinHeight = appointmentsMinHeight
    self.appointmentsMaxHeight = appointmentsMaxHeight
    self.agendaTitle = agendaTitle
    self.maxVisibleAppointments = maxVisibleAppointments
    self.anchorDateFormat = anchorDateFormat
    self.anchorTextColorHex = anchorTextColorHex
    self.anchorShowDateText = anchorShowDateText
    self.todayButtonTitle = todayButtonTitle
    self.todayButtonIcon = todayButtonIcon
    self.todayButtonPaddingX = todayButtonPaddingX
    self.todayButtonPaddingY = todayButtonPaddingY
    self.todayButtonMarginX = todayButtonMarginX
    self.todayButtonMarginY = todayButtonMarginY
  }
}

/// Reusable configuration for the upcoming-calendar popup.
public struct CalendarUpcomingPopupConfig: Sendable {
  public let days: Int
  public let excludePastEvents: Bool
  public let backgroundColorHex: String
  public let borderColorHex: String
  public let borderWidth: Double
  public let cornerRadius: Double
  public let paddingX: Double
  public let paddingY: Double
  public let spacing: Double
  public let marginX: Double
  public let marginY: Double
  public let firstWeekday: Int?
  public let selectionDateFormat: String
  public let defaultIndicatorColorHex: String

  public init(
    days: Int,
    excludePastEvents: Bool,
    backgroundColorHex: String,
    borderColorHex: String,
    borderWidth: Double,
    cornerRadius: Double,
    paddingX: Double,
    paddingY: Double,
    spacing: Double,
    marginX: Double,
    marginY: Double,
    firstWeekday: Int?,
    selectionDateFormat: String,
    defaultIndicatorColorHex: String
  ) {
    self.days = days
    self.excludePastEvents = excludePastEvents
    self.backgroundColorHex = backgroundColorHex
    self.borderColorHex = borderColorHex
    self.borderWidth = borderWidth
    self.cornerRadius = cornerRadius
    self.paddingX = paddingX
    self.paddingY = paddingY
    self.spacing = spacing
    self.marginX = marginX
    self.marginY = marginY
    self.firstWeekday = firstWeekday
    self.selectionDateFormat = selectionDateFormat
    self.defaultIndicatorColorHex = defaultIndicatorColorHex
  }
}
