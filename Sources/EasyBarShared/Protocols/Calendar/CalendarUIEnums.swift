import Foundation

/// Layout variants for the month-calendar popup.
public enum CalendarMonthPopupLayout: String, CaseIterable, Sendable {
  case calendarAppointmentsHorizontal = "calendar_appointments_horizontal"
  case appointmentsCalendarHorizontal = "appointments_calendar_horizontal"
  case calendarAppointmentsVertical = "calendar_appointments_vertical"
  case appointmentsCalendarVertical = "appointments_calendar_vertical"
}

/// Configurable marker treatments for today's date in the month calendar.
public enum CalendarTodayMarkerVariant: String, CaseIterable, Sendable {
  case regularRoundedRectangle = "regular_rounded_rectangle"
  case softWobble = "soft_wobble"
  case doubleSketch = "double_sketch"
  case openLoop = "open_loop"
}
