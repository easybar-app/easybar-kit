import Foundation

extension CalendarEventComposer {
  /// Stores draft data.
  struct Draft {
    /// The title for this draft.
    let title: String
    /// The location for this draft.
    let location: String?
    /// The stable identifier for this draft.
    let calendarID: String
    /// The start date for this draft.
    let startDate: Date
    /// The end date for this draft.
    let endDate: Date
    /// Whether this draft is all day.
    let isAllDay: Bool
    /// The alert offsets seconds for this draft.
    let alertOffsetsSeconds: [TimeInterval]
    /// The travel time seconds for this draft.
    let travelTimeSeconds: TimeInterval?
  }

  /// Defines the supported validation values.
  enum Validation<Value> {
    case success(Value)
    case failure(String)
  }

  /// Stores composer validation error data.
  struct ComposerValidationError: LocalizedError {
    /// The message for this composer validation error.
    let message: String

    /// The error description for this composer validation error.
    var errorDescription: String? {
      message
    }
  }

  /// Creates draft.
  func makeDraft() -> Validation<Draft> {
    do {
      return .success(try makeValidatedDraft())
    } catch let error as ComposerValidationError {
      return .failure(error.message)
    } catch {
      return .failure(error.localizedDescription)
    }
  }

  /// Creates validated draft.
  func makeValidatedDraft() throws -> Draft {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedTitle.isEmpty else {
      throw ComposerValidationError(message: "Title is required.")
    }

    guard !selectedCalendarID.isEmpty else {
      throw ComposerValidationError(message: "No writable calendar is selected.")
    }

    let range = try normalizedDateRange()
    let travelTimeSeconds = try normalizedTravelTimeSeconds()
    let alertOffsetsSeconds = try normalizedAlertOffsets()

    return Draft(
      title: trimmedTitle,
      location: normalizedOptionalText(location),
      calendarID: selectedCalendarID,
      startDate: range.start,
      endDate: range.end,
      isAllDay: isAllDay,
      alertOffsetsSeconds: alertOffsetsSeconds,
      travelTimeSeconds: travelTimeSeconds
    )
  }

  /// Returns the normalized date range.
  func normalizedDateRange() throws -> (start: Date, end: Date) {
    if isAllDay {
      let startOfDay = calendar.startOfDay(for: startDate)
      let endDay = calendar.startOfDay(for: max(startDate, endDate))
      let exclusiveEnd =
        calendar.date(byAdding: .day, value: 1, to: endDay)
        ?? endDay.addingTimeInterval(86_400)

      return (startOfDay, exclusiveEnd)
    }

    guard endDate > startDate else {
      throw ComposerValidationError(message: "End time must be after start time.")
    }

    return (startDate, endDate)
  }

  /// Returns the normalized travel time seconds.
  func normalizedTravelTimeSeconds() throws -> TimeInterval? {
    guard selectedTravelTime == .custom else {
      return selectedTravelTime.seconds
    }

    let trimmed = customTravelMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return nil
    }

    guard let minutes = Int(trimmed), minutes >= 0 else {
      throw ComposerValidationError(message: "Travel time must be a positive number of minutes.")
    }

    return TimeInterval(minutes * 60)
  }

  /// Returns the normalized alert offsets.
  func normalizedAlertOffsets() throws -> [TimeInterval] {
    var offsets: [TimeInterval] = []

    for row in alertRows {
      switch row.option {
      case .none:
        continue

      case .custom:
        let trimmed = row.customMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let minutes = Int(trimmed), minutes >= 0 else {
          throw ComposerValidationError(message: "Custom alerts must be positive numbers of minutes.")
        }

        offsets.append(TimeInterval(minutes * 60))

      default:
        if let seconds = row.option.leadTimeSeconds {
          offsets.append(seconds)
        }
      }
    }

    return offsets
  }
}
