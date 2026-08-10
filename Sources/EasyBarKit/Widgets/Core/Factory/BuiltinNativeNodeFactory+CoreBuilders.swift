import Foundation

/// Factory helpers for building native widget node state.
enum BuiltinNativeNodeFactory {}

extension BuiltinNativeNodeFactory {
  /// Builds one root node with the shared built-in style defaults.
  static func makeRootNode(
    id: String,
    kind: WidgetNodeKind,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetStyle,
    icon: String = "",
    text: String = "",
    color: String? = nil,
    value: Double? = nil,
    min: Double? = nil,
    max: Double? = nil,
    step: Double? = nil
  ) -> WidgetNodeState {
    makeNode(
      id: id,
      root: id,
      kind: kind,
      parent: placement.groupID,
      position: placement.position,
      order: placement.order,
      icon: icon,
      text: text,
      color: color,
      value: value,
      min: min,
      max: max,
      step: step,
      paddingX: style.paddingX,
      paddingY: style.paddingY,
      marginX: style.marginX,
      marginY: style.marginY,
      spacing: style.spacing,
      backgroundColor: style.backgroundColorHex,
      borderColor: style.borderColorHex,
      borderWidth: style.borderWidth,
      cornerRadius: style.cornerRadius,
      opacity: style.opacity
    )
  }

  /// Builds one child node with the shared child defaults.
  static func makeChildNode(
    id: String,
    root: String,
    kind: WidgetNodeKind,
    parent: String,
    position: WidgetPosition,
    order: Int,
    icon: String = "",
    text: String = "",
    color: String? = nil,
    iconColor: String? = nil,
    labelColor: String? = nil,
    visible: Bool = true,
    role: WidgetNodeRole? = nil,
    popupPresented: Bool? = nil,
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
    value: Double? = nil,
    min: Double? = nil,
    max: Double? = nil,
    step: Double? = nil,
    paddingX: Double? = 0,
    paddingY: Double? = 0,
    marginX: Double? = nil,
    marginY: Double? = nil,
    spacing: Double? = 4,
    backgroundColor: String? = nil,
    borderColor: String? = nil,
    borderWidth: Double? = nil,
    cornerRadius: Double? = nil,
    opacity: Double? = 1,
    width: Double? = nil,
    height: Double? = nil
  ) -> WidgetNodeState {
    makeNode(
      id: id,
      root: root,
      kind: kind,
      parent: parent,
      position: position,
      order: order,
      icon: icon,
      text: text,
      color: color,
      iconColor: iconColor,
      labelColor: labelColor,
      visible: visible,
      role: role,
      popupPresented: popupPresented,
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
      value: value,
      min: min,
      max: max,
      step: step,
      paddingX: paddingX,
      paddingY: paddingY,
      marginX: marginX,
      marginY: marginY,
      spacing: spacing,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
      cornerRadius: cornerRadius,
      opacity: opacity,
      width: width,
      height: height
    )
  }

  /// Builds one node with the shared built-in defaults applied.
  static func makeNode(
    id: String,
    root: String,
    kind: WidgetNodeKind,
    parent: String?,
    position: WidgetPosition,
    order: Int,
    icon: String = "",
    text: String = "",
    color: String? = nil,
    iconColor: String? = nil,
    labelColor: String? = nil,
    visible: Bool = true,
    role: WidgetNodeRole? = nil,
    popupPresented: Bool? = nil,
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
    value: Double? = nil,
    min: Double? = nil,
    max: Double? = nil,
    step: Double? = nil,
    paddingX: Double? = 0,
    paddingY: Double? = 0,
    marginX: Double? = nil,
    marginY: Double? = nil,
    spacing: Double? = 4,
    backgroundColor: String? = nil,
    borderColor: String? = nil,
    borderWidth: Double? = nil,
    cornerRadius: Double? = nil,
    opacity: Double? = 1,
    width: Double? = nil,
    height: Double? = nil
  ) -> WidgetNodeState {
    makeNode(
      NativeNodeDraft(
        id: id,
        root: root,
        kind: kind,
        parent: parent,
        position: position,
        order: order,
        icon: icon,
        text: text,
        color: color,
        iconColor: iconColor,
        labelColor: labelColor,
        visible: visible,
        role: role,
        popupPresented: popupPresented,
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
        value: value,
        min: min,
        max: max,
        step: step,
        paddingX: paddingX,
        paddingY: paddingY,
        marginX: marginX,
        marginY: marginY,
        spacing: spacing,
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        borderWidth: borderWidth,
        cornerRadius: cornerRadius,
        opacity: opacity,
        width: width,
        height: height
      )
    )
  }

