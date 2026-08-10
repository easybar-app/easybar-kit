import XCTest

@testable import EasyBarKit

final class BuiltInSurfacePolicyTests: XCTestCase {
  func testAllAllowsEveryBuiltInRegistration() {
    XCTAssertTrue(EasyBarBuiltInSurfacePolicy.all.allows("inbox"))
    XCTAssertTrue(EasyBarBuiltInSurfacePolicy.all.allows("calendar"))
    XCTAssertTrue(EasyBarBuiltInSurfacePolicy.all.allows("battery"))
  }

  func testInboxOnlyAllowsOnlyInbox() {
    XCTAssertTrue(EasyBarBuiltInSurfacePolicy.inboxOnly.allows("inbox"))
    XCTAssertFalse(EasyBarBuiltInSurfacePolicy.inboxOnly.allows("calendar"))
    XCTAssertFalse(EasyBarBuiltInSurfacePolicy.inboxOnly.allows("battery"))
  }

  func testNoneRejectsAllBuiltInRegistrations() {
    XCTAssertFalse(EasyBarBuiltInSurfacePolicy.none.allows("inbox"))
    XCTAssertFalse(EasyBarBuiltInSurfacePolicy.none.allows("calendar"))
  }
}
