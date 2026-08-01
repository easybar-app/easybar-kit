import Foundation

/// Localized fallback text for calendar composer preset controls.
enum CalendarComposerLocalizedText {
  static var none: String {
    String(localized: "None", comment: "Label for no selected alert or travel time")
  }

  static var atTimeOfEvent: String {
    String(
      localized: "At time of event",
      comment: "Label for an alert at the event start time"
    )
  }

  static var custom: String {
    String(localized: "Custom", comment: "Label for a custom alert or travel-time value")
  }

  static func alertBefore(seconds: TimeInterval) -> String {
    String(
      localized: "\(duration(seconds: seconds)) before",
      comment: "Alert preset label with a duration before an event"
    )
  }

  static func duration(seconds: TimeInterval) -> String {
    let normalizedSeconds = max(0, seconds)
    let formatter = DateComponentsFormatter()
    formatter.calendar = .autoupdatingCurrent
    formatter.unitsStyle = .full
    formatter.allowedUnits = allowedUnits(for: normalizedSeconds)
    formatter.maximumUnitCount = 2
    formatter.zeroFormattingBehavior = .dropAll

    return formatter.string(from: normalizedSeconds) ?? fallbackDuration(seconds: normalizedSeconds)
  }

  private static func allowedUnits(for seconds: TimeInterval) -> NSCalendar.Unit {
    if seconds >= 24 * 60 * 60 {
      return [.day, .hour, .minute]
    }

    if seconds >= 60 * 60 {
      return [.hour, .minute]
    }

    return [.minute]
  }

  private static func fallbackDuration(seconds: TimeInterval) -> String {
    let minutes = max(1, Int((seconds / 60).rounded()))

    if minutes >= 24 * 60, minutes.isMultiple(of: 24 * 60) {
      let days = minutes / (24 * 60)
      return days == 1 ? "1 day" : "\(days) days"
    }

    if minutes >= 60, minutes.isMultiple(of: 60) {
      let hours = minutes / 60
      return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    return minutes == 1 ? "1 minute" : "\(minutes) minutes"
  }
}
