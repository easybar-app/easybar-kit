import EasyBarShared
import XCTest

@testable import EasyBarKit

final class LuaTimerServiceTests: XCTestCase {
  func testRejectsNewTimerWhenActiveLimitIsReached() async throws {
    let responses = LockedState<[String]>([])
    let service = LuaTimerService(
      logger: ProcessLogger(label: "lua.timer-service.tests", minimumLevel: .error),
      maximumActiveTimers: 2,
      sendResponse: { encoded in
        responses.withLock { $0.append(encoded) }
      }
    )

    await service.schedule(
      token: "one",
      delaySeconds: 60,
      runtimeSessionID: 1,
      isRuntimeSessionActive: { _ in true }
    )
    await service.schedule(
      token: "two",
      delaySeconds: 60,
      runtimeSessionID: 1,
      isRuntimeSessionActive: { _ in true }
    )
    await service.schedule(
      token: "three",
      delaySeconds: 60,
      runtimeSessionID: 1,
      isRuntimeSessionActive: { _ in true }
    )

    let response = try XCTUnwrap(responses.withLock { $0.first })
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any]
    )
    XCTAssertEqual(object["type"] as? String, "timer_rejected")
    XCTAssertEqual(object["token"] as? String, "three")
    XCTAssertEqual(object["message"] as? String, "maximum active timer limit reached")

    await service.reset()
  }

  func testReplacingExistingTimerDoesNotConsumeAnotherSlot() async {
    let responses = LockedState<[String]>([])
    let service = LuaTimerService(
      logger: ProcessLogger(label: "lua.timer-service.tests", minimumLevel: .error),
      maximumActiveTimers: 1,
      sendResponse: { encoded in
        responses.withLock { $0.append(encoded) }
      }
    )

    for _ in 0..<2 {
      await service.schedule(
        token: "same",
        delaySeconds: 60,
        runtimeSessionID: 1,
        isRuntimeSessionActive: { _ in true }
      )
    }

    XCTAssertTrue(responses.withLock(\.isEmpty))
    await service.reset()
  }
}
