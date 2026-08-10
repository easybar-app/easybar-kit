import SwiftUI

struct SparklineCanvas: View {

  let values: [Double]
  let tint: Color
  let lineWidth: CGFloat

  private let minValue = 0.0
  private let maxValue = 100.0

  /// Draws the sparkline path when enough points exist.
  var body: some View {
    Canvas { context, size in
      guard let path = makePath(size: size) else { return }

      context.stroke(
        path,
        with: .color(tint),
        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
      )
    }
    .drawingGroup()
  }

  /// Builds the sparkline path for the current values.
  private func makePath(size: CGSize) -> Path? {
    guard values.count >= 2 else { return nil }

    var path = Path()

    for (index, point) in points(size: size).enumerated() {
      if index == 0 {
        path.move(to: point)
        continue
      }

      path.addLine(to: point)
    }

    return path
  }

  /// Returns the sparkline points normalized against the fixed CPU range.
  private func points(size: CGSize) -> [CGPoint] {
    let maxIndex = CGFloat(max(values.count - 1, 1))

    return values.enumerated().map { index, value in
      let x = CGFloat(index) / maxIndex * size.width
      let y = size.height - CGFloat(normalizedValue(value)) * size.height
      return CGPoint(x: x, y: y)
    }
  }

  /// Returns one value normalized into the 0...1 range.
  private func normalizedValue(_ value: Double) -> Double {
    let span = max(maxValue - minValue, 0.0001)
    let clamped = min(max(value, minValue), maxValue)
    return (clamped - minValue) / span
  }
}
