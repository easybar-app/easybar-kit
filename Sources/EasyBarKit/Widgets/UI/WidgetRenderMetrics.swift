import CoreGraphics

/// Normalizes untrusted widget metrics before passing them to rendering APIs.
enum WidgetRenderMetrics {
  /// Returns the dimension.
  static func dimension(_ value: Double?) -> CGFloat? {
    guard let value, value.isFinite else { return nil }
    return CGFloat(max(0, value))
  }

  /// Returns the nonnegative.
  static func nonnegative(_ value: Double?, fallback: Double) -> CGFloat {
    return dimension(value) ?? CGFloat(max(0, fallback))
  }

  /// Returns the positive.
  static func positive(_ value: Double?, fallback: Double) -> CGFloat {
    guard let value, value.isFinite, value > 0 else {
      return CGFloat(max(fallback, .leastNonzeroMagnitude))
    }
    return CGFloat(value)
  }

  /// Returns the opacity.
  static func opacity(_ value: Double?) -> Double {
    guard let value, value.isFinite else { return 1 }
    return min(max(value, 0), 1)
  }

  /// Returns the finite.
  static func finite(_ value: Double?, fallback: Double = 0) -> CGFloat {
    guard let value, value.isFinite else { return CGFloat(fallback) }
    return CGFloat(value)
  }

  /// Returns the unit interval.
  static func unitInterval(_ value: Double?, fallback: Double = 0) -> CGFloat {
    return min(max(finite(value, fallback: fallback), 0), 1)
  }
}
