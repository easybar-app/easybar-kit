#!/usr/bin/env swift
import CoreGraphics
import Darwin
import EventKit
import Foundation

private enum ScriptError: Error, LocalizedError {
  case calendarAccessDenied
  case invalidCurrentMonth
  case noWritableCalendarSource

  var errorDescription: String? {
    switch self {
    case .calendarAccessDenied:
      return "Calendar access was not granted. Allow access in System Settings > Privacy & Security > Calendars."
    case .invalidCurrentMonth:
      return "Could not determine the current month."
    case .noWritableCalendarSource:
      return "No writable calendar source found."
    }
  }
}

private enum DemoURLPlacement {
  case none
  case eventURL
  case notes
  case location
}

private struct DemoLinkFixture {
  let titleSuffix: String
  let expectedAction: String
  let placement: DemoURLPlacement
  let urlString: String?
  let locationPrefix: String?

  var hasJoinMeetingAction: Bool {
    expectedAction == "Join Meeting"
  }

  var hasOpenURLAction: Bool {
    expectedAction == "Open URL"
  }
}

private struct AppController {
  private let arguments = Array(CommandLine.arguments.dropFirst())
  private let store = EKEventStore()

  /// Runs the demo calendar population script and returns the process exit code.
  func run() -> Int32 {
    if arguments.contains("--help") || arguments.contains("-h") {
      printUsage()
      return 0
    }

    let calendarName = arguments.first ?? "demo"
    let clearExisting = ProcessInfo.processInfo.environment["CLEAR_EXISTING"]?.lowercased() != "false"

    do {
      try populateCalendar(named: calendarName, clearExisting: clearExisting)
      return 0
    } catch {
      printError(error.localizedDescription)
      return 1
    }
  }

  /// Prints script usage.
  private func printUsage() {
    print(
      """
      Usage:
        ./scripts/populate-demo-calendar.swift
        ./scripts/populate-demo-calendar.swift demo

      Optional:
        CLEAR_EXISTING=false ./scripts/populate-demo-calendar.swift demo
      """)
  }

  /// Prints a script error message.
  private func printError(_ message: String) {
    fputs("\(message)\n", stderr)
  }

