import Foundation

/// Returns the resolved slider width.
func resolvedSliderWidth(explicit: CGFloat?, fallback: CGFloat) -> CGFloat {
  if let explicit, explicit.isFinite, explicit > 0 {
    return explicit
  }
  return fallback.isFinite && fallback > 0 ? fallback : 1
}

/// Normalizes widget-provided slider bounds before they reach SwiftUI controls.
struct SliderValueRange: Equatable {
  /// The minimum span accepted by this slider value range.
  static let minimumSpan = 0.0001

  /// The lower bound for this slider value range.
  let lowerBound: Double
  /// The upper bound for this slider value range.
  let upperBound: Double
  /// The step for this slider value range.
  let step: Double

  /// Creates a slider value range.
  init(minimum: Double, maximum: Double, step: Double) {
    let finiteMinimum = minimum.isFinite ? minimum : 0
    let finiteMaximum = maximum.isFinite ? maximum : 100
    let orderedLower = Swift.min(finiteMinimum, finiteMaximum)
    let orderedUpper = Swift.max(finiteMinimum, finiteMaximum)

    lowerBound = orderedLower
    upperBound =
      orderedUpper > orderedLower
      ? orderedUpper
      : orderedLower + Self.minimumSpan
    self.step = step.isFinite && step > 0 ? step : Self.minimumSpan
  }

  /// Clamps a potentially invalid external value into the normalized bounds.
  func clamped(_ value: Double) -> Double {
    guard value.isFinite else { return lowerBound }
    return Swift.min(Swift.max(value, lowerBound), upperBound)
  }
}
