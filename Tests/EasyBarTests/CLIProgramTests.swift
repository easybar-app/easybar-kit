import EasyBarShared
import XCTest

@testable import EasyBarCtl

final class CLIProgramTests: XCTestCase {
  func testDefaultProgramUsesEasyBarIdentity() {
    let program = CLIProgram(environment: [:])

    XCTAssertEqual(program.commandName, "easybar")
    XCTAssertEqual(program.displayName, "EasyBar")
    XCTAssertTrue(program.supportsHelperAgents)
  }

  func testFrontendProgramUsesEnvironmentIdentity() throws {
    let program = CLIProgram(
      environment: [
        SharedEnvironmentKeys.cliName: "easybar-native",
        SharedEnvironmentKeys.cliDisplayName: "EasyBar Native",
        SharedEnvironmentKeys.cliSupportsHelperAgents: "false",
      ]
    )

    XCTAssertEqual(program.commandName, "easybar-native")
    XCTAssertEqual(program.displayName, "EasyBar Native")
    XCTAssertFalse(program.supportsHelperAgents)
    XCTAssertFalse(program.isVisible(commandPath: ["agent"]))
    XCTAssertTrue(program.isVisible(commandPath: ["widgets", "install"]))
    XCTAssertThrowsError(try program.validate(action: .restartAgent(.calendar)))
  }
}
