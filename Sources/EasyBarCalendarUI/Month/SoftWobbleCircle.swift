import SwiftUI

/// A deterministic uneven circle that stays stable across SwiftUI redraws.
struct SoftWobbleCircle: Shape {
  func path(in rect: CGRect) -> Path {
    let point: (Double, Double) -> CGPoint = { x, y in
      CGPoint(
        x: rect.minX + rect.width * x,
        y: rect.minY + rect.height * y
      )
    }

    var path = Path()
    path.move(to: point(0.52, 0.04))
    path.addCurve(
      to: point(0.96, 0.48),
      control1: point(0.79, -0.01),
      control2: point(1.01, 0.20)
    )
    path.addCurve(
      to: point(0.48, 0.97),
      control1: point(1.00, 0.77),
      control2: point(0.76, 1.03)
    )
    path.addCurve(
      to: point(0.05, 0.49),
      control1: point(0.18, 1.00),
      control2: point(-0.02, 0.76)
    )
    path.addCurve(
      to: point(0.52, 0.04),
      control1: point(-0.01, 0.20),
      control2: point(0.24, 0.06)
    )
    path.closeSubpath()
    return path
  }
}
