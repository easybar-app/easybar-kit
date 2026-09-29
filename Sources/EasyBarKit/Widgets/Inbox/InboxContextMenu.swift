import Foundation

/// Defines the supported inbox context menu action values.
enum InboxContextMenuAction: Equatable {
  case setGroup(InboxGroupMode)
  case setSort(InboxSortMode)
  case toggleDescending
  case toggleUnreadCount
  case toggleInactiveStyle
  case toggleShowWhenEmpty
  case toggleSourceActions

  /// Resolves an inbox context-menu identifier to its action.
  init?(id: String) {
    if let value = id.removingPrefix("inbox.group."),
      let mode = InboxGroupMode(rawValue: value)
    {
      self = .setGroup(mode)
      return
    }
    if let value = id.removingPrefix("inbox.sort."),
      let mode = InboxSortMode(rawValue: value)
    {
      self = .setSort(mode)
      return
    }
    switch id {
    case "inbox.sort_descending": self = .toggleDescending
    case "inbox.show_unread_count": self = .toggleUnreadCount
    case "inbox.use_inactive_style_when_read": self = .toggleInactiveStyle
    case "inbox.show_when_empty": self = .toggleShowWhenEmpty
    case "inbox.show_source_actions": self = .toggleSourceActions
    default: return nil
    }
  }
}

extension String {
  /// Returns the removing prefix.
  fileprivate func removingPrefix(_ prefix: String) -> String? {
    guard hasPrefix(prefix) else { return nil }
    let suffix = String(dropFirst(prefix.count))
    return suffix.isEmpty ? nil : suffix
  }
}

/// Defines the supported inbox context menu values.
enum InboxContextMenu {
  /// Creates the requested value.
  static func make(config: Config.InboxBuiltinConfig) -> [WidgetContextMenuItem] {
    let groups = InboxGroupMode.allCases.map { mode in
      WidgetContextMenuItem(
        id: "inbox.group.\(mode.rawValue)",
        title: title(mode.rawValue),
        checked: config.groupBy == mode
      )
    }
    let sorts = InboxSortMode.allCases.map { mode in
      WidgetContextMenuItem(
        id: "inbox.sort.\(mode.rawValue)",
        title: title(mode.rawValue),
        checked: config.sortBy == mode
      )
    }
    return [
      WidgetContextMenuItem(title: "Group By", submenu: groups),
      WidgetContextMenuItem(title: "Sort By", submenu: sorts),
      WidgetContextMenuItem(
        id: "inbox.sort_descending", title: "Newest First",
        checked: config.sortDescending
      ),
      WidgetContextMenuItem(separator: true),
      WidgetContextMenuItem(
        id: "inbox.show_unread_count", title: "Show Unread Count",
        checked: config.showUnreadCount
      ),
      WidgetContextMenuItem(
        id: "inbox.use_inactive_style_when_read", title: "Inactive Style When Read",
        checked: config.useInactiveStyleWhenRead
      ),
      WidgetContextMenuItem(
        id: "inbox.show_when_empty", title: "Show When Empty",
        checked: config.showWhenEmpty
      ),
      WidgetContextMenuItem(
        id: "inbox.show_source_actions", title: "Show Source Actions",
        checked: config.showSourceActions
      ),
    ]
  }

  /// Returns the title.
  private static func title(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
  }
}
