import Foundation

/// Value snapshot used to distinguish user edits from a freshly prepared composer.
@MainActor
struct CalendarEventComposerFormState {
  let mode: CalendarEventComposer.Mode
  let title: String
  let location: String
  let selectedCalendarID: String
  let startDate: Date
  let endDate: Date
  let isAllDay: Bool
  let selectedTravelTime: CalendarEventComposer.TravelTimeOption
  let customTravelMinutesText: String
  let alertOptions: [CalendarEventComposer.AlertOption]
  let customAlertMinutesText: [String]

  init(composer: CalendarEventComposer) {
    mode = composer.mode
    title = composer.title
    location = composer.location
    selectedCalendarID = composer.selectedCalendarID
    startDate = composer.startDate
    endDate = composer.endDate
    isAllDay = composer.isAllDay
    selectedTravelTime = composer.selectedTravelTime
    customTravelMinutesText = composer.customTravelMinutesText
    alertOptions = composer.alertRows.map(\.option)
    customAlertMinutesText = composer.alertRows.map(\.customMinutesText)
  }

  func matches(_ other: Self) -> Bool {
    mode == other.mode
      && title == other.title
      && location == other.location
      && selectedCalendarID == other.selectedCalendarID
      && startDate == other.startDate
      && endDate == other.endDate
      && isAllDay == other.isAllDay
      && selectedTravelTime == other.selectedTravelTime
      && customTravelMinutesText == other.customTravelMinutesText
      && alertOptions == other.alertOptions
      && customAlertMinutesText == other.customAlertMinutesText
  }
}
