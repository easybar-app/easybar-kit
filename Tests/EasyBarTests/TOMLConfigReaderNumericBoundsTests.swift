import SwiftTOMLEdit
import XCTest

final class TOMLConfigReaderNumericBoundsTests: XCTestCase {
  private enum Failure: Error, Equatable {
    case invalidType(path: String, expected: String, actual: String)
    case invalidValue(path: String, message: String)
  }

  func testLargeWholeNumberBoundProducesAnErrorWithoutOverflowing() {
    let reader = TOMLConfigReader<Failure>(
      table: TOMLTable(["value": .double(0)]),
      path: "config",
      makeInvalidTypeError: { path, expected, actual in
        .invalidType(path: path, expected: expected, actual: actual)
      },
      makeInvalidValueError: { path, message in
        .invalidValue(path: path, message: message)
      }
    )

    XCTAssertThrowsError(
      try reader.double(
        "value",
        fallback: 0,
        minimum: Double(Int.max)
      )
    ) { error in
      guard let failure = error as? Failure else {
        return XCTFail("Expected a typed reader failure, got \(error)")
      }
      guard case .invalidValue(let path, let message) = failure else {
        return XCTFail("Expected an invalid-value failure, got \(failure)")
      }

      XCTAssertEqual(path, "config.value")
      XCTAssertTrue(message.contains("expected a value greater than or equal to"))
      XCTAssertTrue(message.contains("9223372036854775808"))
    }
  }
}
