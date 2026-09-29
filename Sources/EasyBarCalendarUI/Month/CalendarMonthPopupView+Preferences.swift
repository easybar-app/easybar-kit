import SwiftUI

/// Stores month calendar grid frame preference key data.
struct MonthCalendarGridFramePreferenceKey: PreferenceKey {
  /// The default value for this month calendar grid frame preference key.
  static var defaultValue: CGRect { .zero }

  /// Handles reduce.
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
    return
  }
}

/// Stores month calendar day frame preference key data.
struct MonthCalendarDayFramePreferenceKey: PreferenceKey {
  /// The default value for this month calendar day frame preference key.
  static var defaultValue: [Date: CGRect] { [:] }

  /// Handles reduce.
  static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}
