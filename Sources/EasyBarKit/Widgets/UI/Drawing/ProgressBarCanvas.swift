import SwiftUI

struct ProgressBarCanvas: View {

  let value: Double
  let minValue: Double
  let maxValue: Double
  let tint: Color

  /// Draws the progress track and fill.
  var body: some View {
    Canvas { context, size in
      context.fill(trackPath(size: size), with: .color(.white.opacity(0.12)))
      context.fill(fillPath(size: size), with: .color(tint))
    }
    .drawingGroup()
  }

  /// Builds the background track path.
  private func trackPath(size: CGSize) -> Path {
    Path(
      roundedRect: CGRect(origin: .zero, size: size),
      cornerRadius: cornerRadius(size: size)
    )
  }

  /// Builds the filled progress path.
  private func fillPath(size: CGSize) -> Path {
    Path(
      roundedRect: fillRect(size: size),
      cornerRadius: cornerRadius(size: size)
    )
  }

  /// Returns the filled progress rect.
  private func fillRect(size: CGSize) -> CGRect {
    return CGRect(x: 0, y: 0, width: fillWidth(size: size), height: size.height)
  }

  /// Returns the filled width clamped to the canvas width.
  private func fillWidth(size: CGSize) -> CGFloat {
    return max(0, min(size.width, size.width * normalizedValue))
  }

  /// Returns the rounded track corner radius.
  private func cornerRadius(size: CGSize) -> CGFloat {
    return size.height / 2
  }

  /// Returns the current value normalized into the 0...1 range.
  private var normalizedValue: Double {
    let span = max(maxValue - minValue, 0.0001)
    let clamped = min(max(value, minValue), maxValue)
    return (clamped - minValue) / span
  }
}
