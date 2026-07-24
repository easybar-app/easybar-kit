import EasyBarConfigParsing
import Foundation

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
    var enabled: Bool
    var position: WidgetPosition
    var order: Int
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
    var icon: String
    var textColorHex: String?
    var backgroundColorHex: String?
    var borderColorHex: String?
    var borderWidth: Double
    var cornerRadius: Double
    var marginX: Double
    var marginY: Double
    var paddingX: Double
    var paddingY: Double
    var spacing: Double
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
    var backgroundColorHex: String?
    var borderColorHex: String?
    var borderWidth: Double
    var cornerRadius: Double
    var marginX: Double
    var marginY: Double
    var paddingX: Double
    var paddingY: Double
    var spacing: Double
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
    var textColorHex: String?
    var chrome: BuiltinWidgetChromeStyle

    /// Adapts the style to the shared node factory with an explicit icon.
    func widgetStyle(icon: String) -> BuiltinWidgetStyle {
      chrome.widgetStyle(icon: icon, textColorHex: textColorHex)
    }
  }

  /// Inbox anchor style with explicit unread and read presentation states.
  struct InboxBuiltinStyle {
    var unreadIcon: String
    var readIcon: String
    var unreadIconColorHex: String?
    var readIconColorHex: String?
    var unreadCountColorHex: String?
    var chrome: BuiltinWidgetChromeStyle
  }

  /// Shared popup style block for built-ins that render simple tooltip-style popups.
  struct BuiltinPopupStyle {
    var textColorHex: String?
    var backgroundColorHex: String
    var borderColorHex: String
    var borderWidth: Double
    var cornerRadius: Double
    var paddingX: Double
    var paddingY: Double
    var marginX: Double
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
