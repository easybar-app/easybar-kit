import EasyBarShared
import XCTest

@testable import EasyBarKit

@MainActor
final class TimerEventsTests: XCTestCase {
  /// Verifies that two intervals for one widget can be retained, replaced, and stopped.
  func testRetainsAndReplacesDistinctSchedulesForSameWidget() {
    let eventHub = EventHub(
      logger: ProcessLogger(label: "timer-events.test", minimumLevel: .error),
      enqueueLuaEvent: { _ in }
    )
    let timerEvents = TimerEvents(
      logger: ProcessLogger(label: "timer-events.test", minimumLevel: .error),
      eventHub: eventHub
    )
    let schedules: Set<WidgetIntervalSchedule> = [
      WidgetIntervalSchedule(widgetID: "clock", interval: 3_600),
      WidgetIntervalSchedule(widgetID: "clock", interval: 7_200),
    ]

    timerEvents.replaceIntervalTimers(schedules: schedules)
    defer { timerEvents.stopAll() }

    XCTAssertEqual(timerEvents.activeIntervalSchedules, schedules)

    let remainingSchedule = WidgetIntervalSchedule(widgetID: "clock", interval: 3_600)
    timerEvents.replaceIntervalTimers(schedules: [remainingSchedule])
    XCTAssertEqual(timerEvents.activeIntervalSchedules, [remainingSchedule])

    timerEvents.stopIntervalTimers()
    XCTAssertTrue(timerEvents.activeIntervalSchedules.isEmpty)
  }
}
