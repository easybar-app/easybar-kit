import EasyBarShared
import Foundation

/// Defines the supported calendar popup mode values.
public enum CalendarPopupMode: String, CaseIterable, Sendable {
  case none
  case upcoming
  case month
}

/// Defines the supported calendar anchor layout values.
public enum CalendarAnchorLayout: String, Codable, CaseIterable, Sendable {
  case row
  case column
}

/// Defines the supported calendar anchor field kind values.
public enum CalendarAnchorFieldKind: String, Codable, CaseIterable, Sendable {
  case time
  case date
}

/// Defines the supported calendar anchor font weight values.
public enum CalendarAnchorFontWeight: String, Codable, CaseIterable, Sendable {
  case ultraLight = "ultralight"
  case thin
  case light
  case regular
  case medium
  case semibold
  case bold
  case heavy
  case black
}

/// Stores calendar widget placement data.
public struct CalendarWidgetPlacement: Sendable {
  /// Whether this calendar widget placement is enabled.
  public var enabled: Bool
  /// The position for this calendar widget placement.
  public var position: WidgetPosition
  /// The order for this calendar widget placement.
  public var order: Int
  /// The group for this calendar widget placement.
  public var group: String?

  /// Creates a calendar widget placement.
  public init(
    enabled: Bool,
    position: WidgetPosition,
    order: Int,
    group: String? = nil
  ) {
    self.enabled = enabled
    self.position = position
    self.order = order
    self.group = group
  }

  /// The stable identifier for this calendar widget placement.
  public var groupID: String? {
    guard let group else { return nil }

    let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    return trimmed
  }
}

/// Stores calendar widget style data.
public struct CalendarWidgetStyle: Sendable {
  /// The icon for this calendar widget style.
  public var icon: String
  /// The text color hex for this calendar widget style.
  public var textColorHex: String?
  /// The background color hex for this calendar widget style.
  public var backgroundColorHex: String?
  /// The border color hex for this calendar widget style.
  public var borderColorHex: String?
  /// The border width for this calendar widget style.
  public var borderWidth: Double
  /// The corner radius for this calendar widget style.
  public var cornerRadius: Double
  /// The margin x for this calendar widget style.
  public var marginX: Double
  /// The margin y for this calendar widget style.
  public var marginY: Double
  /// The padding x for this calendar widget style.
  public var paddingX: Double
  /// The padding y for this calendar widget style.
  public var paddingY: Double
  /// The spacing for this calendar widget style.
  public var spacing: Double
  /// The opacity for this calendar widget style.
  public var opacity: Double

  /// Creates a calendar widget style.
  public init(
    icon: String,
    textColorHex: String?,
    backgroundColorHex: String?,
    borderColorHex: String?,
    borderWidth: Double,
    cornerRadius: Double,
    marginX: Double,
    marginY: Double,
    paddingX: Double,
    paddingY: Double,
    spacing: Double,
    opacity: Double
  ) {
    self.icon = icon
    self.textColorHex = textColorHex
    self.backgroundColorHex = backgroundColorHex
    self.borderColorHex = borderColorHex
    self.borderWidth = borderWidth
    self.cornerRadius = cornerRadius
    self.marginX = marginX
    self.marginY = marginY
    self.paddingX = paddingX
    self.paddingY = paddingY
    self.spacing = spacing
    self.opacity = opacity
  }
}
