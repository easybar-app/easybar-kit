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
  /// The stable identifier for this native node draft.
  var id: String
  /// The root for this native node draft.
  var root: String
  /// The kind for this native node draft.
  var kind: WidgetNodeKind
  /// The parent for this native node draft.
  var parent: String?
  /// The position for this native node draft.
  var position: WidgetPosition
  /// The order for this native node draft.
  var order: Int
  /// The icon for this native node draft.
  var icon: String = ""
  /// The text for this native node draft.
  var text: String = ""
  /// The color for this native node draft.
  var color: String?
  /// The icon color for this native node draft.
  var iconColor: String?
  /// The label color for this native node draft.
  var labelColor: String?
  /// Whether this native node draft is visible.
  var visible: Bool = true
  /// The role for this native node draft.
  var role: WidgetNodeRole?
  /// Whether the popup presented option is enabled for this native node draft.
  var popupPresented: Bool?
  /// The image path for this native node draft.
  var imagePath: String?
  /// The image size for this native node draft.
  var imageSize: Double?
  /// The image corner radius for this native node draft.
  var imageCornerRadius: Double?
  /// The symbol name for this native node draft.
  var symbolName: String?
  /// The symbol secondary color for this native node draft.
  var symbolSecondaryColor: String?
  /// The symbol overlay name for this native node draft.
  var symbolOverlayName: String?
  /// The symbol overlay color for this native node draft.
  var symbolOverlayColor: String?
  /// The symbol overlay backdrop color for this native node draft.
  var symbolOverlayBackdropColor: String?
  /// The symbol overlay scale for this native node draft.
  var symbolOverlayScale: Double?
  /// The symbol overlay backdrop scale for this native node draft.
  var symbolOverlayBackdropScale: Double?
  /// The symbol overlay offset x for this native node draft.
  var symbolOverlayOffsetX: Double?
  /// The symbol overlay offset y for this native node draft.
  var symbolOverlayOffsetY: Double?
  /// The symbol fill fraction for this native node draft.
  var symbolFillFraction: Double?
  /// The symbol fill width factor for this native node draft.
  var symbolFillWidthFactor: Double?
  /// The symbol fill height factor for this native node draft.
  var symbolFillHeightFactor: Double?
  /// The symbol fill offset x factor for this native node draft.
  var symbolFillOffsetXFactor: Double?
  /// The symbol fill offset y factor for this native node draft.
  var symbolFillOffsetYFactor: Double?
  /// The symbol fill corner radius factor for this native node draft.
  var symbolFillCornerRadiusFactor: Double?
  /// The symbol fill minimum visible width factor for this native node draft.
  var symbolFillMinimumVisibleWidthFactor: Double?
  /// The symbol canvas width factor for this native node draft.
  var symbolCanvasWidthFactor: Double?
  /// The symbol canvas height factor for this native node draft.
  var symbolCanvasHeightFactor: Double?
  /// The font size for this native node draft.
  var fontSize: Double?
  /// The icon font size for this native node draft.
  var iconFontSize: Double?
  /// The label font size for this native node draft.
  var labelFontSize: Double?
  /// The icon offset x for this native node draft.
  var iconOffsetX: Double?
  /// The icon offset y for this native node draft.
  var iconOffsetY: Double?
  /// The value for this native node draft.
  var value: Double?
  /// The min for this native node draft.
  var min: Double?
  /// The max for this native node draft.
  var max: Double?
  /// The step for this native node draft.
  var step: Double?
  /// The padding x for this native node draft.
  var paddingX: Double? = 0
  /// The padding y for this native node draft.
  var paddingY: Double? = 0
  /// The margin x for this native node draft.
  var marginX: Double?
  /// The margin y for this native node draft.
  var marginY: Double?
  /// The spacing for this native node draft.
  var spacing: Double? = 4
  /// The background color for this native node draft.
  var backgroundColor: String?
  /// The border color for this native node draft.
  var borderColor: String?
  /// The border width for this native node draft.
  var borderWidth: Double?
  /// The corner radius for this native node draft.
  var cornerRadius: Double?
  /// The opacity for this native node draft.
  var opacity: Double? = 1
  /// The width for this native node draft.
  var width: Double?
  /// The height for this native node draft.
  var height: Double?
}
