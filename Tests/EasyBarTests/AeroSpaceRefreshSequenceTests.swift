import XCTest

@testable import EasyBarKit

final class AeroSpaceRefreshSequenceTests: XCTestCase {
  func testNewerRefreshSupersedesOlderRefreshInSameGeneration() {
    var sequence = AeroSpaceRefreshSequence()
    let older = sequence.issue(generation: 4)
    let newer = sequence.issue(generation: 4)

    XCTAssertFalse(sequence.isCurrent(older, generation: 4))
    XCTAssertTrue(sequence.isCurrent(newer, generation: 4))
  }

  func testLifecycleGenerationInvalidatesLatestRefresh() {
    var sequence = AeroSpaceRefreshSequence()
    let token = sequence.issue(generation: 4)

    XCTAssertFalse(sequence.isCurrent(token, generation: 5))
  }
}
