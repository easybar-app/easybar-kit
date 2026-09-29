import EasyBarShared
import Foundation

/// Reusable style values for calendar appointments lists.
public struct CalendarAppointmentsStyle: Sendable {
  /// The secondary text color hex for this calendar appointments style.
  public let secondaryTextColorHex: String
  /// The empty text color hex for this calendar appointments style.
  public let emptyTextColorHex: String
  /// The event text color hex for this calendar appointments style.
  public let eventTextColorHex: String
  /// The travel text color hex for this calendar appointments style.
  public let travelTextColorHex: String
  /// The location icon color hex for this calendar appointments style.
  public let locationIconColorHex: String?
  /// The travel icon color hex for this calendar appointments style.
  public let travelIconColorHex: String?
  /// The alert icon color hex for this calendar appointments style.
  public let alertIconColorHex: String?
  /// Whether this calendar appointments style shows calendar name.
  public let showCalendarName: Bool
  /// Whether this calendar appointments style shows location.
  public let showLocation: Bool
  /// Whether this calendar appointments style shows travel time.
  public let showTravelTime: Bool
  /// Whether this calendar appointments style shows end time.
  public let showEndTime: Bool
  /// Whether this calendar appointments style shows alert icon.
  public let showAlertIcon: Bool
  /// Whether this calendar appointments style shows all day label.
  public let showAllDayLabel: Bool
  /// The all day label for this calendar appointments style.
  public let allDayLabel: String
  /// Whether this calendar appointments style shows holiday all day label.
  public let showHolidayAllDayLabel: Bool
  /// The location icon for this calendar appointments style.
  public let locationIcon: String
  /// The alert icon for this calendar appointments style.
  public let alertIcon: String
  /// The travel icon for this calendar appointments style.
  public let travelIcon: String
  /// The item indent for this calendar appointments style.
  public let itemIndent: Double

  /// Creates a calendar appointments style.
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
  /// The birthday icon for this calendar birthday style.
  public let birthdayIcon: String
  /// The birthday icon color hex for this calendar birthday style.
  public let birthdayIconColorHex: String?

  /// Creates a calendar birthday style.
  public init(birthdayIcon: String, birthdayIconColorHex: String?) {
    self.birthdayIcon = birthdayIcon
    self.birthdayIconColorHex = birthdayIconColorHex
  }
}

/// Reusable configuration for the calendar composer UI and view model.
public struct CalendarComposerConfig: Sendable {
  /// The create title for this calendar composer config.
  public let createTitle: String
  /// The edit title for this calendar composer config.
  public let editTitle: String
  /// The save label for this calendar composer config.
  public let saveLabel: String
  /// The update label for this calendar composer config.
  public let updateLabel: String
  /// The remove label for this calendar composer config.
  public let removeLabel: String
  /// Whether this calendar composer config can cel label.
  public let cancelLabel: String
  /// The delete confirmation title for this calendar composer config.
  public let deleteConfirmationTitle: String
  /// The delete confirmation message for this calendar composer config.
  public let deleteConfirmationMessage: String
  /// The open calendar label for this calendar composer config.
  public let openCalendarLabel: String
  /// The title label for this calendar composer config.
  public let titleLabel: String
  /// The title placeholder for this calendar composer config.
  public let titlePlaceholder: String
  /// The location label for this calendar composer config.
  public let locationLabel: String
  /// The location placeholder for this calendar composer config.
  public let locationPlaceholder: String
  /// The calendar label for this calendar composer config.
  public let calendarLabel: String
  /// The all day label for this calendar composer config.
  public let allDayLabel: String
  /// The start label for this calendar composer config.
  public let startLabel: String
  /// The end label for this calendar composer config.
  public let endLabel: String
  /// The travel time label for this calendar composer config.
  public let travelTimeLabel: String
  /// The alert label for this calendar composer config.
  public let alertLabel: String
  /// The add alert label for this calendar composer config.
  public let addAlertLabel: String
  /// The default calendar name for this calendar composer config.
  public let defaultCalendarName: String?
  /// The default alert for this calendar composer config.
  public let defaultAlert: String
  /// The default travel time for this calendar composer config.
  public let defaultTravelTime: String
  /// The alert labels for this calendar composer config.
  public let alertLabels: [String: String]
  /// The travel time labels for this calendar composer config.
  public let travelTimeLabels: [String: String]
  /// The padding x for this calendar composer config.
  public let paddingX: Double
  /// The padding y for this calendar composer config.
  public let paddingY: Double
  /// The background color hex for this calendar composer config.
  public let backgroundColorHex: String
  /// The border color hex for this calendar composer config.
  public let borderColorHex: String
  /// The border width for this calendar composer config.
  public let borderWidth: Double
  /// The corner radius for this calendar composer config.
  public let cornerRadius: Double
  /// The header text color hex for this calendar composer config.
  public let headerTextColorHex: String
  /// The secondary text color hex for this calendar composer config.
  public let secondaryTextColorHex: String

