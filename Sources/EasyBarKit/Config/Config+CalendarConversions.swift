import EasyBarCalendarConfig
import Foundation

extension Config.BuiltinWidgetPlacement {
  /// Creates an instance.
  init(_ placement: CalendarWidgetPlacement) {
    self.init(
      enabled: placement.enabled,
      position: placement.position,
      order: placement.order,
      group: placement.group
    )
  }
}

extension Config.BuiltinWidgetStyle {
  /// Creates an instance.
  init(_ style: CalendarWidgetStyle) {
    self.init(
      icon: style.icon,
      textColorHex: style.textColorHex,
      backgroundColorHex: style.backgroundColorHex,
      borderColorHex: style.borderColorHex,
      borderWidth: style.borderWidth,
      cornerRadius: style.cornerRadius,
      marginX: style.marginX,
      marginY: style.marginY,
      paddingX: style.paddingX,
      paddingY: style.paddingY,
      spacing: style.spacing,
      opacity: style.opacity
    )
  }
}

extension CalendarWidgetPlacement {
  /// Creates an instance.
  init(_ placement: Config.BuiltinWidgetPlacement) {
    self.init(
      enabled: placement.enabled,
      position: placement.position,
      order: placement.order,
      group: placement.group
    )
  }
}

extension CalendarWidgetStyle {
  /// Creates an instance.
  init(_ style: Config.BuiltinWidgetStyle) {
    self.init(
      icon: style.icon,
      textColorHex: style.textColorHex,
      backgroundColorHex: style.backgroundColorHex,
      borderColorHex: style.borderColorHex,
      borderWidth: style.borderWidth,
      cornerRadius: style.cornerRadius,
      marginX: style.marginX,
      marginY: style.marginY,
      paddingX: style.paddingX,
      paddingY: style.paddingY,
      spacing: style.spacing,
      opacity: style.opacity
    )
  }
}
