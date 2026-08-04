import Foundation

/// Configurable marker treatments for today's date in the month calendar.
public enum CalendarTodayMarkerVariant: String, CaseIterable, Sendable {
  case regularRoundedRectangle = "regular_rounded_rectangle"
  case softWobble = "soft_wobble"
  case doubleSketch = "double_sketch"
  case openLoop = "open_loop"
}
