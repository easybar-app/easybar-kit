import EasyBarShared
import XCTest

@testable import EasyBarKit

final class LuaProcessControllerEnvironmentTests: XCTestCase {
  /// Verifies Lua widgets receive the CLI owned by their active frontend.
  func testLuaEnvironmentIncludesFrontendCLIName() {
    let controller = LuaProcessController(
      logger: ProcessLogger(label: "test.lua.environment"),
      cliName: "easybar-native"
    )

    let environment = controller.luaRuntimeEnvironment(
      config: Config.makeUnloadedConfig().snapshot()
    )

    XCTAssertEqual(
      environment[SharedEnvironmentKeys.cliName],
      "easybar-native"
    )
  }
}
