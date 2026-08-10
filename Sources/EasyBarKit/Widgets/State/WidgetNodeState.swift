import Foundation

/// Render-ready state for one widget node.
struct WidgetNodeState: Identifiable, Codable, Equatable, Sendable {
  let id: String
  let root: String
  let kind: WidgetNodeKind
  let parent: String?
  let position: WidgetPosition
  let order: Int

  var icon: String
  var text: String
  var color: String?
  var iconColor: String?
  var labelColor: String?
  var visible: Bool

  var role: WidgetNodeRole?
  var popupPresented: Bool?
  var receivesMouseHover: Bool?
  var receivesMouseDown: Bool?
  var receivesMouseUp: Bool?
  var receivesMouseClick: Bool?
  var receivesMouseScroll: Bool?
  var contextMenu: [WidgetContextMenuItem]? = nil

  var imagePath: String?
  var imageSvg: String?
  var imageSize: Double?
  var imageCornerRadius: Double?
  var symbolName: String?
  var symbolSecondaryColor: String?
  var symbolOverlayName: String?
  var symbolOverlayColor: String?
  var symbolOverlayBackdropColor: String?
  var symbolOverlayScale: Double?
  var symbolOverlayBackdropScale: Double?
  var symbolOverlayOffsetX: Double?
  var symbolOverlayOffsetY: Double?

  // Custom symbol fill metadata used for exact battery-percentage rendering.
  var symbolFillFraction: Double?
  var symbolFillWidthFactor: Double?
  var symbolFillHeightFactor: Double?
  var symbolFillOffsetXFactor: Double?
  var symbolFillOffsetYFactor: Double?
  var symbolFillCornerRadiusFactor: Double?
  var symbolFillMinimumVisibleWidthFactor: Double?
  var symbolCanvasWidthFactor: Double?
  var symbolCanvasHeightFactor: Double?

  var fontSize: Double?
  var iconFontSize: Double?
  var labelFontSize: Double?
  var labelFontFamily: String? = nil
  var labelFontWeight: String? = nil
  var iconOffsetX: Double?
  var iconOffsetY: Double?

  var value: Double?
  var min: Double?
  var max: Double?
  var step: Double?
  var values: [Double]?
  var lineWidth: Double?

  var paddingX: Double?
  var paddingY: Double?
  var paddingLeft: Double?
  var paddingRight: Double?
  var paddingTop: Double?
  var paddingBottom: Double?
  var marginX: Double? = nil
  var marginY: Double? = nil
  var marginLeft: Double? = nil
  var marginRight: Double? = nil
  var marginTop: Double? = nil
  var marginBottom: Double? = nil
  var spacing: Double?

  var backgroundColor: String?
  var borderColor: String?
  var borderWidth: Double?
  var cornerRadius: Double?
  var opacity: Double?

  var width: Double?
  var height: Double?
  var yOffset: Double?

  /// Returns the bounded menu definition accepted by the native renderer.
  var validatedContextMenu: [WidgetContextMenuItem]? {
    WidgetContextMenuItem.validated(contextMenu)
  }

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
