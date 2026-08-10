import SwiftUI

struct SliderWidgetView: View {
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
  @State private var isEditing = false
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
