import Foundation

/// Available visual treatments for today's date in the month calendar.
public enum TodayMarkerVariant: String, CaseIterable, Sendable {
  case regularRoundedRectangle = "regular_rounded_rectangle"
  case softWobble = "soft_wobble"
  case doubleSketch = "double_sketch"
  case openLoop = "open_loop"
}
