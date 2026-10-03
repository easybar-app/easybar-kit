import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class RuntimeReloadPreflightTests: XCTestCase {
  private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var socketPaths: [String] = []
    private var lockRebindRequested = false

    func recordSocketPath(_ path: String) {
      lock.withLock { socketPaths.append(path) }
    }

    func recordLockRebind() {
      lock.withLock { lockRebindRequested = true }
    }

    func snapshot() -> (socketPaths: [String], lockRebindRequested: Bool) {
      lock.withLock { (socketPaths, lockRebindRequested) }
    }
  }

  /// Verifies that a failed socket rebind restores config state and skips lock rebinding.
  func testSocketFailureRestoresPreviousConfigState() async {
    let configManager = ConfigManager(config: Config.makeUnloadedConfig())
    let result = await configManager.loadInitialConfig()
    let recorder = Recorder()

    let applied = await RuntimeReloadPreflight.apply(
      result: result,
      reloadSocket: { path in
        recorder.recordSocketPath(path)
        return .failed(requestedPath: path)
      },
      restorePreviousState: {
        await configManager.restorePreviousState()
      },
      logger: ProcessLogger(label: "runtime.reload.preflight.tests", minimumLevel: .error),
      rebindInstanceLock: { _ in
        recorder.recordLockRebind()
        return true
      }
    )

    let recorded = recorder.snapshot()
    XCTAssertFalse(applied)
    XCTAssertEqual(
      recorded.socketPaths,
      [SharedPathDefaults.easyBarSocketPath(in: result.snapshot.app.runtimeDirectory)]
    )
    XCTAssertFalse(recorded.lockRebindRequested)
  }
}
