import EasyBarCalendarConfig
import Foundation

extension Config.BuiltinWidgetPlacement {
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
