import XCTest

@testable import EasyBarKit

final class WidgetRenderMetricsTests: XCTestCase {
  func testDimensionRejectsNonFiniteAndClampsNegativeValues() {
    XCTAssertNil(WidgetRenderMetrics.dimension(nil))
    XCTAssertNil(WidgetRenderMetrics.dimension(.nan))
    XCTAssertNil(WidgetRenderMetrics.dimension(.infinity))
    XCTAssertEqual(WidgetRenderMetrics.dimension(-12), 0)
    XCTAssertEqual(WidgetRenderMetrics.dimension(12), 12)
  }

  func testPositiveUsesFallbackForInvalidValues() {
    XCTAssertEqual(WidgetRenderMetrics.positive(-1, fallback: 14), 14)
    XCTAssertEqual(WidgetRenderMetrics.positive(0, fallback: 14), 14)
    XCTAssertEqual(WidgetRenderMetrics.positive(.nan, fallback: 14), 14)
    XCTAssertEqual(WidgetRenderMetrics.positive(9, fallback: 14), 9)
  }

  func testOpacityIsFiniteAndClamped() {
    XCTAssertEqual(WidgetRenderMetrics.opacity(nil), 1)
    XCTAssertEqual(WidgetRenderMetrics.opacity(.nan), 1)
    XCTAssertEqual(WidgetRenderMetrics.opacity(-0.5), 0)
    XCTAssertEqual(WidgetRenderMetrics.opacity(0.4), 0.4)
    XCTAssertEqual(WidgetRenderMetrics.opacity(2), 1)
  }

  func testFinitePreservesSignedValuesAndRejectsNonFiniteValues() {
    XCTAssertEqual(WidgetRenderMetrics.finite(-2), -2)
    XCTAssertEqual(WidgetRenderMetrics.finite(.nan), 0)
    XCTAssertEqual(WidgetRenderMetrics.finite(.infinity, fallback: 3), 3)
  }

  func testUnitIntervalRejectsNonFiniteAndClampsValues() {
    XCTAssertEqual(WidgetRenderMetrics.unitInterval(.nan), 0)
    XCTAssertEqual(WidgetRenderMetrics.unitInterval(-1), 0)
    XCTAssertEqual(WidgetRenderMetrics.unitInterval(0.4), 0.4)
    XCTAssertEqual(WidgetRenderMetrics.unitInterval(2), 1)
  }
}
