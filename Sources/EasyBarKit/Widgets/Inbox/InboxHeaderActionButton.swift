import SwiftUI

/// Icon-only inbox header action with a tooltip that works inside the non-activating popup panel.
struct InboxHeaderActionButton: View {
  /// The tooltip for this inbox header action button.
  let tooltip: String
  /// The system image for this inbox header action button.
  let systemImage: String
  /// Whether this inbox header action button is enabled.
  let isEnabled: Bool
  /// The tint color for this inbox header action button.
  let tintColor: Color
  /// The tooltip text color for this inbox header action button.
  let tooltipTextColor: Color
  /// The tooltip background color for this inbox header action button.
  let tooltipBackgroundColor: Color
  /// The tooltip border color for this inbox header action button.
  let tooltipBorderColor: Color
  /// The action for this inbox header action button.
  let action: () -> Void

  @State private var isHovering = false

  /// The rendered content for this view.
  var body: some View {
    Button(tooltip, systemImage: systemImage, action: action)
      .labelStyle(.iconOnly)
      .buttonStyle(.plain)
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(tintColor)
      .disabled(!isEnabled)
      .background {
        PopupHoverRegion { hovering in
          isHovering = hovering
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if isHovering {
          Text(tooltip)
            .font(.caption)
            .foregroundStyle(tooltipTextColor)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tooltipBackgroundColor, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
              RoundedRectangle(cornerRadius: 5)
                .stroke(tooltipBorderColor, lineWidth: 1)
            }
            .shadow(radius: 2, y: 1)
            .offset(y: 26)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
  }
}
