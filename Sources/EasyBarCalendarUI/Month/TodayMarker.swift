import EasyBarCalendarPresentation
import EasyBarShared
import SwiftUI

/// Draws the configured marker for today's date.
struct TodayMarker: View {
  /// The variant for this today marker.
  let variant: CalendarTodayMarkerVariant
  /// The color for this today marker.
  let color: Color
  /// The line width for this today marker.
  let lineWidth: Double

  /// The resolved line width for this today marker.
  private var resolvedLineWidth: Double {
    max(lineWidth, 0.8)
  }

  /// The stroke style for this today marker.
  private var strokeStyle: StrokeStyle {
    StrokeStyle(
      lineWidth: resolvedLineWidth,
      lineCap: .round,
      lineJoin: .round
    )
  }

  /// The rendered content for this view.
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
