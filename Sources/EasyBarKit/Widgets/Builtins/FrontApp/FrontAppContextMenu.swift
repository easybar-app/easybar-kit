import Foundation

/// Actions exposed by the native front-app widget context menu.
enum FrontAppContextMenuAction: Equatable {
  case hideApplication
  case toggleShowIcon
  case toggleShowName
  case revealInFinder

  /// Stable context-menu action identifier.
  var id: String {
    switch self {
    case .hideApplication: return "front_app.hide"
    case .toggleShowIcon: return "front_app.toggle_show_icon"
    case .toggleShowName: return "front_app.toggle_show_name"
    case .revealInFinder: return "front_app.reveal_in_finder"
    }
  }

  /// Decodes one stable context-menu action identifier.
  init?(id: String) {
    switch id {
    case Self.hideApplication.id: self = .hideApplication
    case Self.toggleShowIcon.id: self = .toggleShowIcon
    case Self.toggleShowName.id: self = .toggleShowName
    case Self.revealInFinder.id: self = .revealInFinder
    default: return nil
    }
  }
}

/// Builds the native front-app context menu from config and focused-app state.
enum FrontAppContextMenu {
  static func make(
    config: Config.FrontAppBuiltinConfig,
    canHideFocusedApp: Bool,
    canRevealFocusedApp: Bool
  ) -> [WidgetContextMenuItem] {
    [
      WidgetContextMenuItem(
        id: FrontAppContextMenuAction.hideApplication.id,
        title: "Hide Application",
        enabled: canHideFocusedApp
      ),
      WidgetContextMenuItem(separator: true),
      WidgetContextMenuItem(
        id: FrontAppContextMenuAction.toggleShowIcon.id,
        title: "Show Icon",
        enabled: !config.showIcon || config.showName,
        checked: config.showIcon
      ),
      WidgetContextMenuItem(
        id: FrontAppContextMenuAction.toggleShowName.id,
        title: "Show Name",
        enabled: !config.showName || config.showIcon,
        checked: config.showName
      ),
      WidgetContextMenuItem(separator: true),
      WidgetContextMenuItem(
        id: FrontAppContextMenuAction.revealInFinder.id,
        title: "Show in Finder",
        enabled: canRevealFocusedApp
      ),
    ]
  }
}
