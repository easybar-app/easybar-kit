import AppKit
import SwiftUI

/// Custom progress-style slider used by native and scripted widgets.
struct ProgressSliderWidgetView: View {
  let rootWidgetID: String
  let targetWidgetID: String
  let accessibilityLabel: String
  let minValue: Double
  let maxValue: Double
  let step: Double
  let externalValue: Double
  let tint: Color
  let width: CGFloat?

  @State private var value: Double
  @State private var isDragging = false
  @Environment(\.appViewServices) private var appViewServices

  private var range: SliderValueRange {
    SliderValueRange(minimum: minValue, maximum: maxValue, step: step)
  }

  init(
    rootWidgetID: String,
    targetWidgetID: String,
    accessibilityLabel: String,
    minValue: Double,
    maxValue: Double,
    step: Double,
    value: Double,
    tint: Color,
    width: CGFloat? = nil
  ) {
    self.rootWidgetID = rootWidgetID
    self.targetWidgetID = targetWidgetID
    self.accessibilityLabel = accessibilityLabel
    self.minValue = minValue
    self.maxValue = maxValue
    self.step = step
    self.externalValue = value
    self.tint = tint
    self.width = width
    let range = SliderValueRange(minimum: minValue, maximum: maxValue, step: step)
    _value = State(initialValue: range.clamped(value))
  }

  /// Renders the draggable progress slider.
  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.white.opacity(0.12))
          .frame(height: 8)

        Capsule()
          .fill(tint)
          .frame(width: max(0, geometry.size.width * normalizedValue), height: 8)

        Circle()
          .fill(tint)
          .frame(width: 12, height: 12)
          .offset(x: knobOffset(in: geometry.size.width) - 6)
      }
      .contentShape(Rectangle())
      .overlay {
        ProgressSliderInteractionSurface(
          onPreview: { x in
            isDragging = true

            let newValue = value(for: x, width: geometry.size.width)
            value = newValue

            guard let eventHub = appViewServices?.eventHub else { return }
            WidgetEventDispatcher.shared.enqueue {
              await eventHub.emitWidgetEvent(
                .sliderPreview,
                widgetID: rootWidgetID,
                targetWidgetID: targetWidgetID,
                value: newValue
              )
            }
          },
          onCommit: { x in
            let newValue = value(for: x, width: geometry.size.width)
            value = newValue
            isDragging = false

            guard let eventHub = appViewServices?.eventHub else { return }
            WidgetEventDispatcher.shared.enqueue {
              await eventHub.emitWidgetEvent(
                .sliderChanged,
                widgetID: rootWidgetID,
                targetWidgetID: targetWidgetID,
                value: newValue
              )
            }
          }
        )
        .accessibilityHidden(true)
      }
    }
    .frame(width: resolvedWidth, height: 14)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(Text(value, format: .number))
    .accessibilityAdjustableAction(adjustValue)
    .onChange(of: externalValue) { _, newValue in
      if !isDragging {
        value = range.clamped(newValue)
      }
    }
  }

  /// Returns the resolved slider width.
  private var resolvedWidth: CGFloat {
    resolvedSliderWidth(
      explicit: width,
      fallback: 72
    )
  }

  /// Returns the current value normalized into the 0...1 range.
  private var normalizedValue: CGFloat {
    let span = range.upperBound - range.lowerBound
    return CGFloat((range.clamped(value) - range.lowerBound) / span)
  }

  /// Returns the knob offset inside the current width.
  private func knobOffset(in width: CGFloat) -> CGFloat {
    return width * normalizedValue
  }

  /// Converts one drag position into a stepped value.
  private func value(for x: CGFloat, width: CGFloat) -> Double {
    let clampedX = min(max(0, x), width)
    let ratio = Double(clampedX / max(width, 1))
    let rawValue = range.lowerBound + ratio * (range.upperBound - range.lowerBound)

    let stepped = (rawValue / range.step).rounded() * range.step
    return range.clamped(stepped)
  }

  /// Changes and commits the value for an assistive-technology adjustment.
  private func adjustValue(_ direction: AccessibilityAdjustmentDirection) {
    let delta: Double
    switch direction {
    case .increment:
      delta = range.step
    case .decrement:
      delta = -range.step
    @unknown default:
      return
    }

    let adjustedValue = range.clamped(value + delta)
    guard adjustedValue != value else { return }
    value = adjustedValue

    guard let eventHub = appViewServices?.eventHub else { return }
    WidgetEventDispatcher.shared.enqueue {
      await eventHub.emitWidgetEvent(
        .sliderChanged,
        widgetID: rootWidgetID,
        targetWidgetID: targetWidgetID,
        value: adjustedValue
      )
    }
  }
}

private struct ProgressSliderInteractionSurface: NSViewRepresentable {
  let onPreview: (CGFloat) -> Void
  let onCommit: (CGFloat) -> Void

  /// Creates nsview.
  func makeNSView(context: Context) -> ProgressSliderInteractionNSView {
    let view = ProgressSliderInteractionNSView()
    view.onPreview = onPreview
    view.onCommit = onCommit
    return view
  }

  /// Updates the AppKit interaction surface callbacks.
  func updateNSView(_ nsView: ProgressSliderInteractionNSView, context: Context) {
    nsView.onPreview = onPreview
    nsView.onCommit = onCommit
  }
}

private final class ProgressSliderInteractionNSView: NSView {
  var onPreview: ((CGFloat) -> Void)?
  var onCommit: ((CGFloat) -> Void)?

  /// Accepts the first click even when EasyBar is inactive.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  /// Restricts hit-testing to the slider bounds.
  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
  }

  /// Sends a preview value when dragging starts.
  override func mouseDown(with event: NSEvent) {
    emitPreview(for: event)
  }

  /// Sends preview values while dragging.
  override func mouseDragged(with event: NSEvent) {
    emitPreview(for: event)
  }

  /// Commits the final slider value.
  override func mouseUp(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    onCommit?(point.x)
  }

  /// Emits one preview value for a mouse event.
  private func emitPreview(for event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    onPreview?(point.x)
  }
}
