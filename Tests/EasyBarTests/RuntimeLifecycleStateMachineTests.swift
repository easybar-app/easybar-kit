import XCTest

@testable import EasyBarKit

final class RuntimeLifecycleStateMachineTests: XCTestCase {
  func testStartAdvancesGenerationAndRejectsDuplicateStart() {
    var lifecycle = RuntimeLifecycleStateMachine()

    guard let generation = lifecycle.start() else {
      return XCTFail("Expected lifecycle to start")
    }

    XCTAssertEqual(generation, 1)
    XCTAssertEqual(lifecycle.generation, generation)

    XCTAssertNil(lifecycle.start())
  }

  func testStopCancelsStartupAndLifecycleWork() {
    var lifecycle = RuntimeLifecycleStateMachine()

    guard let generation = lifecycle.start() else {
      return XCTFail("Expected lifecycle to start")
    }

    XCTAssertTrue(lifecycle.stop())
    XCTAssertFalse(lifecycle.canContinueStartup(generation: generation))
    XCTAssertFalse(lifecycle.canContinueLifecycleWork(generation: generation))
    XCTAssertFalse(lifecycle.stop())
  }

  func testLifecycleOperationsAreRejectedWhileStopped() {
    var lifecycle = RuntimeLifecycleStateMachine()

    guard case .notStarted = lifecycle.begin(.reloadConfig) else {
      return XCTFail("Expected reload to be rejected while stopped")
    }

    guard case .notStarted = lifecycle.begin(.restartLuaRuntime) else {
      return XCTFail("Expected Lua restart to be rejected while stopped")
    }
  }

  func testBusyLifecycleOperationQueuesDuplicateReloadOnce() {
    var lifecycle = RuntimeLifecycleStateMachine()
    _ = lifecycle.start()

    guard case .started = lifecycle.begin(.reloadConfig) else {
      return XCTFail("Expected first reload to start")
    }

    guard case .queued = lifecycle.begin(.reloadConfig) else {
      return XCTFail("Expected duplicate reload to queue")
    }

    guard case .queued = lifecycle.begin(.reloadConfig) else {
      return XCTFail("Expected repeated duplicate reload to stay queued")
    }

    XCTAssertEqual(lifecycle.finish(), .reloadConfig)
    XCTAssertNil(lifecycle.finish())
  }

  func testQueuedReloadTakesPriorityOverQueuedLuaRestart() {
    var lifecycle = RuntimeLifecycleStateMachine()
    _ = lifecycle.start()

    guard case .started = lifecycle.begin(.restartLuaRuntime) else {
      return XCTFail("Expected first restart to start")
    }

    guard case .queued = lifecycle.begin(.restartLuaRuntime) else {
      return XCTFail("Expected duplicate restart to queue")
    }

    guard case .queued = lifecycle.begin(.reloadConfig) else {
      return XCTFail("Expected reload to queue while restart is active")
    }

    XCTAssertEqual(lifecycle.finish(), .reloadConfig)
    XCTAssertEqual(lifecycle.finish(), .restartLuaRuntime)
    XCTAssertNil(lifecycle.finish())
  }
}