  /// Populates one demo calendar with generated events for the current month.
  private func populateCalendar(named calendarName: String, clearExisting: Bool) throws {
    guard requestCalendarAccess() else {
      throw ScriptError.calendarAccessDenied
    }

    let targetCalendar = try getOrCreateCalendar(named: calendarName)

    var systemCalendar = Calendar.current
    systemCalendar.timeZone = TimeZone.current

    let now = Date()
    let currentComponents = systemCalendar.dateComponents([.year, .month], from: now)

    guard
      let monthStart = systemCalendar.date(from: currentComponents),
      let monthEnd = systemCalendar.date(byAdding: .month, value: 1, to: monthStart),
      let dayRange = systemCalendar.range(of: .day, in: .month, for: monthStart)
    else {
      throw ScriptError.invalidCurrentMonth
    }

    if clearExisting {
      try clearEvents(
        calendar: targetCalendar,
        start: monthStart,
        end: monthEnd
      )
    }

    let titles = [
      "Team Sync",
      "Design Review",
      "Customer Call",
      "Focus Block",
      "Planning Session",
      "Coffee Chat",
      "Product Review",
      "Budget Check",
      "Interview",
      "Sprint Review",
      "Demo Prep",
      "Roadmap Discussion",
      "Workshop",
      "One-on-One",
      "Incident Review",
      "Architecture Review",
      "Partner Check-In",
      "Research Review",
    ]

    let locations = [
      "Office",
      "Home Office",
      "Client Site",
      "Zurich HB",
      "Conference Room A",
      "Conference Room B",
      "Cafe Central",
      "Google Meet",
      "Zoom",
      "On the train",
      "Remote",
      "Workshop Room",
      "Partner Office",
      "Focus Room",
    ]

    let modes = [
      "in person",
      "remote",
      "hybrid",
      "tentative",
      "busy",
      "free",
      "private notes",
      "follow-up needed",
      "high priority",
      "low priority",
    ]

    let durations = [30, 45, 60, 75, 90]

    let startSlots = [
      8 * 60,
      9 * 60,
      10 * 60,
      11 * 60,
      12 * 60,
      13 * 60,
      14 * 60,
      15 * 60,
      16 * 60,
      17 * 60,
      18 * 60,
    ]

    let alarmOffsets: [TimeInterval] = [
      -5 * 60,
      -10 * 60,
      -15 * 60,
      -30 * 60,
      -60 * 60,
    ]

    let travelTimes: [TimeInterval] = [
      5 * 60,
      10 * 60,
      15 * 60,
      20 * 60,
      30 * 60,
      45 * 60,
    ]

    var createdCount = 0
    var travelTimeSetCount = 0
    var joinMeetingActionCount = 0
    var openURLActionCount = 0
    var eventURLCount = 0
    var notesURLCount = 0
    var locationURLCount = 0

    for day in dayRange {
      let appointmentsToday = Int.random(in: 2...5)
      let selectedSlots = Array(startSlots.shuffled().prefix(appointmentsToday)).sorted()

      for appointmentIndex in 0..<appointmentsToday {
        let startMinutes = selectedSlots[appointmentIndex]
        let durationMinutes = pick(durations)
        let endMinutes = startMinutes + durationMinutes
        let linkFixture = demoLinkFixture(day: day, appointmentIndex: appointmentIndex)

        let title = "\(pick(titles)) \(linkFixture.titleSuffix) #\(day).\(appointmentIndex + 1)"
        let location = demoLocation(
          baseLocation: pick(locations),
          linkFixture: linkFixture
        )
        let mode = pick(modes)

        let shouldHaveTravelTime = Bool.random()
        let travelSeconds = shouldHaveTravelTime ? pick(travelTimes) : 0

        let event = EKEvent(eventStore: store)
        event.calendar = targetCalendar
        event.title = title
        event.startDate = dateFor(
          day: day,
          minutesFromMidnight: startMinutes,
          currentComponents: currentComponents,
          calendar: systemCalendar
        )
        event.endDate = dateFor(
          day: day,
          minutesFromMidnight: endMinutes,
          currentComponents: currentComponents,
          calendar: systemCalendar
        )
        event.location = location
        event.timeZone = TimeZone.current

        if linkFixture.placement == .eventURL, let urlString = linkFixture.urlString {
          event.url = URL(string: urlString)
          eventURLCount += 1
        }

        event.notes = demoNotes(
          mode: mode,
          durationMinutes: durationMinutes,
          travelSeconds: travelSeconds,
          linkFixture: linkFixture,
          day: day,
          appointmentIndex: appointmentIndex
        )

        if linkFixture.hasJoinMeetingAction {
          joinMeetingActionCount += 1
        }

        if linkFixture.hasOpenURLAction {
          openURLActionCount += 1
        }

        switch linkFixture.placement {
        case .none:
          break
        case .eventURL:
          break
        case .notes:
          notesURLCount += 1
        case .location:
          locationURLCount += 1
        }

        if Bool.random() {
          event.structuredLocation = EKStructuredLocation(title: location)
        }

        switch Int.random(in: 0...3) {
        case 0:
          event.availability = .busy
        case 1:
          event.availability = .free
        case 2:
          event.availability = .tentative
        default:
          event.availability = .unavailable
        }

        switch Int.random(in: 0...4) {
        case 0:
          event.addAlarm(EKAlarm(relativeOffset: pick(alarmOffsets)))
        case 1:
          event.addAlarm(EKAlarm(relativeOffset: -30 * 60))
          event.addAlarm(EKAlarm(relativeOffset: -5 * 60))
        case 2:
          event.addAlarm(EKAlarm(relativeOffset: -60 * 60))
        default:
          break
        }

        // Travel time support varies by macOS/EventKit version.
        if travelSeconds > 0, event.responds(to: NSSelectorFromString("setTravelTime:")) {
          event.setValue(travelSeconds, forKey: "travelTime")
          travelTimeSetCount += 1
        }

        try store.save(event, span: .thisEvent, commit: false)
        createdCount += 1
      }
    }

    try store.commit()

    print("Created \(createdCount) appointments in calendar \"\(calendarName)\" for the current month.")
    print("Events expected to show Join Meeting: \(joinMeetingActionCount).")
    print("Events expected to show Open URL: \(openURLActionCount).")
    print("URL source coverage: event.url=\(eventURLCount), notes=\(notesURLCount), location=\(locationURLCount).")
    print("Events with actual EventKit travel time set: \(travelTimeSetCount).")
    print("Events without native travel-time support still include travel time in the notes.")
  }

