import Foundation

extension Config {
  /// Parses one shared built-in placement block.
  func parseBuiltinPlacement(
    reader: ConfigReader,
    fallback: BuiltinWidgetPlacement,
    allowGroupReference: Bool = true
  ) throws -> BuiltinWidgetPlacement {
    let rawGroup = try reader.optionalString("group", fallback: fallback.group)

    return BuiltinWidgetPlacement(
      enabled: try reader.bool("enabled", fallback: fallback.enabled),
      position: try reader.enum("position", fallback: fallback.position),
      order: try reader.int("order", fallback: fallback.order),
      group: try validatedBuiltinGroupReference(
        rawGroup,
        path: reader.path(for: "group"),
        allowGroupReference: allowGroupReference
      )
    )
  }

  /// Parses one shared built-in widget style block.
  func parseBuiltinStyle(
    reader: ConfigReader,
    fallback: BuiltinWidgetStyle
  ) throws -> BuiltinWidgetStyle {
    let chrome = try parseBuiltinChromeStyle(
      reader: reader,
      fallback: fallback.chrome
    )

    return BuiltinWidgetStyle(
      icon: try reader.string("icon", fallback: fallback.icon),
      textColorHex: try reader.optionalColor("text_color", fallback: fallback.textColorHex),
      backgroundColorHex: chrome.backgroundColorHex,
      borderColorHex: chrome.borderColorHex,
      borderWidth: chrome.borderWidth,
      cornerRadius: chrome.cornerRadius,
      marginX: chrome.marginX,
      marginY: chrome.marginY,
      paddingX: chrome.paddingX,
      paddingY: chrome.paddingY,
      spacing: chrome.spacing,
      opacity: chrome.opacity
    )
  }

  /// Parses shared visual chrome without accepting icon or text-color keys.
  func parseBuiltinChromeStyle(
    reader: ConfigReader,
    fallback: BuiltinWidgetChromeStyle
  ) throws -> BuiltinWidgetChromeStyle {
    BuiltinWidgetChromeStyle(
      backgroundColorHex: try reader.optionalColor(
        "background_color",
        fallback: fallback.backgroundColorHex
      ),
      borderColorHex: try reader.optionalColor("border_color", fallback: fallback.borderColorHex),
      borderWidth: try reader.double("border_width", fallback: fallback.borderWidth, minimum: 0),
      cornerRadius: try reader.double("corner_radius", fallback: fallback.cornerRadius, minimum: 0),
      marginX: try reader.double("margin_x", fallback: fallback.marginX),
      marginY: try reader.double("margin_y", fallback: fallback.marginY),
      paddingX: try reader.double("padding_x", fallback: fallback.paddingX, minimum: 0),
      paddingY: try reader.double("padding_y", fallback: fallback.paddingY, minimum: 0),
      spacing: try reader.double("spacing", fallback: fallback.spacing, minimum: 0),
      opacity: try reader.double("opacity", fallback: fallback.opacity, minimum: 0, maximum: 1)
    )
  }

  /// Parses text color and visual chrome without accepting a generic icon key.
  func parseBuiltinTextStyle(
    reader: ConfigReader,
    fallback: BuiltinWidgetTextStyle
  ) throws -> BuiltinWidgetTextStyle {
    BuiltinWidgetTextStyle(
      textColorHex: try reader.optionalColor("text_color", fallback: fallback.textColorHex),
      chrome: try parseBuiltinChromeStyle(reader: reader, fallback: fallback.chrome)
    )
  }

  /// Parses one shared tooltip-style popup block.
  func parseBuiltinPopupStyle(
    reader: ConfigReader,
    fallback: BuiltinPopupStyle
  ) throws -> BuiltinPopupStyle {
    BuiltinPopupStyle(
      textColorHex: try reader.optionalColor("text_color", fallback: fallback.textColorHex),
      backgroundColorHex: try reader.color(
        "background_color", fallback: fallback.backgroundColorHex),
      borderColorHex: try reader.color("border_color", fallback: fallback.borderColorHex),
      borderWidth: try reader.double("border_width", fallback: fallback.borderWidth, minimum: 0),
      cornerRadius: try reader.double("corner_radius", fallback: fallback.cornerRadius, minimum: 0),
      paddingX: try reader.double("padding_x", fallback: fallback.paddingX, minimum: 0),
      paddingY: try reader.double("padding_y", fallback: fallback.paddingY, minimum: 0),
      marginX: try reader.double("margin_x", fallback: fallback.marginX),
      marginY: try reader.double("margin_y", fallback: fallback.marginY)
    )
  }
}
