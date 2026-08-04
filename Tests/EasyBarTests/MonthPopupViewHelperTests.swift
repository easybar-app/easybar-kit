import CoreGraphics
import EasyBarCalendarPresentation
import EasyBarShared
import XCTest

@testable import EasyBarCalendarUI

final class MonthPopupViewHelperTests: XCTestCase {
  @MainActor
  func testFormatVisibleMonthTitleHonorsProvidedLocale() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

    let date = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
    let locale = Locale(identifier: "de_CH")

    let expectedFormatter = DateFormatter()
    expectedFormatter.calendar = calendar
    expectedFormatter.locale = locale
    expectedFormatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")

    XCTAssertEqual(
      CalendarMonthPopupView<StubMonthCalendarPopupStore>.formatVisibleMonthTitle(
        date,
        calendar: calendar,
        locale: locale
      ),
      expectedFormatter.string(from: date)
    )
  }

  @MainActor
  func testMinimumPopupWidthCalculatesCalendarFirstHorizontalLayout() {
    let view = makeMonthPopupView(layout: .calendarAppointmentsHorizontal, spacing: 37)

    XCTAssertEqual(view.minimumPopupWidth, 260 + 220 + 37)
  }

  @MainActor
  func testMinimumPopupWidthCalculatesAppointmentsFirstHorizontalLayout() {
    let view = makeMonthPopupView(layout: .appointmentsCalendarHorizontal, spacing: 14)

    XCTAssertEqual(view.minimumPopupWidth, 260 + 220 + 14)
  }

  @MainActor
  func testMinimumPopupWidthCalculatesCalendarFirstVerticalLayout() {
    let view = makeMonthPopupView(layout: .calendarAppointmentsVertical, spacing: 12)

    XCTAssertEqual(view.minimumPopupWidth, 260)
  }

  @MainActor
  func testMinimumPopupWidthCalculatesAppointmentsFirstVerticalLayout() {
    let view = makeMonthPopupView(layout: .appointmentsCalendarVertical, spacing: 48)

    XCTAssertEqual(view.minimumPopupWidth, 260)
  }

  @MainActor
  func testPopupCornerRadiusUsesConfiguredValue() {
    let view = makeMonthPopupView(layout: .calendarAppointmentsVertical, spacing: 12)

    XCTAssertEqual(view.popupCornerRadius, CGFloat(12))
  }

  @MainActor
  func testScrollableAppointmentsHeightUsesConfiguredMaximum() {
    let view = makeMonthPopupView(layout: .calendarAppointmentsVertical, spacing: 12)

    XCTAssertEqual(view.appointmentsScrollableHeight, CGFloat(240))
  }

  @MainActor
  func testOpenComposerOnDateUsesStartOfDayAndRefreshesAfterChange() {
    let calendar = Calendar.current
    let input = calendar.date(
      bySettingHour: 16,
      minute: 45,
      second: 0,
      of: Date(timeIntervalSince1970: 1_800_000_000)
    )!
    var receivedDate: Date?
    var changeCompletion: (() -> Void)?
    var refreshRequested = false
    let view = makeMonthPopupView(
      layout: .calendarAppointmentsVertical,
      spacing: 12,
      onCreateEvent: { date, completion in
        receivedDate = date
        changeCompletion = completion
      },
      onRefreshRequested: {
        refreshRequested = true
      }
    )

    view.openComposer(on: input)

    XCTAssertEqual(receivedDate, calendar.startOfDay(for: input))
    XCTAssertFalse(refreshRequested)

    changeCompletion?()

    XCTAssertTrue(refreshRequested)
  }

  @MainActor
  func testOnlyStationaryDoubleClickOpensComposer() {
    let calendar = Calendar.current
    let startDate = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
    let view = makeMonthPopupView(
      layout: .calendarAppointmentsVertical,
      spacing: 12
    )

    XCTAssertFalse(
      view.shouldOpenComposerAfterGridInteraction(
        clickCount: 1,
        startDate: startDate,
        endDate: startDate,
        didCrossIntoAnotherDay: false
      )
    )
    XCTAssertTrue(
      view.shouldOpenComposerAfterGridInteraction(
        clickCount: 2,
        startDate: startDate,
        endDate: startDate,
        didCrossIntoAnotherDay: false
      )
    )
    XCTAssertFalse(
      view.shouldOpenComposerAfterGridInteraction(
        clickCount: 2,
        startDate: startDate,
        endDate: endDate,
        didCrossIntoAnotherDay: false
      )
    )
    XCTAssertFalse(
      view.shouldOpenComposerAfterGridInteraction(
        clickCount: 2,
        startDate: startDate,
        endDate: startDate,
        didCrossIntoAnotherDay: true
      )
    )
  }
}

