import Foundation

/// Actions exposed by the native AeroSpace-mode widget context menu.
enum AeroSpaceModeContextMenuAction: Equatable {
  case setLayout(AeroSpaceLayoutMode)
  case toggleShowIcon
  case toggleShowText
  case openConfig
  case refresh

  private static let layoutPrefix = "aerospace_mode.layout."

  /// Stable context-menu action identifier.
  var id: String {
    switch self {
    case .setLayout(let mode): return "\(Self.layoutPrefix)\(mode.rawValue)"
    case .toggleShowIcon: return "aerospace_mode.toggle_show_icon"
    case .toggleShowText: return "aerospace_mode.toggle_show_text"
    case .openConfig: return "aerospace_mode.open_config"
    case .refresh: return "aerospace_mode.refresh"
    }
  }

  /// Decodes one stable context-menu action identifier.
  init?(id: String) {
    if id.hasPrefix(Self.layoutPrefix),
      let mode = AeroSpaceLayoutMode(rawValue: String(id.dropFirst(Self.layoutPrefix.count))),
      mode != .unknown
    {
      self = .setLayout(mode)
      return
    }

    switch id {
    case Self.toggleShowIcon.id: self = .toggleShowIcon
    case Self.toggleShowText.id: self = .toggleShowText
    case Self.openConfig.id: self = .openConfig
    case Self.refresh.id: self = .refresh
    default: return nil
    }
  }
}

/// Builds the native AeroSpace-mode context menu from config and live layout state.
enum AeroSpaceModeContextMenu {
  private static let layoutOptions: [(AeroSpaceLayoutMode, String)] = [
    (.hTiles, "Horizontal Tiles"),
    (.vTiles, "Vertical Tiles"),
    (.hAccordion, "Horizontal Accordion"),
    (.vAccordion, "Vertical Accordion"),
    (.floating, "Floating"),
  ]

  static func make(
    config: Config.AeroSpaceModeBuiltinConfig,
    currentLayout: AeroSpaceLayoutMode
  ) -> [WidgetContextMenuItem] {
    let layoutItems = layoutOptions.map { mode, title in
      WidgetContextMenuItem(
        id: AeroSpaceModeContextMenuAction.setLayout(mode).id,
        title: title,
        checked: currentLayout == mode
      )
    }

    return [
      WidgetContextMenuItem(title: "Layout", submenu: layoutItems),
      WidgetContextMenuItem(separator: true),
      WidgetContextMenuItem(
        id: AeroSpaceModeContextMenuAction.toggleShowIcon.id,
        title: "Show Icon",
        enabled: !config.showIcon || config.showText,
        checked: config.showIcon
      ),
      WidgetContextMenuItem(
        id: AeroSpaceModeContextMenuAction.toggleShowText.id,
        title: "Show Text",
        enabled: !config.showText || config.showIcon,
        checked: config.showText
      ),
      WidgetContextMenuItem(separator: true),
      WidgetContextMenuItem(
        id: AeroSpaceModeContextMenuAction.openConfig.id,
        title: "Open AeroSpace Config"
      ),
      WidgetContextMenuItem(
        id: AeroSpaceModeContextMenuAction.refresh.id,
        title: "Refresh AeroSpace State"
      ),
    ]
  }
}
