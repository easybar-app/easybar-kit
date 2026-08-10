import SwiftUI

/// Draws an Apple-like Wi-Fi indicator using two arcs and a dot.
struct WiFiSignalCanvas: View {

  let signalLevel: Int
  let state: String
  let activeColor: Color
  let inactiveColor: Color
  let slashColor: Color

  /// Converts an untrusted widget value into the indicator's supported range.
  static func normalizedSignalLevel(_ value: Double?) -> Int {
    guard let value, value.isFinite else { return 0 }
    return Int(min(max(value, 0), 3))
  }

  /// Draws the Wi-Fi indicator for the current state.
  var body: some View {
    Canvas { context, size in
      let level = max(0, min(signalLevel, 3))
      let lineWidth = max(1.7, min(size.width, size.height) * 0.15)

      drawArc(
        context: &context,
        size: size,
        scale: 1.0,
        color: outerArcColor(for: level),
        lineWidth: lineWidth
      )

      drawArc(
        context: &context,
        size: size,
        scale: 0.62,
        color: innerArcColor(for: level),
        lineWidth: lineWidth
      )

      drawDot(
        context: &context,
        size: size,
        color: dotColor(for: level)
      )

      if isDisconnected {
        drawSlash(
          context: &context,
          size: size,
          color: slashColor,
          lineWidth: lineWidth
        )
      }

      if isDenied {
        drawExclamation(
          context: &context,
          size: size,
          color: activeColor,
          lineWidth: lineWidth
        )
      }
    }
    .drawingGroup()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Wi-Fi")
    .accessibilityValue(accessibilityValue)
  }

  /// Returns the connection state announced by assistive technologies.
  private var accessibilityValue: String {
    if isDenied {
      return "Location access denied"
    }

    if isDisconnected {
      return "Disconnected"
    }

    return "Connected, signal \(max(0, min(signalLevel, 3))) of 3"
  }

  /// Returns whether the indicator should render as connected.
  private var isConnected: Bool {
    return state == "connected"
  }

  /// Returns whether the indicator should render as disconnected.
  private var isDisconnected: Bool {
    return state == "disconnected"
  }

  /// Returns whether the indicator should render as denied.
  private var isDenied: Bool {
    return state == "denied"
  }

  /// Returns the resolved outer-arc color for one signal level.
  private func outerArcColor(for level: Int) -> Color {
    guard isConnected else { return inactiveColor }
    return level >= 3 ? activeColor : inactiveColor
  }

  /// Returns the resolved inner-arc color for one signal level.
  private func innerArcColor(for level: Int) -> Color {
    guard isConnected else { return inactiveColor }
    return level >= 2 ? activeColor : inactiveColor
  }

  /// Returns the resolved dot color for one signal level.
  private func dotColor(for level: Int) -> Color {
    guard isConnected else { return inactiveColor }
    return level >= 1 ? activeColor : inactiveColor
  }

  /// Draws one Wi-Fi arc.
  private func drawArc(
    context: inout GraphicsContext,
    size: CGSize,
    scale: CGFloat,
    color: Color,
    lineWidth: CGFloat
  ) {
    let horizontalInset = lineWidth * 0.45
    let maxRadiusX = (size.width / 2) - horizontalInset
    let maxRadiusY = size.height * 0.98
    let baseRadius = min(maxRadiusX, maxRadiusY)
    let radius = baseRadius * scale

    let center = CGPoint(
      x: size.width / 2,
      y: size.height + lineWidth * 0.02
    )

    var path = Path()
    path.addArc(
      center: center,
      radius: radius,
      startAngle: .degrees(228),
      endAngle: .degrees(312),
      clockwise: false
    )

    context.stroke(
      path,
      with: .color(color),
      style: StrokeStyle(
        lineWidth: lineWidth,
        lineCap: .round,
        lineJoin: .round
      )
    )
  }

  /// Draws the Wi-Fi bottom dot.
  private func drawDot(
    context: inout GraphicsContext,
    size: CGSize,
    color: Color
  ) {
    let diameter = max(2.8, min(size.width, size.height) * 0.21)
    let y = size.height - diameter - 0.85

    let rect = CGRect(
      x: (size.width - diameter) / 2,
      y: y,
      width: diameter,
      height: diameter
    )

    context.fill(
      Path(ellipseIn: rect),
      with: .color(color)
    )
  }

  /// Draws the disconnected slash overlay.
  private func drawSlash(
    context: inout GraphicsContext,
    size: CGSize,
    color: Color,
    lineWidth: CGFloat
  ) {
    var path = Path()
    path.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.88))
    path.addLine(to: CGPoint(x: size.width * 0.81, y: size.height * 0.18))

    context.stroke(
      path,
      with: .color(color),
      style: StrokeStyle(
        lineWidth: max(1.45, lineWidth * 0.9),
        lineCap: .round
      )
    )
  }

  /// Draws the denied-state exclamation overlay.
  private func drawExclamation(
    context: inout GraphicsContext,
    size: CGSize,
    color: Color,
    lineWidth: CGFloat
  ) {
    let stemWidth = max(1.3, lineWidth * 0.86)
    let x = size.width * 0.84

    var stem = Path()
    stem.move(to: CGPoint(x: x, y: size.height * 0.18))
    stem.addLine(to: CGPoint(x: x, y: size.height * 0.45))

    context.stroke(
      stem,
      with: .color(color),
      style: StrokeStyle(lineWidth: stemWidth, lineCap: .round)
    )

    let dotDiameter = max(1.9, min(size.width, size.height) * 0.11)
    let dotRect = CGRect(
      x: x - dotDiameter / 2,
      y: size.height * 0.57,
      width: dotDiameter,
      height: dotDiameter
    )

    context.fill(
      Path(ellipseIn: dotRect),
      with: .color(color)
    )
  }
}
