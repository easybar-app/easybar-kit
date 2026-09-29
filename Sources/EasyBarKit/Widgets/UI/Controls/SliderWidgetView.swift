import SwiftUI

/// Stores slider widget view data.
struct SliderWidgetView: View {
  /// The stable identifier for this slider widget view.
  let rootWidgetID: String
  /// The stable identifier for this slider widget view.
  let targetWidgetID: String
  /// The accessibility label for this slider widget view.
  let accessibilityLabel: String
  /// The min value for this slider widget view.
  let minValue: Double
  /// The max value for this slider widget view.
  let maxValue: Double
  /// The step for this slider widget view.
  let step: Double
  /// The external value for this slider widget view.
  let externalValue: Double
  /// The tint for this slider widget view.
  let tint: Color
  /// The width for this slider widget view.
  let width: CGFloat?

  @State private var value: Double
  @State private var isEditing = false
  @Environment(\.appViewServices) private var appViewServices

  /// The range for this slider widget view.
  private var range: SliderValueRange {
    SliderValueRange(minimum: minValue, maximum: maxValue, step: step)
  }

  /// Creates a slider widget view.
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

  /// Renders the native slider control.
  var body: some View {
    Slider(
      value: Binding(
        get: { value },
        set: { newValue in
          if !isEditing {
            isEditing = true
          }

          let clampedValue = range.clamped(newValue)
          value = clampedValue

          guard let eventHub = appViewServices?.eventHub else { return }
          WidgetEventDispatcher.shared.enqueue {
            await eventHub.emitWidgetEvent(
              .sliderPreview,
              widgetID: rootWidgetID,
              targetWidgetID: targetWidgetID,
              value: clampedValue
            )
          }
        }
      ),
      in: range.lowerBound...range.upperBound,
      step: range.step,
      onEditingChanged: { editing in
        isEditing = editing

        if !editing {
          let committedValue = value

          guard let eventHub = appViewServices?.eventHub else { return }
          WidgetEventDispatcher.shared.enqueue {
            await eventHub.emitWidgetEvent(
              .sliderChanged,
              widgetID: rootWidgetID,
              targetWidgetID: targetWidgetID,
              value: committedValue
            )
          }
        }
      }
    )
    .tint(tint)
    .frame(width: resolvedWidth)
    .accessibilityLabel(accessibilityLabel)
    .onChange(of: externalValue) { _, newValue in
      if !isEditing {
        value = range.clamped(newValue)
      }
    }
  }

  /// Returns the resolved slider width.
  private var resolvedWidth: CGFloat {
    resolvedSliderWidth(
      explicit: width,
      fallback: 140
    )
  }
}
