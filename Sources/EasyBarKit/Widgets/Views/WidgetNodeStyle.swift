import SwiftUI

/// Shared box-model styling for rendered widget nodes.
struct WidgetNodeStyle: ViewModifier {
  let node: WidgetNodeState
  @EnvironmentObject private var configStore: ConfigSnapshotStore

  /// Applies the shared box-model styling for one widget node.
  func body(content: Content) -> some View {
    content
      .padding(.leading, leadingPadding)
      .padding(.trailing, trailingPadding)
      .padding(.top, topPadding)
      .padding(.bottom, bottomPadding)
      .frame(
        width: frameWidth,
        height: frameHeight,
        alignment: .center
      )
      .background(backgroundColor)
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(
            borderColor,
            lineWidth: borderWidth
          )
      }
      .clipShape(
        RoundedRectangle(cornerRadius: cornerRadius)
      )
      .opacity(WidgetRenderMetrics.opacity(node.opacity))
      .padding(.leading, leadingMargin)
      .padding(.trailing, trailingMargin)
      .padding(.top, topMargin)
      .padding(.bottom, bottomMargin)
      .offset(y: verticalOffset)
  }

  /// Returns the resolved leading padding.
  private var leadingPadding: CGFloat {
    return CGFloat(node.paddingLeft ?? node.paddingX ?? 0)
  }

  /// Returns the resolved trailing padding.
  private var trailingPadding: CGFloat {
    return CGFloat(node.paddingRight ?? node.paddingX ?? 0)
  }

  /// Returns the resolved top padding.
  private var topPadding: CGFloat {
    return CGFloat(node.paddingTop ?? node.paddingY ?? 0)
  }

  /// Returns the resolved bottom padding.
  private var bottomPadding: CGFloat {
    return CGFloat(node.paddingBottom ?? node.paddingY ?? 0)
  }

  /// Returns the resolved leading margin.
  private var leadingMargin: CGFloat {
    return CGFloat(node.marginLeft ?? node.marginX ?? 0)
  }

  /// Returns the resolved trailing margin.
  private var trailingMargin: CGFloat {
    return CGFloat(node.marginRight ?? node.marginX ?? 0)
  }

  /// Returns the resolved top margin.
  private var topMargin: CGFloat {
    return CGFloat(node.marginTop ?? node.marginY ?? 0)
  }

  /// Returns the resolved bottom margin.
  private var bottomMargin: CGFloat {
    return CGFloat(node.marginBottom ?? node.marginY ?? 0)
  }

  /// Returns the resolved frame width.
  private var frameWidth: CGFloat? {
    WidgetRenderMetrics.dimension(node.width)
  }

  /// Returns the resolved frame height.
  private var frameHeight: CGFloat? {
    WidgetRenderMetrics.dimension(node.height)
  }

  /// Returns the resolved node corner radius.
  private var cornerRadius: CGFloat {
    return WidgetRenderMetrics.nonnegative(node.cornerRadius, fallback: 0)
  }

  /// Returns the resolved node border width.
  private var borderWidth: CGFloat {
    return WidgetRenderMetrics.nonnegative(node.borderWidth, fallback: 0)
  }

  /// Returns the resolved vertical offset.
  private var verticalOffset: CGFloat {
    return CGFloat(node.yOffset ?? 0)
  }

  /// Returns the resolved background color.
  private var backgroundColor: Color {
    return resolvedColor(node.backgroundColor)
  }

  /// Returns the resolved border color.
  private var borderColor: Color {
    return resolvedColor(node.borderColor)
  }

  /// Resolves one optional node color or clears it.
  private func resolvedColor(_ hex: String?) -> Color {
    guard let hex, !hex.isEmpty else { return Color.clear }
    return Color(hex: hex, snapshot: configStore.snapshot)
  }
}
