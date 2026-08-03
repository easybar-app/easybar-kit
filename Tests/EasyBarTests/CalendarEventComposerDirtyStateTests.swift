import Combine
import EasyBarCalendarPresentation
import EasyBarShared
import XCTest

@testable import EasyBarCalendarUI

final class CalendarEventComposerDirtyStateTests: XCTestCase {
  @MainActor
  func testPreparedCreateFormBecomesDirtyOnlyWhenEditableValuesChange() {
    let snapshots = CurrentValueSubject<CalendarAgentSnapshot?, Never>(nil)
    let composer = makeComposer(snapshotPublisher: snapshots.eraseToAnyPublisher())
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    composer.prepare(defaultDate: date)
    XCTAssertFalse(composer.hasUnsavedChanges)

    composer.title = "Planning"
    XCTAssertTrue(composer.hasUnsavedChanges)

    composer.title = ""
    XCTAssertFalse(composer.hasUnsavedChanges)
  }

  @MainActor
  func testCalendarSnapshotPopulationDoesNotDirtyUntouchedForm() async {
    let snapshots = CurrentValueSubject<CalendarAgentSnapshot?, Never>(nil)
    let composer = makeComposer(snapshotPublisher: snapshots.eraseToAnyPublisher())
    let calendarSelected = expectation(description: "Writable calendar selected")
    let observation = composer.$selectedCalendarID
      .filter { $0 == "work" }
      .sink { _ in calendarSelected.fulfill() }

    composer.prepare(defaultDate: Date(timeIntervalSince1970: 1_800_000_000))
    snapshots.send(makeSnapshot())
    await fulfillment(of: [calendarSelected], timeout: 1)

    XCTAssertEqual(composer.selectedCalendarID, "work")
    XCTAssertFalse(composer.hasUnsavedChanges)
    withExtendedLifetime(observation) {}
  }

  @MainActor
  func testPreparedEditFormTracksAndClearsRevertedChanges() {
    let snapshots = CurrentValueSubject<CalendarAgentSnapshot?, Never>(makeSnapshot())
    let composer = makeComposer(snapshotPublisher: snapshots.eraseToAnyPublisher())
    let event = CalendarAgentEvent(
      id: "event-1",
      eventIdentifier: "eventkit-1",
      title: "Planning",
      startDate: Date(timeIntervalSince1970: 1_800_000_000),
      endDate: Date(timeIntervalSince1970: 1_800_003_600),
      isAllDay: false,
      calendarID: "work",
      calendarName: "Work",
      location: "Office"
    )

    composer.prepare(event: event)
    XCTAssertFalse(composer.hasUnsavedChanges)

    composer.location = "Remote"
    XCTAssertTrue(composer.hasUnsavedChanges)

    composer.location = "Office"
    XCTAssertFalse(composer.hasUnsavedChanges)
  }

  @MainActor
  private func makeComposer(
    snapshotPublisher: AnyPublisher<CalendarAgentSnapshot?, Never>
  ) -> CalendarEventComposer {
    CalendarEventComposer(
      config: makeConfig(),
      snapshotPublisher: snapshotPublisher,
      refreshSnapshots: {},
      createEvent: { _, completion in completion(true, nil) },
      updateEvent: { _, completion in completion(true, nil) },
      deleteEvent: { _, completion in completion(true, nil) },
      openCalendarApp: {}
    )
  }

  private func makeSnapshot() -> CalendarAgentSnapshot {
    CalendarAgentSnapshot(
      accessGranted: true,
      permissionState: "authorized",
      generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
      writableCalendars: [CalendarAgentWritableCalendar(id: "work", title: "Work")],
      events: [],
      sections: []
    )
  }

  private func makeConfig() -> CalendarComposerConfig {
    CalendarComposerConfig(
      createTitle: "Create",
      editTitle: "Edit",
      saveLabel: "Save",
      updateLabel: "Update",
      removeLabel: "Remove",
      cancelLabel: "Cancel",
      deleteConfirmationTitle: "Delete?",
      deleteConfirmationMessage: "Cannot undo.",
      openCalendarLabel: "Calendar",
      titleLabel: "Title",
      titlePlaceholder: "What?",
      locationLabel: "Location",
      locationPlaceholder: "Where?",
      calendarLabel: "Calendar",
      allDayLabel: "All day",
      startLabel: "Start",
      endLabel: "End",
      travelTimeLabel: "Travel time",
      alertLabel: "Alert",
      addAlertLabel: "Add alert",
      defaultCalendarName: nil,
      defaultAlert: "1_hour",
      defaultTravelTime: "none",
      alertLabels: [:],
      travelTimeLabels: [:],
      paddingX: 14,
      paddingY: 14,
      backgroundColorHex: "#000000",
      borderColorHex: "#111111",
      borderWidth: 1,
      cornerRadius: 10,
      headerTextColorHex: "#ffffff",
      secondaryTextColorHex: "#cccccc"
    )
  }
}
