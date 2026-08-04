import EasyBarCalendarPresentation
import SwiftUI

/// Draws the configured marker for today's date.
struct TodayMarker: View {
  let variant: TodayMarkerVariant
  let color: Color
  let lineWidth: Double

  private var resolvedLineWidth: Double {
    max(lineWidth, 0.8)
  }

  private var strokeStyle: StrokeStyle {
    StrokeStyle(
      lineWidth: resolvedLineWidth,
      lineCap: .round,
      lineJoin: .round
    )
  }

  var body: some View {
    switch variant {
    case .regularRoundedRectangle:
      RoundedRectangle(cornerRadius: 5)
        .inset(by: 1.5)
        .stroke(color.opacity(0.9), lineWidth: resolvedLineWidth)

    case .softWobble:
      SoftWobbleCircle()
        .stroke(color.opacity(0.92), style: strokeStyle)

    case .doubleSketch:
      ZStack {
        SoftWobbleCircle()
          .stroke(
            color.opacity(0.78),
            style: StrokeStyle(
              lineWidth: resolvedLineWidth * 0.78,
              lineCap: .round,
              lineJoin: .round
            )
          )

        SoftWobbleCircle()
          .stroke(
            color.opacity(0.52),
            style: StrokeStyle(
              lineWidth: resolvedLineWidth * 0.62,
              lineCap: .round,
              lineJoin: .round
            )
          )
          .scaleEffect(x: 0.94, y: 1.03)
          .rotationEffect(.degrees(-7))
          .offset(x: 0.5, y: -0.25)
      }

    case .openLoop:
      OpenHandDrawnLoop()
        .stroke(color.opacity(0.94), style: strokeStyle)
    }
  }
}
