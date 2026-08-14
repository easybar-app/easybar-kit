import Foundation

/// Stable wire-level error codes returned by the calendar agent.
public enum CalendarAgentErrorCode: String, Codable, Equatable, Sendable {
  case accessDenied = "access_denied"
  case invalidDateRange = "invalid_date_range"
  case invalidRequest = "invalid_request"
  case eventNotFound = "event_not_found"
  case noWritableCalendar = "no_writable_calendar"
  case missingQuery = "missing_query"
  case missingCreateEvent = "missing_create_event"
  case missingUpdateEvent = "missing_update_event"
  case missingDeleteEvent = "missing_delete_event"
  case unknown = "unknown"
}

/// Commands supported by the calendar agent socket.
public enum CalendarAgentCommand: String, Codable, Equatable, Sendable {
  case ping
  case version
  case fetch
  case subscribe
  case logs
  case restart
  case createEvent = "create_event"
  case updateEvent = "update_event"
  case deleteEvent = "delete_event"
}
