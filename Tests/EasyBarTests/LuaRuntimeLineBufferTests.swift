import XCTest

@testable import EasyBarKit

final class LuaRuntimeLineBufferTests: XCTestCase {
  func testReportsOverflowWithoutSilentlyAcceptingDroppedLine() async {
    let buffer = LuaRuntimeLineBuffer(maximumBufferedLines: 1)

    XCTAssertEqual(buffer.enqueue("first"), .enqueued)
    XCTAssertEqual(buffer.enqueue("second"), .overflow)

    var iterator = buffer.stream.makeAsyncIterator()
    let first = await iterator.next()
    XCTAssertEqual(first, "first")
    buffer.finish()
    let finished = await iterator.next()
    XCTAssertNil(finished)
  }

  func testEnqueueAfterFinishReportsTermination() {
    let buffer = LuaRuntimeLineBuffer(maximumBufferedLines: 1)
    buffer.finish()

    XCTAssertEqual(buffer.enqueue("late"), .terminated)
  }
}
