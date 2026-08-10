import XCTest

@testable import EasyBarKit

final class ConfigSnapshotTests: XCTestCase {
  private var originalSnapshot: ConfigSnapshot!

  /// Prepares isolated state before each test.
  override func setUpWithError() throws {
    try super.setUpWithError()
    originalSnapshot = Config.makeUnloadedConfig().snapshot()
  }

  /// Restores state mutated by the test fixture.
  override func tearDownWithError() throws {
    Config.makeUnloadedConfig().apply(originalSnapshot)
    try super.tearDownWithError()
  }

  /// Verifies that apply restores app bar and builtin state from snapshot.
  func testApplyRestoresAppBarAndBuiltinStateFromSnapshot() {
    let config = Config.makeUnloadedConfig()

    config.runtimeDirectory = "/tmp/runtime-before"
    config.widgetsPath = "/tmp/widgets-before"
    config.loggingLevel = .debug
    config.barHeight = 41
    config.barBackgroundHex = "#112233"
    config.builtinTime.placement.enabled = true
    config.builtinTime.placement.position = .left
    config.builtinTime.content.format = "HH:mm:ss"
    config.builtinCPU.enabled = true
    config.builtinCPU.historySize = 18

    let snapshot = config.snapshot()

    config.runtimeDirectory = "/tmp/runtime-after"
    config.widgetsPath = "/tmp/widgets-after"
    config.loggingLevel = .error
    config.barHeight = 22
    config.barBackgroundHex = "#abcdef"
    config.builtinTime.placement.enabled = false
    config.builtinTime.placement.position = .right
    config.builtinTime.content.format = "mm"
    config.builtinCPU.enabled = false
    config.builtinCPU.historySize = 4

    config.apply(snapshot)

    XCTAssertEqual(config.runtimeDirectory, "/tmp/runtime-before")
    XCTAssertEqual(config.widgetsPath, "/tmp/widgets-before")
    XCTAssertEqual(config.loggingLevel, .debug)
    XCTAssertEqual(config.barHeight, 41)
    XCTAssertEqual(config.barBackgroundHex, "#112233")
    XCTAssertTrue(config.builtinTime.placement.enabled)
    XCTAssertEqual(config.builtinTime.placement.position, .left)
    XCTAssertEqual(config.builtinTime.content.format, "HH:mm:ss")
    XCTAssertTrue(config.builtinCPU.enabled)
    XCTAssertEqual(config.builtinCPU.historySize, 18)
  }
}