@MainActor
private final class StubMonthCalendarPopupStore: CalendarMonthPopupStore {
  var snapshot: CalendarAgentSnapshot?
  var events: [CalendarAgentEvent] = []

  func eventsInRange(from startDate: Date, to endDate: Date) -> [CalendarAgentEvent] {
    return []
  }

  func hasEvents(on date: Date) -> Bool {
    return false
  }
}

@MainActor
private func makeMonthPopupView(
  layout: CalendarMonthPopupLayout,
  spacing: Double,
  onCreateEvent: @escaping (Date, @escaping () -> Void) -> Void = { _, _ in },
  onRefreshRequested: @escaping () -> Void = {}
) -> CalendarMonthPopupView<StubMonthCalendarPopupStore> {
  return CalendarMonthPopupView(
    store: StubMonthCalendarPopupStore(),
    logger: ProcessLogger(label: "test", minimumLevel: .error),
    config: .testValue(layout: layout, spacing: spacing),
    appointmentsStyle: .testValue,
    birthdays: .testValue,
    emptyText: "No events",
    onVisibleMonthChanged: { _ in },
    onCreateEvent: onCreateEvent,
    onEditEvent: { _, _ in },
    onRefreshRequested: onRefreshRequested
  )
}

extension CalendarMonthPopupConfig {
  fileprivate static func testValue(
    layout: CalendarMonthPopupLayout,
    spacing: Double
  ) -> CalendarMonthPopupConfig {
    return CalendarMonthPopupConfig(
      backgroundColorHex: "#000000",
      borderColorHex: "#ffffff",
      borderWidth: 1,
      cornerRadius: 12,
      paddingX: 0,
      paddingY: 0,
      spacing: spacing,
      marginX: 0,
      marginY: 0,
      showWeekNumbers: false,
      showEventIndicators: true,
      headerTextColorHex: "#ffffff",
      weekdayTextColorHex: "#ffffff",
      firstWeekday: nil,
      resolvedWeekdaySymbols: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
      dayTextColorHex: "#ffffff",
      outsideMonthTextColorHex: "#999999",
      todayCellBackgroundColorHex: "#222222",
      todayCellBorderColorHex: "#ffffff",
      todayCellBorderWidth: 1,
      todayMarkerVariant: .doubleSketch,
      todayMarkerSize: 22,
      indicatorColorHex: "#00ff00",
      selectedTextColorHex: "#000000",
      selectedBackgroundColorHex: "#ffffff",
      selectionDateFormat: "EEE d MMM",
      selectionDateSeparator: " - ",
      allowsRangeSelection: true,
      resetSelectionOnThirdTap: true,
      layout: layout,
      appointmentsScrollable: true,
      appointmentsMinHeight: 120,
      appointmentsMaxHeight: 240,
      agendaTitle: "Agenda",
      maxVisibleAppointments: 5,
      anchorDateFormat: "EEE d MMM",
      anchorTextColorHex: nil,
      anchorShowDateText: true,
      todayButtonTitle: "Today",
      todayButtonIcon: "􀉉",
      todayButtonPaddingX: 7,
      todayButtonPaddingY: 2,
      todayButtonMarginX: 0,
      todayButtonMarginY: 0
    )
  }
}

extension CalendarAppointmentsStyle {
  fileprivate static var testValue: CalendarAppointmentsStyle {
    return CalendarAppointmentsStyle(
      secondaryTextColorHex: "#999999",
      emptyTextColorHex: "#777777",
      eventTextColorHex: "#ffffff",
      travelTextColorHex: "#bbbbbb",
      locationIconColorHex: nil,
      travelIconColorHex: nil,
      alertIconColorHex: nil,
      showCalendarName: true,
      showLocation: true,
      showTravelTime: true,
      showEndTime: true,
      showAlertIcon: true,
      showAllDayLabel: true,
      allDayLabel: "All day",
      showHolidayAllDayLabel: false,
      locationIcon: "@",
      alertIcon: "!",
      travelIcon: ">",
      itemIndent: 0
    )
  }
}

extension CalendarBirthdayStyle {
  fileprivate static var testValue: CalendarBirthdayStyle {
    return CalendarBirthdayStyle(
      birthdayIcon: "*",
      birthdayIconColorHex: nil
    )
  }
}