  /// Removes existing generated events from the target calendar in the requested range.
  private func clearEvents(calendar: EKCalendar, start: Date, end: Date) throws {
    let predicate = store.predicateForEvents(
      withStart: start,
      end: end,
      calendars: [calendar]
    )

    let existingEvents = store.events(matching: predicate)

    for event in existingEvents {
      try store.remove(event, span: .thisEvent, commit: false)
    }

    try store.commit()
  }

  /// Requests read/write access to the user's calendars.
  private func requestCalendarAccess() -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    var grantedResult = false

    if #available(macOS 14.0, *) {
      store.requestFullAccessToEvents { granted, error in
        if let error {
          fputs("Calendar access error: \(error.localizedDescription)\n", stderr)
        }

        grantedResult = granted
        semaphore.signal()
      }
    } else {
      store.requestAccess(to: .event) { granted, error in
        if let error {
          fputs("Calendar access error: \(error.localizedDescription)\n", stderr)
        }

        grantedResult = granted
        semaphore.signal()
      }
    }

    semaphore.wait()
    return grantedResult
  }

  /// Returns an existing calendar with the given name or creates a new one.
  private func getOrCreateCalendar(named name: String) throws -> EKCalendar {
    if let existing = store.calendars(for: .event).first(where: { $0.title == name }) {
      return existing
    }

    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = name
    calendar.cgColor = CGColor(red: 0.15, green: 0.35, blue: 0.95, alpha: 1.0)

    guard
      let source =
        store.defaultCalendarForNewEvents?.source
        ?? store.sources.first(where: { $0.sourceType == .calDAV })
        ?? store.sources.first(where: { $0.sourceType == .local })
        ?? store.sources.first
    else {
      throw ScriptError.noWritableCalendarSource
    }

    calendar.source = source
    try store.saveCalendar(calendar, commit: true)

    return calendar
  }

  /// Returns a deterministic URL fixture so the generated calendar always covers all quick actions.
  private func demoLinkFixture(day: Int, appointmentIndex: Int) -> DemoLinkFixture {
    let fixtures = [
      DemoLinkFixture(
        titleSuffix: "[Join via event URL]",
        expectedAction: "Join Meeting",
        placement: .eventURL,
        urlString: "https://meet.google.com/eas-ybar-demo",
        locationPrefix: "Google Meet"
      ),
      DemoLinkFixture(
        titleSuffix: "[Open URL via event URL]",
        expectedAction: "Open URL",
        placement: .eventURL,
        urlString: "https://github.com/gi8lino/easybar",
        locationPrefix: nil
      ),
      DemoLinkFixture(
        titleSuffix: "[Join via notes]",
        expectedAction: "Join Meeting",
        placement: .notes,
        urlString: "https://us06web.zoom.us/j/12345678901?pwd=easybarDemo",
        locationPrefix: "Zoom"
      ),
      DemoLinkFixture(
        titleSuffix: "[Open URL via notes]",
        expectedAction: "Open URL",
        placement: .notes,
        urlString: "https://example.com/easybar/demo/roadmap",
        locationPrefix: nil
      ),
      DemoLinkFixture(
        titleSuffix: "[Join via location]",
        expectedAction: "Join Meeting",
        placement: .location,
        urlString:
          "https://teams.microsoft.com/l/meetup-join/19%3ameeting_easybar_demo%40thread.v2/0?context=%7B%22Tid%22%3A%22demo%22%2C%22Oid%22%3A%22easybar%22%7D",
        locationPrefix: "Microsoft Teams"
      ),
      DemoLinkFixture(
        titleSuffix: "[Open URL via location]",
        expectedAction: "Open URL",
        placement: .location,
        urlString: "https://developer.apple.com/documentation/eventkit",
        locationPrefix: "Reference"
      ),
      DemoLinkFixture(
        titleSuffix: "[Join Webex]",
        expectedAction: "Join Meeting",
        placement: .eventURL,
        urlString: "https://example.webex.com/meet/easybar-demo",
        locationPrefix: "Webex"
      ),
      DemoLinkFixture(
        titleSuffix: "[No URL]",
        expectedAction: "No URL action",
        placement: .none,
        urlString: nil,
        locationPrefix: nil
      ),
    ]

    return fixtures[(day + appointmentIndex) % fixtures.count]
  }

  /// Returns a location string, optionally embedding a demo URL for URL extraction testing.
  private func demoLocation(baseLocation: String, linkFixture: DemoLinkFixture) -> String {
    guard let urlString = linkFixture.urlString else {
      return baseLocation
    }

    if linkFixture.placement == .location {
      let prefix = linkFixture.locationPrefix ?? baseLocation
      return "\(prefix): \(urlString)"
    }

    if let locationPrefix = linkFixture.locationPrefix {
      return locationPrefix
    }

    return baseLocation
  }

  /// Returns notes with enough detail to test copy-details and URL extraction behavior.
  private func demoNotes(
    mode: String,
    durationMinutes: Int,
    travelSeconds: TimeInterval,
    linkFixture: DemoLinkFixture,
    day: Int,
    appointmentIndex: Int
  ) -> String {
    var lines = [
      "Generated demo appointment.",
      "Mode: \(mode)",
      "Duration: \(durationMinutes) minutes",
      "Travel time: \(travelLabel(travelSeconds))",
      "Expected quick action: \(linkFixture.expectedAction)",
      "Demo source: \(demoSourceLabel(linkFixture.placement))",
      "Agenda:",
      "- Review current status",
      "- Discuss blockers",
      "- Agree on next owner",
      "Follow-up: Send summary after the appointment.",
      "Seed: current-month-demo-data-\(day)-\(appointmentIndex + 1)",
    ]

    if linkFixture.placement == .notes, let urlString = linkFixture.urlString {
      lines.insert("Meeting or reference link: \(urlString)", at: 6)
    }

    if linkFixture.placement == .eventURL, let urlString = linkFixture.urlString {
      lines.insert("Event URL field: \(urlString)", at: 6)
    }

    if linkFixture.placement == .location, let urlString = linkFixture.urlString {
      lines.insert("Location contains URL: \(urlString)", at: 6)
    }

    return lines.joined(separator: "\n")
  }

  /// Returns a label for where a demo URL was stored.
  private func demoSourceLabel(_ placement: DemoURLPlacement) -> String {
    switch placement {
    case .none:
      return "none"
    case .eventURL:
      return "event.url"
    case .notes:
      return "notes"
    case .location:
      return "location"
    }
  }

  /// Picks a random value from a non-empty array.
  private func pick<T>(_ values: [T]) -> T {
    values.randomElement()!
  }

  /// Returns a date in the current month for the given day and time.
  private func dateFor(
    day: Int,
    minutesFromMidnight: Int,
    currentComponents: DateComponents,
    calendar: Calendar
  ) -> Date {
    var components = currentComponents
    components.day = day
    components.hour = minutesFromMidnight / 60
    components.minute = minutesFromMidnight % 60
    components.second = 0

    return calendar.date(from: components)!
  }

  /// Formats EventKit travel time for event notes.
  private func travelLabel(_ seconds: TimeInterval) -> String {
    if seconds <= 0 {
      return "none"
    }

    return "\(Int(seconds / 60)) minutes"
  }
}

exit(AppController().run())
