import EasyBarShared
import Foundation

/// Host-provided quick actions shown for calendar appointment rows.
public struct CalendarEventActions {
  /// Case-insensitive URL substrings used to identify meeting links.
  public let meetingURLPatterns: [String]
  /// Copies a user-facing summary of one appointment.
  public let copyDetails: ((CalendarAgentEvent) -> Void)?
  /// Opens an attached event URL when the appointment has one.
  public let openURL: ((CalendarAgentEvent) -> Void)?
  /// Opens the system Calendar application.
  public let openCalendar: ((CalendarAgentEvent) -> Void)?

  /// Creates one action set for appointment quick actions.
  public init(
    meetingURLPatterns: [String] = CalendarMeetingURLMatcher.defaultPatterns,
    copyDetails: ((CalendarAgentEvent) -> Void)? = nil,
    openURL: ((CalendarAgentEvent) -> Void)? = nil,
    openCalendar: ((CalendarAgentEvent) -> Void)? = nil
  ) {
    self.meetingURLPatterns = CalendarMeetingURLMatcher.normalizedPatterns(meetingURLPatterns)
    self.copyDetails = copyDetails
    self.openURL = openURL
    self.openCalendar = openCalendar
  }

  /// Returns whether at least one non-edit action can be shown for the event.
  public func hasVisibleAction(for event: CalendarAgentEvent) -> Bool {
    copyDetails != nil
      || openCalendar != nil
      || (openURL != nil && event.hasUsableURL)
  }

  /// Returns the menu title for opening the event URL.
  public func urlActionTitle(for event: CalendarAgentEvent) -> String {
    CalendarMeetingURLMatcher.matches(event.url, patterns: meetingURLPatterns)
      ? "Join Meeting"
      : "Open URL"
  }
}

extension CalendarAgentEvent {
  /// Returns whether the event has a non-empty URL string.
  var hasUsableURL: Bool {
    guard let url else { return false }

    return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

}
