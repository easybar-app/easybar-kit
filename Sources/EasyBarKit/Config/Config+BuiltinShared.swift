import Foundation
import SwiftTOMLEdit

extension Config {
  /// Default popup text color.
  static let builtinPopupDefaultTextColorHex = ThemeSection.default.colors.textSecondary
  /// Default popup background color.
  static let builtinPopupDefaultBackgroundColorHex = ThemeSection.default.colors.background
  /// Default popup border color.
  static let builtinPopupDefaultBorderColorHex = ThemeSection.default.colors.borderStrong
  /// Default popup border width.
  static let builtinPopupDefaultBorderWidth = 1.0
  /// Default popup corner radius.
  static let builtinPopupDefaultCornerRadius = 8.0
  /// Default popup horizontal padding.
  static let builtinPopupDefaultPaddingX = 8.0
  /// Default popup vertical padding.
  static let builtinPopupDefaultPaddingY = 6.0
  /// Default popup horizontal margin.
  static let builtinPopupDefaultMarginX = 0.0
  /// Default popup vertical margin.
  static let builtinPopupDefaultMarginY = 8.0

  /// Shared placement block for built-in widgets.
  struct BuiltinWidgetPlacement {
    /// Whether this builtin widget placement is enabled.
    var enabled: Bool
    /// The position for this builtin widget placement.
    var position: WidgetPosition
    /// The order for this builtin widget placement.
    var order: Int
    /// The group for this builtin widget placement.
    var group: String? = nil

    /// Returns the configured native group parent when present.
    var groupID: String? {
      guard let group else { return nil }

      let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }

      return trimmed
    }
  }

  /// Shared style block for built-in widgets.
  struct BuiltinWidgetStyle {
    /// The icon for this builtin widget style.
    var icon: String
    /// The text color hex for this builtin widget style.
    var textColorHex: String?
    /// The background color hex for this builtin widget style.
    var backgroundColorHex: String?
    /// The border color hex for this builtin widget style.
    var borderColorHex: String?
    /// The border width for this builtin widget style.
    var borderWidth: Double
    /// The corner radius for this builtin widget style.
    var cornerRadius: Double
    /// The margin x for this builtin widget style.
    var marginX: Double
    /// The margin y for this builtin widget style.
    var marginY: Double
    /// The padding x for this builtin widget style.
    var paddingX: Double
    /// The padding y for this builtin widget style.
    var paddingY: Double
    /// The spacing for this builtin widget style.
    var spacing: Double
    /// The opacity for this builtin widget style.
    var opacity: Double

    /// Returns the content-independent visual chrome.
    var chrome: BuiltinWidgetChromeStyle {
      BuiltinWidgetChromeStyle(
        backgroundColorHex: backgroundColorHex,
        borderColorHex: borderColorHex,
        borderWidth: borderWidth,
        cornerRadius: cornerRadius,
        marginX: marginX,
        marginY: marginY,
        paddingX: paddingX,
        paddingY: paddingY,
        spacing: spacing,
        opacity: opacity
      )
    }
  }

  /// Shared visual chrome for built-ins that render their own content.
  struct BuiltinWidgetChromeStyle {
    /// The background color hex for this builtin widget chrome style.
    var backgroundColorHex: String?
    /// The border color hex for this builtin widget chrome style.
    var borderColorHex: String?
    /// The border width for this builtin widget chrome style.
    var borderWidth: Double
    /// The corner radius for this builtin widget chrome style.
    var cornerRadius: Double
    /// The margin x for this builtin widget chrome style.
    var marginX: Double
    /// The margin y for this builtin widget chrome style.
    var marginY: Double
    /// The padding x for this builtin widget chrome style.
    var paddingX: Double
    /// The padding y for this builtin widget chrome style.
    var paddingY: Double
    /// The spacing for this builtin widget chrome style.
    var spacing: Double
    /// The opacity for this builtin widget chrome style.
    var opacity: Double

    /// Adapts the chrome to the shared node factory with explicit content styling.
    func widgetStyle(icon: String = "", textColorHex: String? = nil) -> BuiltinWidgetStyle {
      BuiltinWidgetStyle(
        icon: icon,
        textColorHex: textColorHex,
        backgroundColorHex: backgroundColorHex,
        borderColorHex: borderColorHex,
        borderWidth: borderWidth,
        cornerRadius: cornerRadius,
        marginX: marginX,
        marginY: marginY,
        paddingX: paddingX,
        paddingY: paddingY,
        spacing: spacing,
        opacity: opacity
      )
    }
  }

  /// Shared text and chrome style for built-ins that choose their icon dynamically.
  struct BuiltinWidgetTextStyle {
    /// The text color hex for this builtin widget text style.
    var textColorHex: String?
    /// The chrome for this builtin widget text style.
    var chrome: BuiltinWidgetChromeStyle

    /// Adapts the style to the shared node factory with an explicit icon.
    func widgetStyle(icon: String) -> BuiltinWidgetStyle {
      chrome.widgetStyle(icon: icon, textColorHex: textColorHex)
    }
  }

  /// Inbox anchor style with explicit unread and read presentation states.
  struct InboxBuiltinStyle {
    /// The unread icon for this inbox builtin style.
    var unreadIcon: String
    /// The read icon for this inbox builtin style.
    var readIcon: String
    /// The unread icon color hex for this inbox builtin style.
    var unreadIconColorHex: String?
    /// The read icon color hex for this inbox builtin style.
    var readIconColorHex: String?
    /// The unread count color hex for this inbox builtin style.
    var unreadCountColorHex: String?
    /// The chrome for this inbox builtin style.
    var chrome: BuiltinWidgetChromeStyle
  }

  /// Shared popup style block for built-ins that render simple tooltip-style popups.
  struct BuiltinPopupStyle {
    /// The text color hex for this builtin popup style.
    var textColorHex: String?
    /// The background color hex for this builtin popup style.
    var backgroundColorHex: String
    /// The border color hex for this builtin popup style.
    var borderColorHex: String
    /// The border width for this builtin popup style.
    var borderWidth: Double
    /// The corner radius for this builtin popup style.
    var cornerRadius: Double
    /// The padding x for this builtin popup style.
    var paddingX: Double
    /// The padding y for this builtin popup style.
    var paddingY: Double
    /// The margin x for this builtin popup style.
    var marginX: Double
    /// The margin y for this builtin popup style.
    var marginY: Double
  }

  /// Parses all built-in widget sections.
  func parseBuiltins(from toml: TOMLTable) throws {
    guard let builtins = try configReader(table: toml, path: "").optionalSection("builtins") else {
      return
    }

    try parseBuiltinGroups(from: builtins)
    try parseInboxBuiltin(from: builtins)
    try parsePrivacySpacerBuiltin(from: builtins)
    try parseSpacerBuiltins(from: builtins)
    try parseCPUBuiltin(from: builtins)
    try parseBatteryBuiltin(from: builtins)
    try parseSpacesBuiltin(from: builtins)
    try parseFrontAppBuiltin(from: builtins)
    try parseAeroSpaceModeBuiltin(from: builtins)
    try parseVolumeBuiltin(from: builtins)
    try parseWiFiBuiltin(from: builtins)
    try parseDateBuiltin(from: builtins)
    try parseTimeBuiltin(from: builtins)
    try parseCalendarBuiltin(from: builtins)
  }
}
