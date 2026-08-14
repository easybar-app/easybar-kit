import EasyBarShared
import Foundation

public enum CalendarPopupMode: String, CaseIterable, Sendable {
  case none
  case upcoming
  case month
}

public enum CalendarAnchorLayout: String, Codable, CaseIterable, Sendable {
  case row
  case column
}

public enum CalendarAnchorFieldKind: String, Codable, CaseIterable, Sendable {
  case time
  case date
}

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

public struct CalendarWidgetPlacement: Sendable {
  public var enabled: Bool
  public var position: WidgetPosition
  public var order: Int
  public var group: String?

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

  public var groupID: String? {
    guard let group else { return nil }

    let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    return trimmed
  }
}

public struct CalendarWidgetStyle: Sendable {
  public var icon: String
  public var textColorHex: String?
  public var backgroundColorHex: String?
  public var borderColorHex: String?
  public var borderWidth: Double
  public var cornerRadius: Double
  public var marginX: Double
  public var marginY: Double
  public var paddingX: Double
  public var paddingY: Double
  public var spacing: Double
  public var opacity: Double

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
