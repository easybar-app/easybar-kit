import AppKit
import EasyBarCalendarUI
import EasyBarShared
import Foundation

/// Builds host-side quick actions for calendar appointment rows.
enum CalendarEventActionFactory {
  /// Returns the default action set used by calendar popups.
  static func makeActions(meetingURLPatterns: [String]) -> CalendarEventActions {
    CalendarEventActions(
      meetingURLPatterns: meetingURLPatterns,
      copyDetails: copyDetails(for:),
      openURL: openURL(for:),
      openCalendar: { _ in openCalendarApp() }
    )
  }

  /// Copies one user-facing event summary to the general pasteboard.
  private static func copyDetails(for event: CalendarAgentEvent) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(detailText(for: event), forType: .string)
  }

  /// Opens the URL attached to one event when it is valid.
  private static func openURL(for event: CalendarAgentEvent) {
    guard
      let rawURL = event.url?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawURL.isEmpty,
      let url = URL(string: rawURL)
    else {
      return
    }

    NSWorkspace.shared.open(url)
  }

  /// Opens Calendar.app.
  private static func openCalendarApp() {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal")
    else { return }

    NSWorkspace.shared.open(appURL)
  }

  /// Builds one readable detail string for copying.
  private static func detailText(for event: CalendarAgentEvent) -> String {
    var lines: [String] = [event.title]

    lines.append("When: \(formattedDateRange(for: event))")

    if let calendarName = normalizedText(event.calendarName) {
      lines.append("Calendar: \(calendarName)")
    }

    if let location = normalizedText(event.location) {
      lines.append("Location: \(location)")
    }

    if let url = normalizedText(event.url) {
      lines.append("URL: \(url)")
    }

    return lines.joined(separator: "\n")
  }

  /// Formats the visible start and end date for one event.
  private static func formattedDateRange(for event: CalendarAgentEvent) -> String {
    if event.isAllDay {
      return formattedAllDayRange(for: event)
    }

    let start = dateTimeFormatter.string(from: event.startDate)
    let end = dateTimeFormatter.string(from: event.endDate)

    guard start != end else { return start }
    return "\(start) - \(end)"
  }

  /// Formats an all-day event date range.
  private static func formattedAllDayRange(for event: CalendarAgentEvent) -> String {
    let calendar = Calendar.autoupdatingCurrent
    let start = calendar.startOfDay(for: event.startDate)
    let visibleEnd = calendar.date(byAdding: .day, value: -1, to: event.endDate) ?? event.endDate
    let normalizedEnd = max(start, calendar.startOfDay(for: visibleEnd))
    let startText = dateFormatter.string(from: start)
    let endText = dateFormatter.string(from: normalizedEnd)

    guard startText != endText else { return "All day, \(startText)" }
    return "All day, \(startText) - \(endText)"
  }

  /// Normalizes optional text and drops empty values.
  private static func normalizedText(_ value: String?) -> String? {
    guard let value else { return nil }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Date formatter used for all-day copied summaries.
  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.calendar = .autoupdatingCurrent
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  /// Date-time formatter used for timed copied summaries.
  private static let dateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.calendar = .autoupdatingCurrent
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()
}
