import Foundation

/// Value snapshot used to distinguish user edits from a freshly prepared composer.
@MainActor
struct CalendarEventComposerFormState {
  /// The mode for this calendar event composer form state.
  let mode: CalendarEventComposer.Mode
  /// The title for this calendar event composer form state.
  let title: String
  /// The location for this calendar event composer form state.
  let location: String
  /// The stable identifier for this calendar event composer form state.
  let selectedCalendarID: String
  /// The start date for this calendar event composer form state.
  let startDate: Date
  /// The end date for this calendar event composer form state.
  let endDate: Date
  /// Whether this calendar event composer form state is all day.
  let isAllDay: Bool
  /// The selected travel time for this calendar event composer form state.
  let selectedTravelTime: CalendarEventComposer.TravelTimeOption
  /// The custom travel minutes text for this calendar event composer form state.
  let customTravelMinutesText: String
  /// The alert options for this calendar event composer form state.
  let alertOptions: [CalendarEventComposer.AlertOption]
  /// The custom alert minutes text for this calendar event composer form state.
  let customAlertMinutesText: [String]

  /// Creates a calendar event composer form state.
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

  /// Evaluates the matches condition.
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
