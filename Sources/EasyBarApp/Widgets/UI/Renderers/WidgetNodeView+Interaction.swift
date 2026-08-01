import EasyBarShared
import SwiftUI

// MARK: - Interaction

extension WidgetNodeView {
  /// Applies node styling and mouse handling to a container.
  func styledContainerSurface<Content: View>(_ content: Content) -> some View {
    let surface = AnyView(
      content
        .modifier(nodeStyle)
        .contentShape(Rectangle())
        .background(containerMouseOverlay)
        .overlay {
          containerContextMenuOverlay
        }
    )
    return accessibleContainerClickSurface(surface)
  }

  /// Builds the ordinary mouse-event surface behind container children.
  ///
  /// Keeping this surface behind the children preserves child click precedence.
  @ViewBuilder
  var containerMouseOverlay: some View {
    if node.hasMouseInteractionHandlers {
      nodeEventSurface(includesContextMenu: false)
    }
  }

  /// Places a right-click-only context-menu surface above container children.
  ///
  /// `MouseTrackingNSView` ignores non-right-click hit tests when it has no ordinary
  /// mouse handlers, so child hover and left-click behavior remains unchanged.
  @ViewBuilder
  var containerContextMenuOverlay: some View {
    if node.hasContextMenu {
      GeometryReader { proxy in
        WidgetMouseView(
          widgetID: node.root,
          targetWidgetID: node.id,
          logger: logger,
          eventHub: appViewServices?.eventHub,
          tracksHover: false,
          contextMenuItems: node.validatedContextMenu
        )
        .frame(width: proxy.size.width, height: proxy.size.height)
        .contentShape(Rectangle())
      }
    }
  }

  /// Applies node styling and mouse handling to a leaf node.
  func styledNodeSurface<Content: View>(_ content: Content) -> some View {
    let surface = AnyView(
      content
        .modifier(nodeStyle)
        .contentShape(Rectangle())
        .overlay {
          nodeMouseOverlay
        }
    )
    return accessibleLeafClickSurface(surface)
  }

  /// Styles one native interactive control surface without attaching an extra tap gesture.
  ///
  /// Native controls such as `Slider` already manage their own mouse tracking and drag
  /// lifecycle. Adding an extra `TapGesture` wrapper can interfere with dragging.
  func styledControlContent<Content: View>(_ content: Content) -> some View {
    AnyView(
      content
        .modifier(nodeStyle)
        .onHover { hovering in
          guard node.isMouseHoverInteractive else { return }
          emitNodeHoverEvent(hovering)
        }
        .overlay {
          scrollOverlay
        }
    )
  }

  /// Applies hover, scroll, and optional click handling to content.
  func styledMouseContent<Content: View>(_ content: Content) -> some View {
    let base = AnyView(
      content
        .modifier(nodeStyle)
        .contentShape(Rectangle())
        .onHover { hovering in
          guard node.isMouseHoverInteractive else { return }
          emitNodeHoverEvent(hovering)
        }
        .overlay {
          scrollOverlay
        }
    )

    guard node.isMouseClickInteractive else {
      return base
    }

    return AnyView(
      base.simultaneousGesture(
        TapGesture().onEnded {
          emitNodeClickEvent()
        }
      )
      .accessibilityAddTraits(.isButton)
      .accessibilityAction {
        emitNodeClickEvent()
      }
    )
  }

  /// Applies popup anchoring and interaction handling to content.
  func popupAnchorSurface<Content: View>(_ content: Content) -> some View {
    let base = AnyView(content.foregroundStyle(nodeColor))
    let surfaced = popupAnchorInteractiveSurface(base)

    return AnyView(
      surfaced
        .background {
          WidgetPopupAnchorView { anchor in
            popupPanel.updateAnchorView(anchor)
          }
        }
    )
  }

  /// Applies popup anchoring to an item node.
  func popupItemSurface<Content: View>(_ content: Content) -> some View {
    accessibleLeafClickSurface(
      content
        .modifier(nodeStyle)
        .contentShape(Rectangle())
        .overlay {
          popupAnchorMouseOverlay
        }
        .background {
          WidgetPopupAnchorView { anchor in
            popupPanel.updateAnchorView(anchor)
          }
        }
    )
  }

  /// Builds the AppKit-backed event surface for one node.
  func nodeEventSurface(
    tracksHover: Bool = true,
    includesContextMenu: Bool = true
  ) -> some View {
    GeometryReader { proxy in
      WidgetMouseView(
        widgetID: node.root,
        targetWidgetID: node.id,
        logger: logger,
        eventHub: appViewServices?.eventHub,
        tracksHover: tracksHover,
        emitsMouseHover: node.isMouseHoverInteractive,
        emitsMouseDown: node.isMouseDownInteractive,
        emitsMouseUp: node.isMouseUpInteractive,
        emitsMouseClick: node.isMouseClickInteractive,
        emitsMouseScroll: node.isMouseScrollInteractive,
        contextMenuItems: includesContextMenu ? node.validatedContextMenu : nil
      )
      .frame(width: proxy.size.width, height: proxy.size.height)
      .contentShape(Rectangle())
    }
  }