  /// Creates a calendar composer config.
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
  /// The background color hex for this calendar month popup config.
  public let backgroundColorHex: String
  /// The border color hex for this calendar month popup config.
  public let borderColorHex: String
  /// The border width for this calendar month popup config.
  public let borderWidth: Double
  /// The corner radius for this calendar month popup config.
  public let cornerRadius: Double
  /// The padding x for this calendar month popup config.
  public let paddingX: Double
  /// The padding y for this calendar month popup config.
  public let paddingY: Double
  /// The spacing for this calendar month popup config.
  public let spacing: Double
  /// The margin x for this calendar month popup config.
  public let marginX: Double
  /// The margin y for this calendar month popup config.
  public let marginY: Double
  /// Whether this calendar month popup config shows week numbers.
  public let showWeekNumbers: Bool
  /// Whether this calendar month popup config shows event indicators.
  public let showEventIndicators: Bool
  /// The header text color hex for this calendar month popup config.
  public let headerTextColorHex: String
  /// The weekday text color hex for this calendar month popup config.
  public let weekdayTextColorHex: String
  /// The first weekday for this calendar month popup config.
  public let firstWeekday: Int?
  /// The resolved weekday symbols for this calendar month popup config.
  public let resolvedWeekdaySymbols: [String]
  /// The day text color hex for this calendar month popup config.
  public let dayTextColorHex: String
  /// The outside month text color hex for this calendar month popup config.
  public let outsideMonthTextColorHex: String
  /// The today cell background color hex for this calendar month popup config.
  public let todayCellBackgroundColorHex: String
  /// The today cell border color hex for this calendar month popup config.
  public let todayCellBorderColorHex: String
  /// The today cell border width for this calendar month popup config.
  public let todayCellBorderWidth: Double
  /// The today marker variant for this calendar month popup config.
  public let todayMarkerVariant: CalendarTodayMarkerVariant
  /// The today marker size for this calendar month popup config.
  public let todayMarkerSize: Double
  /// The indicator color hex for this calendar month popup config.
  public let indicatorColorHex: String
  /// The selected text color hex for this calendar month popup config.
  public let selectedTextColorHex: String
  /// The selected background color hex for this calendar month popup config.
  public let selectedBackgroundColorHex: String
  /// The selection date format for this calendar month popup config.
  public let selectionDateFormat: String
  /// The selection date separator for this calendar month popup config.
  public let selectionDateSeparator: String
  /// Whether the allows range selection option is enabled for this calendar month popup config.
  public let allowsRangeSelection: Bool
  /// Whether the reset selection on third tap option is enabled for this calendar month popup config.
  public let resetSelectionOnThirdTap: Bool
  /// The layout for this calendar month popup config.
  public let layout: CalendarMonthPopupLayout
  /// Whether the appointments scrollable option is enabled for this calendar month popup config.
  public let appointmentsScrollable: Bool
  /// The appointments min height for this calendar month popup config.
  public let appointmentsMinHeight: Double
  /// The appointments max height for this calendar month popup config.
  public let appointmentsMaxHeight: Double
  /// The agenda title for this calendar month popup config.
  public let agendaTitle: String
  /// The max visible appointments for this calendar month popup config.
  public let maxVisibleAppointments: Int
  /// The anchor date format for this calendar month popup config.
  public let anchorDateFormat: String
  /// The anchor text color hex for this calendar month popup config.
  public let anchorTextColorHex: String?
  /// Whether the anchor show date text option is enabled for this calendar month popup config.
  public let anchorShowDateText: Bool
  /// The today button title for this calendar month popup config.
  public let todayButtonTitle: String
  /// The today button icon for this calendar month popup config.
  public let todayButtonIcon: String
  /// The today button padding x for this calendar month popup config.
  public let todayButtonPaddingX: Double
  /// The today button padding y for this calendar month popup config.
  public let todayButtonPaddingY: Double
  /// The today button margin x for this calendar month popup config.
  public let todayButtonMarginX: Double
  /// The today button margin y for this calendar month popup config.
  public let todayButtonMarginY: Double

  /// Creates a calendar month popup config.
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
  /// The days for this calendar upcoming popup config.
  public let days: Int
  /// Whether this calendar upcoming popup config excludes past events.
  public let excludePastEvents: Bool
  /// The background color hex for this calendar upcoming popup config.
  public let backgroundColorHex: String
  /// The border color hex for this calendar upcoming popup config.
  public let borderColorHex: String
  /// The border width for this calendar upcoming popup config.
  public let borderWidth: Double
  /// The corner radius for this calendar upcoming popup config.
  public let cornerRadius: Double
  /// The padding x for this calendar upcoming popup config.
  public let paddingX: Double
  /// The padding y for this calendar upcoming popup config.
  public let paddingY: Double
  /// The spacing for this calendar upcoming popup config.
  public let spacing: Double
  /// The margin x for this calendar upcoming popup config.
  public let marginX: Double
  /// The margin y for this calendar upcoming popup config.
  public let marginY: Double
  /// The first weekday for this calendar upcoming popup config.
  public let firstWeekday: Int?
  /// The selection date format for this calendar upcoming popup config.
  public let selectionDateFormat: String
  /// The default indicator color hex for this calendar upcoming popup config.
  public let defaultIndicatorColorHex: String

  /// Creates a calendar upcoming popup config.
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
