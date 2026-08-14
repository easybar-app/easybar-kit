import Foundation

/// Errors raised while mutating calendar events after request validation.
enum CalendarAgentMutationError: LocalizedError {
  case accessDenied
  case eventNotFound
  case noWritableCalendar

  var errorDescription: String? {
    switch self {
    case .accessDenied:
      return "Calendar access is not available."
    case .eventNotFound:
      return "The selected appointment could not be found."
    case .noWritableCalendar:
      return "No writable calendar is available."
    }
  }
}
