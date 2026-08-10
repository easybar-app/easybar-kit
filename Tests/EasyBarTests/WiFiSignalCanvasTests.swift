import XCTest

@testable import EasyBarKit

@MainActor
final class WiFiSignalCanvasTests: XCTestCase {
  func testNormalizedSignalLevelRejectsNonFiniteValues() {
    XCTAssertEqual(WiFiSignalCanvas.normalizedSignalLevel(nil), 0)
    XCTAssertEqual(WiFiSignalCanvas.normalizedSignalLevel(.nan), 0)
    XCTAssertEqual(WiFiSignalCanvas.normalizedSignalLevel(.infinity), 0)
    XCTAssertEqual(WiFiSignalCanvas.normalizedSignalLevel(-.infinity), 0)
  }

  func testNormalizedSignalLevelClampsBeforeConvertingToInt() {
    XCTAssertEqual(WiFiSignalCanvas.normalizedSignalLevel(-Double.greatestFiniteMagnitude), 0)
    XCTAssertEqual(WiFiSignalCanvas.normalizedSignalLevel(1.9), 1)
    XCTAssertEqual(WiFiSignalCanvas.normalizedSignalLevel(Double.greatestFiniteMagnitude), 3)
  }
}
