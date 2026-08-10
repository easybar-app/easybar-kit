import EventKit
import Foundation
import XCTest

@testable import EasyBarCalendarCore
@testable import EasyBarShared

private final class CalendarTravelTimeTestObject: NSObject {
  @objc dynamic var travelTime: Double = 0
}

final class CalendarCoreRegressionTests: XCTestCase {
  func testInProcessAuthorizationGrantSurvivesTransientNotDeterminedStatus() {
    let state = CalendarAuthorizationState()
    state.markGrantedInProcess()

    state.setStatus(.notDetermined)
    XCTAssertTrue(state.effectiveAccessGranted())

    state.setStatus(.denied)
    XCTAssertFalse(state.effectiveAccessGranted())
  }

  func testAuthorizationDenialNotifiesCurrentSubscriberOnce() {
    let status = LockedState<EKAuthorizationStatus>(.notDetermined)
    let completion = LockedState<((Bool, Error?) -> Void)?>(nil)
    let notified = expectation(description: "denial published")
    notified.assertForOverFulfill = true

    let controller = CalendarAuthorizationController(
      eventStore: EKEventStore(),
      authState: CalendarAuthorizationState(),
      logger: makeLogger(),
      authorizationStatus: { status.withLock { $0 } },
      requestAccess: { callback in completion.withLock { $0 = callback } }
    )
    controller.start {
      notified.fulfill()
    }

    status.withLock { $0 = .denied }
    let callback = completion.withLock { $0 }
    XCTAssertNotNil(callback)
    callback?(false, nil)

    wait(for: [notified], timeout: 1)
    controller.stop()
  }

  func testRepeatedProviderStartReplacesTheEventStoreObserver() {
    let notificationCenter = NotificationCenter()
    let eventStore = EKEventStore()
    let changed = expectation(description: "one active event-store observer")
    changed.assertForOverFulfill = true
    let countChanges = LockedState(false)

    let provider = CalendarSnapshotProvider(
      logger: makeLogger(),
      eventStore: eventStore,
      notificationCenter: notificationCenter,
      authorizationStatus: { .denied },
      requestAccess: { _ in XCTFail("denied status must not request access") }
    )
    let callback = {
      if countChanges.withLock({ $0 }) {
        changed.fulfill()
      }
    }

    provider.start(onChange: callback)
    provider.start(onChange: callback)
    countChanges.withLock { $0 = true }
    notificationCenter.post(name: .EKEventStoreChanged, object: eventStore)

    wait(for: [changed], timeout: 1)
    provider.stop()
  }

  func testQueryValidationRejectsReversedAndOversizedRanges() {
    let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    XCTAssertThrowsError(
      try CalendarAgentRequestValidator.validate(
        makeQuery(start: start, end: start.addingTimeInterval(-1))
      )
    ) { error in
      XCTAssertEqual(error as? CalendarAgentRequestValidationError, .invalidDateRange)
    }

    XCTAssertThrowsError(
      try CalendarAgentRequestValidator.validate(
        makeQuery(
          start: start,
          end: start.addingTimeInterval(CalendarAgentRequestLimits.maximumDateSpan + 1)
        )
      )
    ) { error in
      XCTAssertEqual(error as? CalendarAgentRequestValidationError, .dateRangeTooLarge)
    }
  }

  func testRequestValidationBoundsSectionsFiltersAndMutationNumbers() {
    let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
    var query = makeQuery(start: start, end: start.addingTimeInterval(86_400))
    query.sectionStartDate = start
    query.sectionDayCount = CalendarAgentRequestLimits.maximumSectionDayCount + 1

    XCTAssertThrowsError(try CalendarAgentRequestValidator.validate(query)) { error in
      XCTAssertEqual(error as? CalendarAgentRequestValidationError, .invalidSectionDayCount)
    }

    query.sectionDayCount = 1
    query.includedCalendarNames = Array(
      repeating: "calendar",
      count: CalendarAgentRequestLimits.maximumFilterValueCount + 1
    )
    XCTAssertThrowsError(try CalendarAgentRequestValidator.validate(query))

    let draft = CalendarAgentCreateEvent(
      title: "Event",
      startDate: start,
      endDate: start.addingTimeInterval(3_600),
      isAllDay: false,
      alertOffsetsSeconds: [.infinity]
    )
    XCTAssertThrowsError(try CalendarAgentRequestValidator.validate(draft)) { error in
      XCTAssertEqual(
        error as? CalendarAgentRequestValidationError,
        .invalidNumber(field: "alertOffsetsSeconds")
      )
    }
  }

  func testBirthdayCalendarUsesTheSameQueryFilters() {
    var query = makeQuery(
      start: Date(timeIntervalSinceReferenceDate: 1_000_000),
      end: Date(timeIntervalSinceReferenceDate: 1_086_400)
    )
    query.excludedCalendarNames = ["Birthdays"]

    XCTAssertFalse(
      CalendarSnapshotProvider.calendarMatchesQuery(
        CalendarFilterTarget(
          title: "Birthdays",
          identifier: "birthday-calendar",
          sourceTitle: "Contacts",
          sourceIdentifier: "contacts-source"
        ),
        query: query
      )
    )
  }

