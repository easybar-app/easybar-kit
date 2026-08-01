import SwiftUI

// MARK: - Top-Level Rendering

extension WidgetNodeView {
  /// Returns the rendered view for the current node kind.
  @ViewBuilder
  var renderedNodeView: some View {
    switch node.kind {
    case .row, .group:
      rowOrGroupView

    case .spaces, .wifiIndicator:
      customRenderedNodeView

    case .column, .popup:
      dedicatedContainerNodeView

    case .slider, .progressSlider, .progress, .sparkline:
      interactiveNodeView

    case .item:
      itemView
    }
  }

  /// Returns the custom-rendered view for the current node kind.
  @ViewBuilder
  var customRenderedNodeView: some View {
    switch node.kind {
    case .spaces:
      SpacesWidgetView()
        .modifier(nodeStyle)

    case .wifiIndicator:
      WiFiSignalCanvas(
        signalLevel: WiFiSignalCanvas.normalizedSignalLevel(node.value),
        state: node.icon,
        activeColor: nodeColor,
        inactiveColor: color(node.iconColor),
        slashColor: color(node.iconColor)
      )
      .frame(
        width: WidgetRenderMetrics.dimension(node.width) ?? 16,
        height: WidgetRenderMetrics.dimension(node.height) ?? 12
      )
      .modifier(nodeStyle)

    default:
      EmptyView()
    }
  }

  /// Returns the dedicated container view for the current node kind.
  @ViewBuilder
  var dedicatedContainerNodeView: some View {
    switch node.kind {
    case .column:
      VStack(alignment: .leading, spacing: stackSpacing) {
        ForEach(children) { child in
          WidgetNodeView(node: child, logger: logger)
        }
      }
      .modifier(nodeStyle)

    case .popup:
      popupAnchor

    default:
      EmptyView()
    }
  }

  /// Returns the interactive view for the current node kind.
  @ViewBuilder
  var interactiveNodeView: some View {
    switch node.kind {
    case .slider:
      styledControlContent(sliderView)

    case .progressSlider:
      styledControlContent(progressSliderView)

    case .progress:
      styledMouseContent(progressView)

    case .sparkline:
      styledMouseContent(sparklineView)

    default:
      EmptyView()
    }
  }

  var rowOrGroupView: some View {
    Group {
      if usesNativePopupAnchor {
        nativePopupAnchorView {
          childRow
        }
      } else if hasPopupChildren {
        popupAnchorSurface(childRow)
      } else {
        styledContainerSurface(childRow)
      }
    }
  }

  var itemView: some View {
    if usesNativePopupAnchor {
      return AnyView(nativePopupAnchorView { itemContent })
    }

    if hasPopupChildren {
      return AnyView(popupItemSurface(itemContent))
    }

    return AnyView(styledNodeSurface(itemContent))
  }

  /// Builds a native popup anchor with AppKit popup tracking.
  func nativePopupAnchorView<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    let surface = content()
      .foregroundStyle(nodeColor)
      .modifier(nodeStyle)
      .onHover { hovering in handleAnchorHover(hovering) }
      .contextMenu {
        NativePopupContextMenu(items: node.validatedContextMenu ?? []) { actionID in
          emitNodeContextMenuAction(actionID)
        }
      }
      .background {
        WidgetPopupAnchorView { anchor in
          popupPanel.updateAnchorView(anchor)
        }
      }

    if node.kind == .item {
      return accessibleLeafClickSurface(surface)
    }
    return accessibleContainerClickSurface(surface)
  }

  var popupAnchor: some View {
    let content = Group {
      if hasAnchorChildren {
        ForEach(anchorChildren) { child in
          WidgetNodeView(node: child, logger: logger)
        }
      } else {
        itemContent
      }
    }

    return popupAnchorSurface(content)
  }

  var popupContent: some View {
    VStack(alignment: .leading, spacing: stackSpacing) {
      ForEach(popupChildren) { child in
        WidgetNodeView(node: child, logger: logger)
      }
    }
    .fixedSize()
  }
}

/// SwiftUI context-menu content used by native popup anchors, which cannot host the ordinary
/// AppKit mouse overlay without creating an AttributeGraph cycle.
private struct NativePopupContextMenu: View {
  let items: [WidgetContextMenuItem]
  let onAction: (String) -> Void

  var body: some View {
    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
      if item.separator {
        Divider()
      } else if let title = item.title, let submenu = item.submenu, !submenu.isEmpty {
        Menu(title) {
          NativePopupContextMenu(items: submenu, onAction: onAction)
        }
      } else if let title = item.title, let actionID = item.id {
        Button {
          onAction(actionID)
        } label: {
          if item.checked {
            Label(title, systemImage: "checkmark")
          } else {
            Text(title)
          }
        }
        .disabled(!item.enabled)
      }
    }
  }
}
