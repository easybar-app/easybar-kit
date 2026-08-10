import Foundation

extension BuiltinNativeNodeFactory {
  /// Builds one simple root item node.
  static func makeItemNode(
    rootID: String,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetStyle,
    text: String
  ) -> WidgetNodeState {
    var node = makeRootNode(
      id: rootID,
      kind: .item,
      placement: placement,
      style: style,
      icon: style.icon,
      text: text,
      color: style.textColorHex
    )
    node.receivesMouseHover = true
    return node
  }

  /// Builds one simple root progress-slider node.
  static func makeProgressSliderNode(
    rootID: String,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetStyle,
    text: String,
    value: Double,
    min: Double,
    max: Double,
    step: Double,
    width: Double? = nil
  ) -> WidgetNodeState {
    var node = makeRootNode(
      id: rootID,
      kind: .progressSlider,
      placement: placement,
      style: style,
      icon: style.icon,
      text: text,
      color: style.textColorHex,
      value: value,
      min: min,
      max: max,
      step: step
    )
    node.width = width
    return node
  }

  /// Builds one root sparkline node.
  static func makeSparklineNode(
    rootID: String,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetStyle,
    text: String,
    values: [Double],
    lineWidth: Double,
    color: String?
  ) -> WidgetNodeState {
    var node = makeRootNode(
      id: rootID,
      kind: .sparkline,
      placement: placement,
      style: style,
      icon: style.icon,
      text: text,
      color: color
    )

    node.values = values
    node.lineWidth = lineWidth
    return node
  }

  /// Builds one root spaces node.
  static func makeSpacesNode(
    rootID: String,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetChromeStyle
  ) -> WidgetNodeState {
    makeRootNode(
      id: rootID,
      kind: .spaces,
      placement: placement,
      style: style.widgetStyle(),
      icon: "",
      text: "",
      color: nil
    )
  }

  /// Builds one native group root node.
  static func makeGroupNode(
    id: String,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetChromeStyle
  ) -> WidgetNodeState {
    var node = makeRootNode(
      id: id,
      kind: .group,
      placement: placement,
      style: style.widgetStyle(),
      icon: "",
      text: "",
      color: nil
    )
    // Native groups are layout containers; letting them own hover surfaces
    // interferes with hover-driven children such as tooltip widgets.
    node.receivesMouseHover = false
    node.receivesMouseDown = false
    node.receivesMouseUp = false
    node.receivesMouseClick = false
    node.receivesMouseScroll = false
    return node
  }

  /// Builds one root row container node.
  static func makeRowContainerNode(
    rootID: String,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetStyle
  ) -> WidgetNodeState {
    var node = makeRootNode(
      id: rootID,
      kind: .row,
      placement: placement,
      style: style
    )
    node.receivesMouseHover = true
    return node
  }

}
