import EasyBarShared
import Foundation

extension CalendarEventComposer {
  /// Creates an instance.
  func initialAlertRows(
    offsets: [TimeInterval],
    defaultAlert: String
  ) -> [AlertRow] {
    guard !offsets.isEmpty else {
      return [AlertRow(option: AlertOption.from(configValue: defaultAlert))]
    }

    return offsets.map { offset in
      if let option = alertOption(for: offset) {
        return AlertRow(
          option: option,
          customMinutesText: defaultCustomMinutesText(for: option)
        )
      }

      return AlertRow(
        option: .custom,
        customMinutesText: customMinutesText(from: offset)
      )
    }
  }

  /// Returns the alert option.
  func alertOption(for seconds: TimeInterval) -> AlertOption? {
    AlertOption.allCases.first { option in
      guard let leadTimeSeconds = option.leadTimeSeconds else { return false }
      return Int(leadTimeSeconds) == Int(seconds)
    }
  }

  /// Returns the travel option.
  func travelOption(for seconds: TimeInterval?) -> TravelTimeOption? {
    guard let seconds else { return nil }

    return TravelTimeOption.allCases.first { option in
      guard let optionSeconds = option.seconds else { return false }
      return Int(optionSeconds) == Int(seconds)
    }
  }

  /// Returns the displayed end date.
  func displayedEndDate(for event: CalendarAgentEvent) -> Date {
    guard event.isAllDay else {
      return event.endDate
    }

    let startDay = calendar.startOfDay(for: event.startDate)
    let endDay = calendar.startOfDay(for: event.endDate)

    guard endDay > startDay else {
      return startDay
    }

    return calendar.date(byAdding: .day, value: -1, to: endDay) ?? startDay
  }

  /// Returns the default start time.
  func defaultStartTime(on date: Date) -> Date {
    let startOfDay = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .hour, value: 9, to: startOfDay) ?? startOfDay
  }

  /// Returns the default end time.
  func defaultEndTime(on date: Date) -> Date {
    let start = defaultStartTime(on: date)
    return calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
  }

  /// Returns the resolved event identifier.
  func resolvedEventIdentifier(from event: CalendarAgentEvent) -> String? {
    guard !event.id.hasPrefix("birthday-") else {
      return nil
    }

    let suffix = "-\(event.startDate.timeIntervalSince1970)"

    guard event.id.hasSuffix(suffix) else {
      return event.id.isEmpty ? nil : event.id
    }

    let resolved = String(event.id.dropLast(suffix.count))
    return resolved.isEmpty ? nil : resolved
  }

  /// Returns the normalized optional text.
  func normalizedOptionalText(_ value: String?) -> String? {
    guard let value else { return nil }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Clears messages.
  func clearMessages() {
    errorMessage = nil
    infoMessage = nil
  }

  /// Returns the default custom minutes text.
  func defaultCustomMinutesText(for option: AlertOption) -> String {
    guard let seconds = option.leadTimeSeconds, seconds > 0 else {
      return ""
    }

    return customMinutesText(from: seconds)
  }

  /// Returns the default custom minutes text.
  func defaultCustomMinutesText(for option: TravelTimeOption) -> String {
    guard let seconds = option.seconds, seconds > 0 else {
      return ""
    }

    return customMinutesText(from: seconds)
  }

  /// Returns the custom minutes text.
  func customMinutesText(knownSeconds: TimeInterval?, actualSeconds: TimeInterval?) -> String {
    guard knownSeconds == nil, let actualSeconds else {
      return ""
    }

    return customMinutesText(from: actualSeconds)
  }

  /// Returns the custom minutes text.
  func customMinutesText(from seconds: TimeInterval) -> String {
    "\(max(0, Int((seconds / 60).rounded())))"
  }
}