  /// Builds one widget node from a draft value instead of forwarding long parameter chains.
  private static func makeNode(_ draft: NativeNodeDraft) -> WidgetNodeState {
    WidgetNodeState(
      id: draft.id,
      root: draft.root,
      kind: draft.kind,
      parent: draft.parent,
      position: draft.position,
      order: draft.order,
      icon: draft.icon,
      text: draft.text,
      color: draft.color,
      iconColor: draft.iconColor,
      labelColor: draft.labelColor,
      visible: draft.visible,
      role: draft.role,
      popupPresented: draft.popupPresented,
      receivesMouseHover: nil,
      receivesMouseDown: nil,
      receivesMouseUp: nil,
      receivesMouseClick: nil,
      receivesMouseScroll: nil,
      imagePath: draft.imagePath,
      imageSize: draft.imageSize,
      imageCornerRadius: draft.imageCornerRadius,
      symbolName: draft.symbolName,
      symbolSecondaryColor: draft.symbolSecondaryColor,
      symbolOverlayName: draft.symbolOverlayName,
      symbolOverlayColor: draft.symbolOverlayColor,
      symbolOverlayBackdropColor: draft.symbolOverlayBackdropColor,
      symbolOverlayScale: draft.symbolOverlayScale,
      symbolOverlayBackdropScale: draft.symbolOverlayBackdropScale,
      symbolOverlayOffsetX: draft.symbolOverlayOffsetX,
      symbolOverlayOffsetY: draft.symbolOverlayOffsetY,
      symbolFillFraction: draft.symbolFillFraction,
      symbolFillWidthFactor: draft.symbolFillWidthFactor,
      symbolFillHeightFactor: draft.symbolFillHeightFactor,
      symbolFillOffsetXFactor: draft.symbolFillOffsetXFactor,
      symbolFillOffsetYFactor: draft.symbolFillOffsetYFactor,
      symbolFillCornerRadiusFactor: draft.symbolFillCornerRadiusFactor,
      symbolFillMinimumVisibleWidthFactor: draft.symbolFillMinimumVisibleWidthFactor,
      symbolCanvasWidthFactor: draft.symbolCanvasWidthFactor,
      symbolCanvasHeightFactor: draft.symbolCanvasHeightFactor,
      fontSize: draft.fontSize,
      iconFontSize: draft.iconFontSize,
      labelFontSize: draft.labelFontSize,
      iconOffsetX: draft.iconOffsetX,
      iconOffsetY: draft.iconOffsetY,
      value: draft.value,
      min: draft.min,
      max: draft.max,
      step: draft.step,
      values: nil,
      lineWidth: nil,
      paddingX: draft.paddingX,
      paddingY: draft.paddingY,
      paddingLeft: nil,
      paddingRight: nil,
      paddingTop: nil,
      paddingBottom: nil,
      marginX: draft.marginX,
      marginY: draft.marginY,
      marginLeft: nil,
      marginRight: nil,
      marginTop: nil,
      marginBottom: nil,
      spacing: draft.spacing,
      backgroundColor: draft.backgroundColor,
      borderColor: draft.borderColor,
      borderWidth: draft.borderWidth,
      cornerRadius: draft.cornerRadius,
      opacity: draft.opacity,
      width: draft.width,
      height: draft.height,
      yOffset: nil
    )
  }
}

/// Draft value used to construct native widget nodes without repeating initializer chains.
private struct NativeNodeDraft {
  var id: String
  var root: String
  var kind: WidgetNodeKind
  var parent: String?
  var position: WidgetPosition
  var order: Int
  var icon: String = ""
  var text: String = ""
  var color: String?
  var iconColor: String?
  var labelColor: String?
  var visible: Bool = true
  var role: WidgetNodeRole?
  var popupPresented: Bool?
  var imagePath: String?
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
  var iconOffsetX: Double?
  var iconOffsetY: Double?
  var value: Double?
  var min: Double?
  var max: Double?
  var step: Double?
  var paddingX: Double? = 0
  var paddingY: Double? = 0
  var marginX: Double?
  var marginY: Double?
  var spacing: Double? = 4
  var backgroundColor: String?
  var borderColor: String?
  var borderWidth: Double?
  var cornerRadius: Double?
  var opacity: Double? = 1
  var width: Double?
  var height: Double?
}
