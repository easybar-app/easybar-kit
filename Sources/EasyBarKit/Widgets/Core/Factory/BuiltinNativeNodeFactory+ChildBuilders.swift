import Foundation

extension BuiltinNativeNodeFactory {
  /// Builds one child row node.
  static func makeRowNode(
    rootID: String,
    parentID: String,
    rowID: String,
    position: WidgetPosition,
    order: Int,
    spacing: Double?
  ) -> WidgetNodeState {
    makeChildNode(
      id: rowID,
      root: rootID,
      kind: .row,
      parent: parentID,
      position: position,
      order: order,
      spacing: spacing
    )
  }

  /// Builds one child column node.
  static func makeColumnNode(
    rootID: String,
    parentID: String,
    columnID: String,
    position: WidgetPosition,
    order: Int,
    spacing: Double?
  ) -> WidgetNodeState {
    makeChildNode(
      id: columnID,
      root: rootID,
      kind: .column,
      parent: parentID,
      position: position,
      order: order,
      spacing: spacing
    )
  }

  /// Builds one row or column of popup content attached to the popup root.
  static func makePopupContentNode(
    rootID: String,
    contentID: String,
    kind: WidgetNodeKind,
    position: WidgetPosition,
    order: Int = 0,
    visible: Bool = true,
    paddingX: Double? = 0,
    paddingY: Double? = 0,
    spacing: Double? = 4,
    backgroundColor: String? = nil,
    borderColor: String? = nil,
    borderWidth: Double? = nil,
    cornerRadius: Double? = nil,
    opacity: Double? = 1
  ) -> WidgetNodeState {
    precondition(kind == .row || kind == .column, "popup content must be a row or column")

    return makeChildNode(
      id: contentID,
      root: rootID,
      kind: kind,
      parent: rootID,
      position: position,
      order: order,
      visible: visible,
      role: .popupContent,
      paddingX: paddingX,
      paddingY: paddingY,
      spacing: spacing,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
      cornerRadius: cornerRadius,
      opacity: opacity
    )
  }

  /// Builds one child item node.
  static func makeChildItemNode(
    rootID: String,
    parentID: String,
    childID: String,
    position: WidgetPosition,
    order: Int,
    icon: String = "",
    text: String = "",
    color: String? = nil,
    visible: Bool = true,
    imagePath: String? = nil,
    imageSize: Double? = nil,
    imageCornerRadius: Double? = nil,
    symbolName: String? = nil,
    symbolSecondaryColor: String? = nil,
    symbolOverlayName: String? = nil,
    symbolOverlayColor: String? = nil,
    symbolOverlayBackdropColor: String? = nil,
    symbolOverlayScale: Double? = nil,
    symbolOverlayBackdropScale: Double? = nil,
    symbolOverlayOffsetX: Double? = nil,
    symbolOverlayOffsetY: Double? = nil,
    symbolFillFraction: Double? = nil,
    symbolFillWidthFactor: Double? = nil,
    symbolFillHeightFactor: Double? = nil,
    symbolFillOffsetXFactor: Double? = nil,
    symbolFillOffsetYFactor: Double? = nil,
    symbolFillCornerRadiusFactor: Double? = nil,
    symbolFillMinimumVisibleWidthFactor: Double? = nil,
    symbolCanvasWidthFactor: Double? = nil,
    symbolCanvasHeightFactor: Double? = nil,
    fontSize: Double? = nil,
    iconFontSize: Double? = nil,
    labelFontSize: Double? = nil,
    iconOffsetX: Double? = nil,
    iconOffsetY: Double? = nil,
    spacing: Double? = 4
  ) -> WidgetNodeState {
    makeChildNode(
      id: childID,
      root: rootID,
      kind: .item,
      parent: parentID,
      position: position,
      order: order,
      icon: icon,
      text: text,
      color: color,
      visible: visible,
      imagePath: imagePath,
      imageSize: imageSize,
      imageCornerRadius: imageCornerRadius,
      symbolName: symbolName,
      symbolSecondaryColor: symbolSecondaryColor,
      symbolOverlayName: symbolOverlayName,
      symbolOverlayColor: symbolOverlayColor,
      symbolOverlayBackdropColor: symbolOverlayBackdropColor,
      symbolOverlayScale: symbolOverlayScale,
      symbolOverlayBackdropScale: symbolOverlayBackdropScale,
      symbolOverlayOffsetX: symbolOverlayOffsetX,
      symbolOverlayOffsetY: symbolOverlayOffsetY,
      symbolFillFraction: symbolFillFraction,
      symbolFillWidthFactor: symbolFillWidthFactor,
      symbolFillHeightFactor: symbolFillHeightFactor,
      symbolFillOffsetXFactor: symbolFillOffsetXFactor,
      symbolFillOffsetYFactor: symbolFillOffsetYFactor,
      symbolFillCornerRadiusFactor: symbolFillCornerRadiusFactor,
      symbolFillMinimumVisibleWidthFactor: symbolFillMinimumVisibleWidthFactor,
      symbolCanvasWidthFactor: symbolCanvasWidthFactor,
      symbolCanvasHeightFactor: symbolCanvasHeightFactor,
      fontSize: fontSize,
      iconFontSize: iconFontSize,
      labelFontSize: labelFontSize,
      iconOffsetX: iconOffsetX,
      iconOffsetY: iconOffsetY,
      spacing: spacing
    )
  }

  /// Builds one custom-drawn Wi-Fi indicator node.
  static func makeChildWiFiIndicatorNode(
    rootID: String,
    parentID: String,
    childID: String,
    position: WidgetPosition,
    order: Int,
    signalLevel: Int,
    state: String,
    activeColor: String,
    inactiveColor: String,
    width: Double,
    height: Double
  ) -> WidgetNodeState {
    makeChildNode(
      id: childID,
      root: rootID,
      kind: .wifiIndicator,
      parent: parentID,
      position: position,
      order: order,
      icon: state,
      color: activeColor,
      iconColor: inactiveColor,
      value: Double(signalLevel),
      min: 0,
      max: 3,
      paddingX: 0,
      paddingY: 0,
      spacing: 0,
      width: width,
      height: height
    )
  }

  /// Builds one child progress-slider node.
  static func makeChildProgressSliderNode(
    rootID: String,
    parentID: String,
    childID: String,
    position: WidgetPosition,
    order: Int,
    value: Double,
    min: Double,
    max: Double,
    step: Double,
    color: String? = nil,
    visible: Bool = true,
    width: Double? = nil
  ) -> WidgetNodeState {
    makeChildNode(
      id: childID,
      root: rootID,
      kind: .progressSlider,
      parent: parentID,
      position: position,
      order: order,
      color: color,
      visible: visible,
      value: value,
      min: min,
      max: max,
      step: step,
      width: width
    )
  }
}
