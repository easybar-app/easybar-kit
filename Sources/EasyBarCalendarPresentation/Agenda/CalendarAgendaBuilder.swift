import EasyBarShared
import Foundation

/// Shared helpers for grouping and sorting calendar agenda rows.
public enum CalendarAgendaBuilder {
  /// One entry in a grouped agenda list.
  public struct Entry: Identifiable, Equatable, Sendable {
    /// Defines the supported kind values.
    public enum Kind: Equatable, Sendable {
      case dayHeader(Date)
      case event(CalendarAgentEvent)
    }

    /// The stable identifier for this entry.
    public let id: String
    /// The kind for this entry.
    public let kind: Kind

    /// Creates an entry.
    public init(id: String, kind: Kind) {
      self.id = id
      self.kind = kind
    }
  }

  /// Builds agenda entries for one selected event list.
  public static func build(
    events: [CalendarAgentEvent],
    selectionSpansMultipleDays: Bool,
    calendar: Calendar,
    displayedDate: ((CalendarAgentEvent) -> Date)? = nil
  ) -> [Entry] {
    guard !events.isEmpty else { return [] }

    guard selectionSpansMultipleDays else {
      return events.map { event in
        Entry(id: event.id, kind: .event(event))
      }
    }

    let resolvedDisplayDate: (CalendarAgentEvent) -> Date =
      displayedDate ?? { event in
        self.displayDate(for: event, calendar: calendar)
      }
    let grouped = Dictionary(grouping: events, by: resolvedDisplayDate)
    let sortedDates = grouped.keys.sorted()

    var rows: [Entry] = []

    for date in sortedDates {
      rows.append(
        Entry(
          id: "header-\(calendar.startOfDay(for: date).timeIntervalSince1970)",
          kind: .dayHeader(date)
        )
      )

      let dayEvents = (grouped[date] ?? []).sorted(by: eventSortOrder)
      rows.append(contentsOf: dayEvents.map { Entry(id: $0.id, kind: .event($0)) })
    }

    return rows
  }

  /// Returns a limited visible entry list while keeping day headers stable.
  public static func limitedVisibleEntries(
    _ entries: [Entry],
    maxVisibleEvents: Int
  ) -> [Entry] {
    var limited: [Entry] = []
    var visibleEventCount = 0
    let maxVisible = max(1, maxVisibleEvents)

    for entry in entries {
      switch entry.kind {
      case .dayHeader:
        limited.append(entry)
      case .event:
        guard visibleEventCount < maxVisible else { break }
        limited.append(entry)
        visibleEventCount += 1
      }
    }

    while limited.last.map(isDayHeader) == true {
      _ = limited.popLast()
    }

    return limited
  }

  /// Returns the display date for one event inside grouped agendas.
  public static func displayDate(for event: CalendarAgentEvent, calendar: Calendar) -> Date {
    calendar.startOfDay(for: event.startDate)
  }

  /// Returns whether the event is rendered as a birthday.
  public static func isBirthdayEvent(_ event: CalendarAgentEvent) -> Bool {
    event.id.hasPrefix("birthday-")
  }

  /// Shared sort order for agenda event rows.
  public static func eventSortOrder(lhs: CalendarAgentEvent, rhs: CalendarAgentEvent) -> Bool {
    if isBirthdayEvent(lhs) != isBirthdayEvent(rhs) {
      return isBirthdayEvent(lhs) && !isBirthdayEvent(rhs)
    }

    if lhs.isAllDay != rhs.isAllDay {
      return lhs.isAllDay && !rhs.isAllDay
    }

    if lhs.startDate != rhs.startDate {
      return lhs.startDate < rhs.startDate
    }

    if lhs.endDate != rhs.endDate {
      return lhs.endDate < rhs.endDate
    }

    return lhs.id < rhs.id
  }

  /// Returns whether the entry is a day header.
  public static func isDayHeader(_ entry: Entry) -> Bool {
    if case .dayHeader = entry.kind {
      return true
    }
    return false
  }
}
