import Foundation

/// Render-ready state for one widget node.
struct WidgetNodeState: Identifiable, Codable, Equatable, Sendable {
  /// The stable identifier for this widget node state.
  let id: String
  /// The root for this widget node state.
  let root: String
  /// The kind for this widget node state.
  let kind: WidgetNodeKind
  /// The parent for this widget node state.
  let parent: String?
  /// The position for this widget node state.
  let position: WidgetPosition
  /// The order for this widget node state.
  let order: Int

  /// The icon for this widget node state.
  var icon: String
  /// The text for this widget node state.
  var text: String
  /// The color for this widget node state.
  var color: String?
  /// The icon color for this widget node state.
  var iconColor: String?
  /// The label color for this widget node state.
  var labelColor: String?
  /// Whether this widget node state is visible.
  var visible: Bool

  /// The role for this widget node state.
  var role: WidgetNodeRole?
  /// Whether the popup presented option is enabled for this widget node state.
  var popupPresented: Bool?
  /// Whether the receives mouse hover option is enabled for this widget node state.
  var receivesMouseHover: Bool?
  /// Whether the receives mouse down option is enabled for this widget node state.
  var receivesMouseDown: Bool?
  /// Whether the receives mouse up option is enabled for this widget node state.
  var receivesMouseUp: Bool?
  /// Whether the receives mouse click option is enabled for this widget node state.
  var receivesMouseClick: Bool?
  /// Whether the receives mouse scroll option is enabled for this widget node state.
  var receivesMouseScroll: Bool?
  /// The context menu for this widget node state.
  var contextMenu: [WidgetContextMenuItem]? = nil

  /// The image path for this widget node state.
  var imagePath: String?
  /// The image svg for this widget node state.
  var imageSvg: String?
  /// The image size for this widget node state.
  var imageSize: Double?
  /// The image corner radius for this widget node state.
  var imageCornerRadius: Double?
  /// The symbol name for this widget node state.
  var symbolName: String?
  /// The symbol secondary color for this widget node state.
  var symbolSecondaryColor: String?
  /// The symbol overlay name for this widget node state.
  var symbolOverlayName: String?
  /// The symbol overlay color for this widget node state.
  var symbolOverlayColor: String?
  /// The symbol overlay backdrop color for this widget node state.
  var symbolOverlayBackdropColor: String?
  /// The symbol overlay scale for this widget node state.
  var symbolOverlayScale: Double?
  /// The symbol overlay backdrop scale for this widget node state.
  var symbolOverlayBackdropScale: Double?
  /// The symbol overlay offset x for this widget node state.
  var symbolOverlayOffsetX: Double?
  /// The symbol overlay offset y for this widget node state.
  var symbolOverlayOffsetY: Double?

  /// The custom symbol fill fraction used for exact battery-percentage rendering.
  var symbolFillFraction: Double?
  /// The symbol fill width factor for this widget node state.
  var symbolFillWidthFactor: Double?
  /// The symbol fill height factor for this widget node state.
  var symbolFillHeightFactor: Double?
  /// The symbol fill offset x factor for this widget node state.
  var symbolFillOffsetXFactor: Double?
  /// The symbol fill offset y factor for this widget node state.
  var symbolFillOffsetYFactor: Double?
  /// The symbol fill corner radius factor for this widget node state.
  var symbolFillCornerRadiusFactor: Double?
  /// The symbol fill minimum visible width factor for this widget node state.
  var symbolFillMinimumVisibleWidthFactor: Double?
  /// The symbol canvas width factor for this widget node state.
  var symbolCanvasWidthFactor: Double?
  /// The symbol canvas height factor for this widget node state.
  var symbolCanvasHeightFactor: Double?

  /// The font size for this widget node state.
  var fontSize: Double?
  /// The icon font size for this widget node state.
  var iconFontSize: Double?
  /// The label font size for this widget node state.
  var labelFontSize: Double?
  /// The label font family for this widget node state.
  var labelFontFamily: String? = nil
  /// The label font weight for this widget node state.
  var labelFontWeight: String? = nil
  /// The icon offset x for this widget node state.
  var iconOffsetX: Double?
  /// The icon offset y for this widget node state.
  var iconOffsetY: Double?

  /// The value for this widget node state.
  var value: Double?
  /// The min for this widget node state.
  var min: Double?
  /// The max for this widget node state.
  var max: Double?
  /// The step for this widget node state.
  var step: Double?
  /// The values for this widget node state.
  var values: [Double]?
  /// The line width for this widget node state.
  var lineWidth: Double?