  @ViewBuilder
  var scrollOverlay: some View {
    if node.isMouseScrollInteractive || node.hasContextMenu {
      nodeEventSurface(tracksHover: false)
    }
  }

  @ViewBuilder
  var nodeMouseOverlay: some View {
    if node.hasMouseInteractionHandlers || node.hasContextMenu {
      nodeEventSurface(tracksHover: node.isMouseHoverInteractive)
    }
  }

  /// Applies styling and mouse handling to popup anchor content.
  func popupAnchorInteractiveSurface<Content: View>(_ content: Content) -> some View {
    let surface = AnyView(
      content
        .modifier(nodeStyle)
        .contentShape(Rectangle())
        .overlay {
          popupAnchorMouseOverlay
        }
    )
    return accessibleContainerClickSurface(surface)
  }

  /// Adds keyboard and assistive-technology activation to a clickable leaf node.
  func accessibleLeafClickSurface<Content: View>(_ content: Content) -> AnyView {
    guard node.isMouseClickInteractive else { return AnyView(content) }

    return AnyView(
      content
        .accessibilityElement(children: .combine)
        .accessibilityLabel(nodeClickAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
          emitNodeClickEvent()
        }
    )
  }

  /// Adds activation to a clickable container while preserving its child elements.
  func accessibleContainerClickSurface<Content: View>(_ content: Content) -> AnyView {
    guard node.isMouseClickInteractive else { return AnyView(content) }

    return AnyView(
      content
        .accessibilityElement(children: .contain)
        .accessibilityLabel(nodeClickAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
          emitNodeClickEvent()
        }
    )
  }

  /// Returns a stable spoken label for one scripted click target.
  var nodeClickAccessibilityLabel: String {
    let label = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !label.isEmpty {
      return label
    }

    let childLabels = children.compactMap { child -> String? in
      let childLabel = child.text.trimmingCharacters(in: .whitespacesAndNewlines)
      return childLabel.isEmpty ? nil : childLabel
    }
    if !childLabels.isEmpty {
      return childLabels.joined(separator: ", ")
    }

    return "Widget item"
  }

  @ViewBuilder
  var popupAnchorMouseOverlay: some View {
    if shouldShowPopupAnchorMouseOverlay {
      GeometryReader { proxy in
        WidgetMouseView(
          widgetID: node.root,
          targetWidgetID: node.id,
          logger: logger,
          eventHub: appViewServices?.eventHub,
          tracksHover: true,
          emitsMouseHover: node.isMouseHoverInteractive,
          emitsMouseDown: node.isMouseDownInteractive,
          emitsMouseUp: node.isMouseUpInteractive,
          emitsMouseClick: node.isMouseClickInteractive,
          emitsMouseScroll: node.isMouseScrollInteractive,
          contextMenuItems: node.validatedContextMenu,
          onHoverChanged: handleAnchorHover
        )
        .frame(width: proxy.size.width, height: proxy.size.height)
        .contentShape(Rectangle())
      }
    }
  }

  /// Returns whether the popup anchor needs an AppKit mouse overlay.
  var shouldShowPopupAnchorMouseOverlay: Bool {
    return nodeCanPresentPopup || node.hasMouseInteractionHandlers || node.hasContextMenu
  }

  /// Emits a widget hover event for this node.
  func emitNodeHoverEvent(_ hovering: Bool) {
    guard let eventHub = appViewServices?.eventHub else { return }
    let event: WidgetEvent = hovering ? .mouseEntered : .mouseExited

    WidgetEventDispatcher.shared.enqueue {
      await eventHub.emitWidgetEvent(
        event,
        widgetID: node.root,
        targetWidgetID: node.id
      )
    }
  }

  /// Emits a context-menu selection from a native popup anchor.
  func emitNodeContextMenuAction(_ actionID: String) {
    guard let eventHub = appViewServices?.eventHub else { return }
    WidgetEventDispatcher.shared.enqueue {
      await eventHub.emitWidgetEvent(
        .contextMenuClicked,
        widgetID: node.root,
        targetWidgetID: node.id,
        actionID: actionID
      )
    }
  }

  /// Emits a left-click event for this node.
  func emitNodeClickEvent() {
    guard let eventHub = appViewServices?.eventHub else { return }
    WidgetEventDispatcher.shared.enqueue {
      await eventHub.emitWidgetEvent(
        .mouseClicked,
        widgetID: node.root,
        targetWidgetID: node.id,
        button: .left
      )
    }
  }
}
