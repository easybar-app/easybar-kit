import XCTest

@testable import EasyBarKit

final class SliderValueRangeTests: XCTestCase {
  func testSliderWidthUsesValidExplicitWidth() {
    XCTAssertEqual(resolvedSliderWidth(explicit: 80, fallback: 140), 80)
  }

  func testSliderWidthFallsBackForInvalidExplicitWidth() {
    XCTAssertEqual(resolvedSliderWidth(explicit: -1, fallback: 140), 140)
    XCTAssertEqual(resolvedSliderWidth(explicit: 0, fallback: 140), 140)
    XCTAssertEqual(resolvedSliderWidth(explicit: .infinity, fallback: 140), 140)
  }

  func testSliderWidthUsesSafeMinimumForInvalidFallback() {
    XCTAssertEqual(resolvedSliderWidth(explicit: nil, fallback: .nan), 1)
  }

  func testReversedBoundsAreOrdered() {
    let range = SliderValueRange(minimum: 100, maximum: 0, step: 1)

    XCTAssertEqual(range.lowerBound, 0)
    XCTAssertEqual(range.upperBound, 100)
  }

  func testEqualBoundsReceiveMinimumSpan() {
    let range = SliderValueRange(minimum: 5, maximum: 5, step: 0)

    XCTAssertEqual(range.lowerBound, 5)
    XCTAssertEqual(range.upperBound, 5 + SliderValueRange.minimumSpan)
    XCTAssertEqual(range.step, SliderValueRange.minimumSpan)
  }

  func testNonFiniteInputsAndValuesUseSafeDefaults() {
    let range = SliderValueRange(minimum: .nan, maximum: .infinity, step: .nan)

    XCTAssertEqual(range, SliderValueRange(minimum: 0, maximum: 100, step: 0))
    XCTAssertEqual(range.clamped(.nan), 0)
    XCTAssertEqual(range.clamped(200), 100)
  }
}
