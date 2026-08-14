import EasyBarShared
import Foundation

extension CalendarBuiltinConfig {
  public static let `default` = CalendarBuiltinConfig(
    placement: .init(enabled: true, position: .right, order: 60),
    style: .init(
      icon: "",
      textColorHex: "#ffffff",
      backgroundColorHex: "#1a1a1a",
      borderColorHex: "#333333",
      borderWidth: 1,
      cornerRadius: 8,
      marginX: 0,
      marginY: 0,
      paddingX: 8,
      paddingY: 4,
      spacing: 6,
      opacity: 1
    ),
    popupMode: .month,
    anchor: .init(
      layout: .row,
      fields: [.date, .time],
      spacing: 0,
      separator: " ",
      time: .init(
        format: "HH:mm",
        textColorHex: "#ffffff",
        fontFamily: nil,
        fontSize: nil,
        fontWeight: .regular
      ),
      date: .init(
        format: "E, d. MMM",
        textColorHex: "#d0d0d0",
        fontFamily: nil,
        fontSize: nil,
        fontWeight: .regular
      )
    ),
    filters: .init(
      includedCalendarNames: [],
      excludedCalendarNames: [],
      includedCalendarSourceNames: [],
      excludedCalendarSourceNames: [],
      includedCalendarIDs: [],
      excludedCalendarIDs: [],
      includedCalendarSourceIDs: [],
      excludedCalendarSourceIDs: []
    ),
    appointments: .init(
      itemIndent: 8,
      eventTextColorHex: "#d0d0d0",
      emptyTextColorHex: "#c0c0c0",
      secondaryTextColorHex: "#91d7e3",
      travelTextColorHex: "#8a8a8a",
      emptyText: "No appointments",
      showCalendarName: false,
      showAllDayLabel: true,
      showHolidayAllDayLabel: false,
      allDayLabel: "All day",
      meetingURLPatterns: CalendarMeetingURLMatcher.defaultPatterns,
      showLocation: true,
      locationIcon: "",
      locationIconColorHex: nil,
      showTravelTime: true,
      showEndTime: true,
      travelIcon: "",
      travelIconColorHex: "#8a8a8a",
      showAlertIcon: false,
      alertIcon: "",
      alertIconColorHex: "#8a8a8a"
    ),
    birthdays: .init(
      showBirthdays: true,
      birthdaysShowAge: true,
      birthdayIcon: "",
      birthdayIconColorHex: nil
    ),
    composer: .init(
      style: .init(
        backgroundColorHex: "#111111",
        borderColorHex: "#444444",
        borderWidth: 1,
        cornerRadius: 10,
        paddingX: 14,
        paddingY: 14,
        headerTextColorHex: "#ffffff"
      ),
      content: .init(
        createTitle: "New Appointment",
        editTitle: "Edit Appointment",
        titleLabel: "Title",
        locationLabel: "Location",
        calendarLabel: "Calendar",
        titlePlaceholder: "What are you doing?",
        locationPlaceholder: "Where are you going?",
        defaultCalendarName: "",
        defaultAlert: "1_hour",
        defaultTravelTime: "none",
        alertLabels: [:],
        travelTimeLabels: [:],
        startLabel: "Begin",
        endLabel: "End",
        allDayLabel: "All day",
        travelTimeLabel: "Travel time",
        alertLabel: "Alert",
        addAlertLabel: "Add alert",
        openCalendarLabel: "Calendar",
        cancelLabel: "Cancel",
        saveLabel: "Save",
        updateLabel: "Update",
        removeLabel: "Remove",
        deleteConfirmationTitle: "Remove appointment?",
        deleteConfirmationMessage: "This action cannot be undone."
      )
    ),
    upcoming: .init(
      events: .init(days: 3, excludePastEvents: false),
      popup: .init(
        backgroundColorHex: "#111111",
        borderColorHex: "#444444",
        borderWidth: 1,
        cornerRadius: 10,
        paddingX: 10,
        paddingY: 8,
        spacing: 8,
        marginX: 8,
        marginY: 8
      )
    ),
    month: .init(
      popup: .init(
        style: .init(
          backgroundColorHex: "#111111",
          borderColorHex: "#444444",
          borderWidth: 1,
          cornerRadius: 14,
          paddingX: 10,
          paddingY: 8,
          spacing: 8,
          marginX: 8,
          marginY: 8
        ),
        calendar: .init(
          showWeekNumbers: true,
          showEventIndicators: true,
          headerTextColorHex: "#ffffff",
          weekdayTextColorHex: "#91d7e3",
          firstWeekday: nil,
          weekdayFormat: "dd",
          weekdaySymbols: nil,
          resolvedWeekdaySymbols: resolveMonthWeekdaySymbols(format: "dd", manualSymbols: nil),
          dayTextColorHex: "#d0d0d0",
          outsideMonthTextColorHex: "#6e738d",
          todayCellBackgroundColorHex: "#00000000",
          todayCellBorderColorHex: "#FF0000",
          todayCellBorderWidth: 1.4,
          todayMarkerVariant: .doubleSketch,
          todayMarkerSize: 28,
          indicatorColorHex: "#8bd5ca"
        ),
        selection: .init(
          selectedTextColorHex: "#0B1020",
          selectedBackgroundColorHex: "#89B4FA",
          selectionDateFormat: "yyyy-MM-dd",
          selectionDateSeparator: " - ",
          allowsRangeSelection: true,
          resetSelectionOnThirdTap: true
        ),
        agenda: .init(
          layout: .calendarAppointmentsVertical,
          appointmentsScrollable: true,
          appointmentsMinHeight: 180,
          appointmentsMaxHeight: 240,
          agendaTitle: "Appointments",
          maxVisibleAppointments: 8
        ),
        anchor: .init(dateFormat: "EEE d MMM", textColorHex: "#ffffff", showDateText: true),
        todayButton: .init(
          title: "Today",
          icon: "",
          paddingX: 7,
          paddingY: 2,
          marginX: 0,
          marginY: 0
        )
      )
    )
  )

  public static func resolveMonthWeekdaySymbols(
    format: String,
    manualSymbols: [String]?
  ) -> [String] {
    if let manualSymbols {
      return manualSymbols
    }

    return systemMonthWeekdaySymbols(format: format)
  }

  private static func systemMonthWeekdaySymbols(format: String) -> [String] {
    let sundayFirstSymbols = systemSundayFirstWeekdaySymbols(format: format)

    guard sundayFirstSymbols.count == 7 else {
      return sundayFirstSymbols
    }

    return Array(sundayFirstSymbols[1...6]) + [sundayFirstSymbols[0]]
  }

  private static func systemSundayFirstWeekdaySymbols(format: String) -> [String] {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.calendar = .autoupdatingCurrent

    switch format {
    case "d":
      return systemVeryShortWeekdaySymbols(from: formatter)
    case "dd":
      return systemShortWeekdaySymbols(from: formatter).map { String($0.prefix(2)) }
    case "ddd":
      return systemShortWeekdaySymbols(from: formatter)
    default:
      return systemShortWeekdaySymbols(from: formatter)
    }
  }

  private static func systemVeryShortWeekdaySymbols(from formatter: DateFormatter) -> [String] {
    return formatter.veryShortStandaloneWeekdaySymbols
      ?? formatter.veryShortWeekdaySymbols
      ?? systemShortWeekdaySymbols(from: formatter).map { String($0.prefix(1)) }
  }

  private static func systemShortWeekdaySymbols(from formatter: DateFormatter) -> [String] {
    return formatter.shortStandaloneWeekdaySymbols
      ?? formatter.shortWeekdaySymbols
      ?? []
  }
}
