import XCTest

@testable import EasyBarKit

final class WidgetHoverStateTests: XCTestCase {
  func testAggregateHoverEndsOnlyAfterLastSurfaceIsRemoved() {
    let state = WidgetHoverState()
    let first = UUID()
    let second = UUID()

    XCTAssertTrue(state.enter(widgetID: "popup", surfaceID: first))
    XCTAssertFalse(state.enter(widgetID: "popup", surfaceID: second))
    XCTAssertFalse(state.remove(widgetID: "popup", surfaceID: first))
    XCTAssertTrue(state.remove(widgetID: "popup", surfaceID: second))
    XCTAssertTrue(state.enter(widgetID: "popup", surfaceID: UUID()))
  }
}