  /// The padding x for this widget node state.
  var paddingX: Double?
  /// The padding y for this widget node state.
  var paddingY: Double?
  /// The padding left for this widget node state.
  var paddingLeft: Double?
  /// The padding right for this widget node state.
  var paddingRight: Double?
  /// The padding top for this widget node state.
  var paddingTop: Double?
  /// The padding bottom for this widget node state.
  var paddingBottom: Double?
  /// The margin x for this widget node state.
  var marginX: Double? = nil
  /// The margin y for this widget node state.
  var marginY: Double? = nil
  /// The margin left for this widget node state.
  var marginLeft: Double? = nil
  /// The margin right for this widget node state.
  var marginRight: Double? = nil
  /// The margin top for this widget node state.
  var marginTop: Double? = nil
  /// The margin bottom for this widget node state.
  var marginBottom: Double? = nil
  /// The spacing for this widget node state.
  var spacing: Double?

  /// The background color for this widget node state.
  var backgroundColor: String?
  /// The border color for this widget node state.
  var borderColor: String?
  /// The border width for this widget node state.
  var borderWidth: Double?
  /// The corner radius for this widget node state.
  var cornerRadius: Double?
  /// The opacity for this widget node state.
  var opacity: Double?

  /// The width for this widget node state.
  var width: Double?
  /// The height for this widget node state.
  var height: Double?
  /// The y offset for this widget node state.
  var yOffset: Double?

  /// Returns the bounded menu definition accepted by the native renderer.
  var validatedContextMenu: [WidgetContextMenuItem]? {
    WidgetContextMenuItem.validated(contextMenu)
  }

  /// Whether the has context menu option is enabled for this widget node state.
  var hasContextMenu: Bool {
    validatedContextMenu?.isEmpty == false
  }

  /// Returns the single valid image source represented by the decoded wire fields.
  var imageSource: WidgetImageSource? {
    switch (imagePath, imageSvg) {
    case (.some(let path), nil):
      return path.isEmpty ? nil : .path(path)
    case (nil, .some(let svg)):
      guard !svg.isEmpty, svg.lengthOfBytes(using: .utf8) <= WidgetImageSource.maximumInlineSVGBytes
      else { return nil }
      return .svg(svg)
    default:
      return nil
    }
  }

  /// Returns whether this node is attached directly to the bar.
  var isTopLevel: Bool {
    return parent == nil || parent == ""
  }

  /// Returns whether this node has a non-empty parent id.
  var hasParent: Bool {
    return !isTopLevel
  }

  /// Returns whether this node is the built-in calendar root.
  var isCalendarRoot: Bool {
    return id == root && root == "builtin_calendar"
  }

  /// Whether this widget node state is inbox root.
  var isInboxRoot: Bool {
    id == root && root == "builtin_inbox"
  }

  /// Returns whether this node is a popup anchor child.
  var isPopupAnchor: Bool {
    return role == .popupAnchor
  }

  /// Returns whether this node is popup content.
  var isPopupContent: Bool {
    return role == .popupContent
  }

  /// Returns whether the node should present its popup even while idle.
  var presentsPopupAutomatically: Bool {
    return popupPresented == true
  }

  /// Returns whether this node should own hover interactions.
  ///
  /// Root widgets need hover by default even when they render as rows or groups,
  /// because native widgets like battery/volume/wifi and scripted container widgets
  /// rely on root-level hover events. Hover-only overlays do not steal click handling
  /// from children because `WidgetMouseView` only participates in hit-testing when it
  /// emits direct mouse button or scroll events.
  ///
  /// Config-defined native groups can still opt out explicitly through
  /// `receivesMouseHover = false`.
  var isMouseHoverInteractive: Bool {
    if let receivesMouseHover {
      return receivesMouseHover
    }

    return id == root
  }

  /// Returns whether this node should own mouse-down interactions.
  var isMouseDownInteractive: Bool {
    return receivesMouseDown == true
  }

  /// Returns whether this node should own mouse-up interactions.
  var isMouseUpInteractive: Bool {
    return receivesMouseUp == true
  }

  /// Returns whether this node should own click interactions.
  ///
  /// Child items inside scripted row/group containers should be clickable by default so Lua
  /// widgets can subscribe to item-specific click events without needing extra node flags.
  var isMouseClickInteractive: Bool {
    if let receivesMouseClick {
      return receivesMouseClick
    }

    return kind == .item
  }

  /// Returns whether this node should own scroll interactions.
  var isMouseScrollInteractive: Bool {
    return receivesMouseScroll == true
  }

  /// Returns whether this node needs any mouse interaction surface.
  var hasMouseInteractionHandlers: Bool {
    return isMouseHoverInteractive || isMouseDownInteractive || isMouseUpInteractive
      || isMouseClickInteractive || isMouseScrollInteractive
  }
}
