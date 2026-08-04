import SwiftUI

/// An uneven marker loop with a deliberate gap, like one quick pen stroke.
struct OpenHandDrawnLoop: Shape {
  func path(in rect: CGRect) -> Path {
    let point: (Double, Double) -> CGPoint = { x, y in
      CGPoint(
        x: rect.minX + rect.width * x,
        y: rect.minY + rect.height * y
      )
    }

    var path = Path()
    path.move(to: point(0.42, 0.04))
    path.addCurve(
      to: point(0.96, 0.48),
      control1: point(0.74, -0.01),
      control2: point(1.01, 0.19)
    )
    path.addCurve(
      to: point(0.46, 0.97),
      control1: point(1.00, 0.78),
      control2: point(0.73, 1.03)
    )
    path.addCurve(
      to: point(0.05, 0.43),
      control1: point(0.17, 1.00),
      control2: point(-0.02, 0.72)
    )
    path.addCurve(
      to: point(0.31, 0.08),
      control1: point(0.08, 0.22),
      control2: point(0.20, 0.11)
    )
    return path
  }
}
