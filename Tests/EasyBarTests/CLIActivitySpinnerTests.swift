import XCTest

@testable import EasyBarCtl

final class CLIActivitySpinnerTests: XCTestCase {
  func testRenderLineCyclesFramesAndRemovesControlCharacters() {
    XCTAssertEqual(
      CLIActivitySpinner.renderLine(frameIndex: 0, message: "Installing caffeinate…"),
      "\r⠋ Installing caffeinate…"
    )
    XCTAssertEqual(
      CLIActivitySpinner.renderLine(frameIndex: 10, message: "Installing\nunsafe\u{001B}…"),
      "\r⠋ Installingunsafe…"
    )
  }

  func testClearLineResetsTheInteractiveTerminalRow() {
    XCTAssertEqual(CLIActivitySpinner.clearLine, "\r\u{001B}[2K")
  }
}
