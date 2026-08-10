import EasyBarShared
import XCTest

@testable import EasyBarKit

private actor BlockingLuaEventSend {
  private var blocked = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func block() async {
    blocked = true
    let waiters = enteredWaiters
    enteredWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }

    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
  }

  func waitUntilBlocked() async {
    guard !blocked else { return }
    await withCheckedContinuation { continuation in
      enteredWaiters.append(continuation)
    }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

final class LuaEventSinkTests: XCTestCase {
  func testMustDeliverOverflowSuspendsQueueUntilReset() async {
    let send = BlockingLuaEventSend()
    let overflowCounts = LockedState<[Int]>([])
    let queueDepths = LockedState<[Int]>([])
    let sink = LuaEventSink(
      logger: ProcessLogger(label: "lua.event-sink.tests", minimumLevel: .error),
      maximumMustDeliverPayloads: 2,
      sendPayload: { _ in await send.block() },
      recordQueueDepth: { depth in queueDepths.withLock { $0.append(depth) } },
      handleMustDeliverOverflow: { count, _ in
        overflowCounts.withLock { $0.append(count) }
      }
    )

    sink.enqueue(.app(.systemWoke, source: "first"))
    await send.waitUntilBlocked()
    sink.enqueue(.app(.systemWoke, source: "second"))
    sink.enqueue(.app(.systemWoke, source: "third"))
    sink.enqueue(.app(.systemWoke, source: "overflow"))

    XCTAssertEqual(overflowCounts.withLock { $0 }, [3])
    XCTAssertTrue(sink.isSuspendedAfterOverflow)
    XCTAssertEqual(sink.queuedPayloadCount, 0)
    XCTAssertEqual(queueDepths.withLock { $0.last }, 0)

    sink.enqueue(.app(.systemWoke, source: "ignored"))
    XCTAssertEqual(overflowCounts.withLock { $0 }, [3])

    sink.reset()
    XCTAssertFalse(sink.isSuspendedAfterOverflow)
    XCTAssertEqual(sink.queuedPayloadCount, 0)
    await send.release()
  }
}
