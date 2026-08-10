import SwiftUI

/// Icon-only inbox header action with a tooltip that works inside the non-activating popup panel.
struct InboxHeaderActionButton: View {
  let tooltip: String
  let systemImage: String
  let isEnabled: Bool
  let tintColor: Color
  let tooltipTextColor: Color
  let tooltipBackgroundColor: Color
  let tooltipBorderColor: Color
  let action: () -> Void

  @State private var isHovering = false

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
