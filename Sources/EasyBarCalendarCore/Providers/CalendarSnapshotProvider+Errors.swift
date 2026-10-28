import Foundation

/// Errors raised while mutating calendar events after request validation.
enum CalendarAgentMutationError: LocalizedError {
  case accessDenied
  case eventNotFound
  case calendarNotFound
  case noWritableCalendar

  var errorDescription: String? {
    switch self {
    case .accessDenied:
      return "Calendar access is not available."
    case .eventNotFound:
      return "The selected appointment could not be found."
    case .calendarNotFound:
      return "The selected calendar is missing or not writable."
    case .noWritableCalendar:
      return "No writable calendar is available."
    }
  }
}
