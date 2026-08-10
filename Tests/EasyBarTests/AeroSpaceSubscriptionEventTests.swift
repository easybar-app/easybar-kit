import Foundation
import XCTest

@testable import EasyBarKit

final class AeroSpaceSubscriptionEventTests: XCTestCase {
  func testDecodeParsesAeroSpaceEventName() throws {
    let event = try JSONDecoder().decode(
      AeroSpaceSubscriptionEvent.self,
      from: Data(#"{"_event":"focused-workspace-changed","workspace":"2"}"#.utf8)
    )

    XCTAssertEqual(event.name, AeroSpaceSubscriptionEvent.Name.focusedWorkspaceChanged)
    XCTAssertEqual(event.workspace, "2")
    XCTAssertEqual(event.appEvent, .workspaceChange)
  }

  func testAppEventMappingCoversSemanticEasyBarEvents() {
    XCTAssertEqual(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.focusChanged).appEvent,
      .focusChange
    )
    XCTAssertEqual(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.focusedWorkspaceChanged)
        .appEvent,
      .workspaceChange
    )
    XCTAssertEqual(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.focusedMonitorChanged)
        .appEvent,
      .workspaceChange
    )
    XCTAssertNil(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.modeChanged).appEvent
    )
    XCTAssertNil(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.windowDetected).appEvent
    )
    XCTAssertNil(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.bindingTriggered).appEvent
    )
  }

  func testSubscribeArgumentsUseAllEventsAndInitialState() {
    XCTAssertEqual(
      AeroSpaceSubscriptionEvent.subscribeArguments,
      ["subscribe", "--all"]
    )
  }

  func testFocusChangesUseFastFocusAndDebouncedSnapshotPolicy() {
    XCTAssertEqual(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.focusChanged)
        .refreshPolicy,
      .fastFocusAndDebouncedSnapshot
    )
  }

  func testWorkspaceChangesUseFastWorkspaceAndImmediateSnapshotPolicy() {
    XCTAssertEqual(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.focusedWorkspaceChanged)
        .refreshPolicy,
      .fastWorkspaceAndImmediateSnapshot
    )
  }

  func testMonitorChangesRefreshImmediately() {
    XCTAssertEqual(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.focusedMonitorChanged)
        .refreshPolicy,
      .immediateSnapshot
    )
  }

  func testOtherEventsUseDebouncedSnapshotPolicy() {
    XCTAssertEqual(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.windowDetected).refreshPolicy,
      .debouncedSnapshot
    )
    XCTAssertEqual(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.modeChanged).refreshPolicy,
      .debouncedSnapshot
    )
    XCTAssertEqual(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.bindingTriggered)
        .refreshPolicy,
      .debouncedSnapshot
    )
  }

  func testFullSnapshotDebounceIsOneHundredTwentyMilliseconds() {
    XCTAssertEqual(AeroSpaceSubscriptionEvent.fullSnapshotDebounceNanoseconds, 120_000_000)
  }
}