  func testFallbackEventIdentityIsDeterministicAndOccurrenceSpecific() {
    let start = Date(timeIntervalSinceReferenceDate: 123_456)
    let common: (Date) -> String = { occurrenceStart in
      CalendarEventIdentity.makeID(
        prefix: "event-",
        eventIdentifier: nil,
        calendarID: "calendar-id",
        sourceID: "source-id",
        title: "Stand-up",
        startDate: occurrenceStart,
        endDate: occurrenceStart.addingTimeInterval(1_800),
        isAllDay: false,
        location: "Room 1"
      )
    }

    XCTAssertEqual(common(start), common(start))
    XCTAssertNotEqual(common(start), common(start.addingTimeInterval(86_400)))
  }

  func testAlarmNormalizationPreservesAbsoluteAndEqualLeadTimes() {
    let start = Date(timeIntervalSinceReferenceDate: 100_000)
    let offsets = CalendarEventNormalization.visibleAlertOffsetsSeconds(
      eventStartDate: start,
      relativeOffsets: [-3_600, -1_800, 300, .nan],
      absoluteDates: [
        start.addingTimeInterval(-1_800),
        start.addingTimeInterval(-900),
        start.addingTimeInterval(100),
      ]
    )

    XCTAssertEqual(offsets, [900, 1_800, 3_600])
  }

  func testBirthdayAgeParsingRequiresAPlausibleTrailingAge() {
    XCTAssertEqual(
      CalendarEventNormalization.birthdayTitle("Ada Lovelace (36)", showAge: true),
      "Ada Lovelace (36)"
    )
    XCTAssertEqual(
      CalendarEventNormalization.birthdayTitle("Ada Lovelace (36)", showAge: false),
      "Ada Lovelace"
    )
    XCTAssertEqual(
      CalendarEventNormalization.birthdayTitle("Release (2026)", showAge: false),
      "Release (2026)"
    )
    XCTAssertEqual(
      CalendarEventNormalization.birthdayTitle("Room (42) notes", showAge: false),
      "Room (42) notes"
    )
  }

  func testHolidayClassificationDoesNotMatchArbitrarySubstrings() {
    XCTAssertFalse(
      CalendarEventNormalization.isHolidayCalendar(
        isSubscription: true,
        titles: ["Holiday Planning", "Projects"]
      )
    )
    XCTAssertFalse(
      CalendarEventNormalization.isHolidayCalendar(
        isSubscription: false,
        titles: ["Holidays"]
      )
    )
    XCTAssertTrue(
      CalendarEventNormalization.isHolidayCalendar(
        isSubscription: true,
        titles: ["US Holidays"]
      )
    )
  }

  func testUnsupportedTravelTimeObjectFailsClosed() {
    let object = NSObject()
    XCTAssertNil(EventKitTravelTimeAdapter.read(from: object))
    XCTAssertFalse(EventKitTravelTimeAdapter.write(1_800, to: object))
  }

  func testTravelTimeBridgeReadsAndWritesSupportedObjects() {
    let object = CalendarTravelTimeTestObject()
    XCTAssertTrue(EventKitTravelTimeAdapter.write(1_800, to: object))
    XCTAssertEqual(EventKitTravelTimeAdapter.read(from: object), 1_800)
    XCTAssertFalse(EventKitTravelTimeAdapter.write(.infinity, to: object))
  }

  func testEndTimeRemainsVisibleAcrossDifferentDaysWithSameClockTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(86_400)

    XCTAssertTrue(
      CalendarEventNormalization.shouldShowEndTime(
        startDate: start,
        endDate: end,
        isAllDay: false,
        calendar: calendar
      )
    )
  }

  func testMultiDaySectionsClampDisplayedTimesToEachDay() {
    let calendar = Calendar.current
    let sectionStart = calendar.startOfDay(for: Date())
    let eventStart = calendar.date(byAdding: .hour, value: 10, to: sectionStart)!
    let eventEnd = calendar.date(byAdding: .hour, value: 58, to: sectionStart)!
    let event = CalendarAgentEvent(
      id: "event-1",
      title: "Conference",
      startDate: eventStart,
      endDate: eventEnd,
      isAllDay: false
    )
    let provider = CalendarSnapshotProvider(logger: makeLogger())
    let query = CalendarAgentQuery(
      startDate: sectionStart,
      endDate: calendar.date(byAdding: .day, value: 3, to: sectionStart)!,
      sectionStartDate: sectionStart,
      sectionDayCount: 3,
      showBirthdays: false,
      emptyText: "Empty",
      birthdaysTitle: "Birthdays",
      birthdaysDateFormat: "dd.MM",
      birthdaysShowAge: false
    )

    let sections = provider.makeSections(query: query, events: [event])
    XCTAssertEqual(sections.count, 3)
    XCTAssertEqual(sections[0].items.first?.startDate, eventStart)
    XCTAssertEqual(
      sections[1].items.first?.startDate,
      calendar.date(byAdding: .day, value: 1, to: sectionStart)
    )
    XCTAssertEqual(
      sections[2].items.first?.startDate,
      calendar.date(byAdding: .day, value: 2, to: sectionStart)
    )
    XCTAssertEqual(sections[2].items.first?.endDate, eventEnd)
  }

  private func makeQuery(start: Date, end: Date) -> CalendarAgentQuery {
    CalendarAgentQuery(
      startDate: start,
      endDate: end,
      showBirthdays: true,
      emptyText: "No events",
      birthdaysTitle: "Birthdays",
      birthdaysDateFormat: "dd.MM",
      birthdaysShowAge: true
    )
  }

  private func makeLogger() -> ProcessLogger {
    ProcessLogger(
      label: "easybar.calendar.core.regression.tests",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
  }
}
