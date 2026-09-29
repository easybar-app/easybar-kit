import Foundation
import SwiftTOMLEdit

extension InboxGroupMode: TOMLStringDecodable {}
extension InboxSortMode: TOMLStringDecodable {}

extension Config {
  /// Stores inbox builtin config data.
  struct InboxBuiltinConfig: @unchecked Sendable {
    /// The placement for this inbox builtin config.
    var placement: BuiltinWidgetPlacement
    /// The style for this inbox builtin config.
    var style: InboxBuiltinStyle
    /// The group by for this inbox builtin config.
    var groupBy: InboxGroupMode
    /// The sort by for this inbox builtin config.
    var sortBy: InboxSortMode
    /// Whether the sort descending option is enabled for this inbox builtin config.
    var sortDescending: Bool
    /// Whether this inbox builtin config shows unread count.
    var showUnreadCount: Bool
    /// Whether this inbox builtin config uses inactive style when read.
    var useInactiveStyleWhenRead: Bool
    /// Whether this inbox builtin config shows when empty.
    var showWhenEmpty: Bool
    /// Whether this inbox builtin config shows source actions.
    var showSourceActions: Bool
    /// Whether this inbox builtin config shows refresh all.
    var showRefreshAll: Bool
    /// The refresh all icon for this inbox builtin config.
    var refreshAllIcon: String
    /// The refresh all tooltip for this inbox builtin config.
    var refreshAllTooltip: String
    /// Whether this inbox builtin config shows mark all read.
    var showMarkAllRead: Bool
    /// The mark all read icon for this inbox builtin config.
    var markAllReadIcon: String
    /// The mark all read tooltip for this inbox builtin config.
    var markAllReadTooltip: String
    /// Whether this inbox builtin config shows dismiss all.
    var showDismissAll: Bool
    /// The dismiss all icon for this inbox builtin config.
    var dismissAllIcon: String
    /// The dismiss all tooltip for this inbox builtin config.
    var dismissAllTooltip: String
    /// The popup width for this inbox builtin config.
    var popupWidth: Int
    /// The popup max height for this inbox builtin config.
    var popupMaxHeight: Int
    /// The popup background color hex for this inbox builtin config.
    var popupBackgroundColorHex: String?
    /// The popup border color hex for this inbox builtin config.
    var popupBorderColorHex: String?
    /// The popup title color hex for this inbox builtin config.
    var popupTitleColorHex: String?
    /// The popup text color hex for this inbox builtin config.
    var popupTextColorHex: String?
    /// The popup muted color hex for this inbox builtin config.
    var popupMutedColorHex: String?
    /// The popup item background color hex for this inbox builtin config.
    var popupItemBackgroundColorHex: String?
    /// The popup action color hex for this inbox builtin config.
    var popupActionColorHex: String?
    /// The info color hex for this inbox builtin config.
    var infoColorHex: String?
    /// The success color hex for this inbox builtin config.
    var successColorHex: String?
    /// The warning color hex for this inbox builtin config.
    var warningColorHex: String?
    /// The error color hex for this inbox builtin config.
    var errorColorHex: String?
    /// The max items for this inbox builtin config.
    var maxItems: Int

    /// Whether this inbox builtin config is enabled.
    var enabled: Bool { placement.enabled }

    static let `default` = InboxBuiltinConfig(
      placement: .init(enabled: true, position: .right, order: 5),
      style: .init(
        unreadIcon: "􀛬",
        readIcon: "􀍕",
        unreadIconColorHex: "theme.text_secondary",
        readIconColorHex: "theme.muted",
        unreadCountColorHex: "theme.accent",
        chrome: .init(
          backgroundColorHex: "theme.transparent",
          borderColorHex: "theme.transparent",
          borderWidth: 0,
          cornerRadius: 8,
          marginX: 0,
          marginY: 0,
          paddingX: 7,
          paddingY: 3,
          spacing: 4,
          opacity: 1
        )
      ),
      groupBy: .source,
      sortBy: .timestamp,
      sortDescending: true,
      showUnreadCount: true,
      useInactiveStyleWhenRead: true,
      showWhenEmpty: true,
      showSourceActions: true,
      showRefreshAll: true,
      refreshAllIcon: "arrow.clockwise",
      refreshAllTooltip: "Refresh all",
      showMarkAllRead: true,
      markAllReadIcon: "envelope.open",
      markAllReadTooltip: "Mark all read",
      showDismissAll: true,
      dismissAllIcon: "xmark.circle",
      dismissAllTooltip: "Dismiss all",
      popupWidth: 360,
      popupMaxHeight: 540,
      popupBackgroundColorHex: "theme.background",
      popupBorderColorHex: "theme.border_strong",
      popupTitleColorHex: "theme.text",
      popupTextColorHex: "theme.text_secondary",
      popupMutedColorHex: "theme.muted",
      popupItemBackgroundColorHex: "theme.surface",
      popupActionColorHex: "theme.accent",
      infoColorHex: "theme.accent",
      successColorHex: "theme.success",
      warningColorHex: "theme.warning",
      errorColorHex: "theme.error",
      maxItems: 100
    )
  }

  /// Parses inbox builtin.
  func parseInboxBuiltin(from builtins: ConfigReader) throws {
    guard let inbox = try builtins.optionalSection("inbox") else { return }
    let placement = try parseBuiltinPlacement(reader: inbox, fallback: builtinInbox.placement)
    let styleReader = try inbox.section("style")
    let chrome = try parseBuiltinChromeStyle(
      reader: styleReader,
      fallback: builtinInbox.style.chrome
    )
    let style = InboxBuiltinStyle(
      unreadIcon: try styleReader.string("unread_icon", fallback: builtinInbox.style.unreadIcon),
      readIcon: try styleReader.string("read_icon", fallback: builtinInbox.style.readIcon),
      unreadIconColorHex: try styleReader.optionalColor(
        "unread_icon_color", fallback: builtinInbox.style.unreadIconColorHex),
      readIconColorHex: try styleReader.optionalColor(
        "read_icon_color", fallback: builtinInbox.style.readIconColorHex),
      unreadCountColorHex: try styleReader.optionalColor(
        "unread_count_color", fallback: builtinInbox.style.unreadCountColorHex),
      chrome: chrome
    )
    let content = try inbox.section("content")
    let colors = try inbox.optionalSection("colors")

    builtinInbox = InboxBuiltinConfig(
      placement: placement,
      style: style,
      groupBy: try content.enum("group_by", fallback: builtinInbox.groupBy),
      sortBy: try content.enum("sort_by", fallback: builtinInbox.sortBy),
      sortDescending: try content.bool("sort_descending", fallback: builtinInbox.sortDescending),
      showUnreadCount: try content.bool("show_unread_count", fallback: builtinInbox.showUnreadCount),
      useInactiveStyleWhenRead: try content.bool(
        "use_inactive_style_when_read", fallback: builtinInbox.useInactiveStyleWhenRead),
      showWhenEmpty: try content.bool("show_when_empty", fallback: builtinInbox.showWhenEmpty),
      showSourceActions: try content.bool(
        "show_source_actions", fallback: builtinInbox.showSourceActions),
      showRefreshAll: try content.bool(
        "show_refresh_all", fallback: builtinInbox.showRefreshAll),
      refreshAllIcon: try nonEmptyInboxString(
        "refresh_all_icon", from: content, fallback: builtinInbox.refreshAllIcon),
      refreshAllTooltip: try nonEmptyInboxString(
        "refresh_all_tooltip", from: content, fallback: builtinInbox.refreshAllTooltip),
      showMarkAllRead: try content.bool(
        "show_mark_all_read", fallback: builtinInbox.showMarkAllRead),
      markAllReadIcon: try nonEmptyInboxString(
        "mark_all_read_icon", from: content, fallback: builtinInbox.markAllReadIcon),
      markAllReadTooltip: try nonEmptyInboxString(
        "mark_all_read_tooltip", from: content, fallback: builtinInbox.markAllReadTooltip),
      showDismissAll: try content.bool(
        "show_dismiss_all", fallback: builtinInbox.showDismissAll),
      dismissAllIcon: try nonEmptyInboxString(
        "dismiss_all_icon", from: content, fallback: builtinInbox.dismissAllIcon),
      dismissAllTooltip: try nonEmptyInboxString(
        "dismiss_all_tooltip", from: content, fallback: builtinInbox.dismissAllTooltip),
      popupWidth: try content.int(
        "popup_width", fallback: builtinInbox.popupWidth, minimum: 240, maximum: 800),
      popupMaxHeight: try content.int(
        "popup_max_height", fallback: builtinInbox.popupMaxHeight, minimum: 120, maximum: 1000),
      popupBackgroundColorHex: try colors?.optionalColor(
        "background", fallback: builtinInbox.popupBackgroundColorHex) ?? builtinInbox.popupBackgroundColorHex,
      popupBorderColorHex: try colors?.optionalColor("border", fallback: builtinInbox.popupBorderColorHex)
        ?? builtinInbox.popupBorderColorHex,
      popupTitleColorHex: try colors?.optionalColor("title", fallback: builtinInbox.popupTitleColorHex)
        ?? builtinInbox.popupTitleColorHex,
      popupTextColorHex: try colors?.optionalColor("text", fallback: builtinInbox.popupTextColorHex)
        ?? builtinInbox.popupTextColorHex,
      popupMutedColorHex: try colors?.optionalColor("muted", fallback: builtinInbox.popupMutedColorHex)
        ?? builtinInbox.popupMutedColorHex,
      popupItemBackgroundColorHex: try colors?.optionalColor(
        "item_background", fallback: builtinInbox.popupItemBackgroundColorHex)
        ?? builtinInbox.popupItemBackgroundColorHex,
      popupActionColorHex: try colors?.optionalColor("action", fallback: builtinInbox.popupActionColorHex)
        ?? builtinInbox.popupActionColorHex,
      infoColorHex: try colors?.optionalColor("info", fallback: builtinInbox.infoColorHex)
        ?? builtinInbox.infoColorHex,
      successColorHex: try colors?.optionalColor("success", fallback: builtinInbox.successColorHex)
        ?? builtinInbox.successColorHex,
      warningColorHex: try colors?.optionalColor("warning", fallback: builtinInbox.warningColorHex)
        ?? builtinInbox.warningColorHex,
      errorColorHex: try colors?.optionalColor("error", fallback: builtinInbox.errorColorHex)
        ?? builtinInbox.errorColorHex,
      maxItems: try content.int("max_items", fallback: builtinInbox.maxItems, minimum: 1, maximum: 1000)
    )
  }

  /// Returns the non empty inbox string.
  private func nonEmptyInboxString(
    _ key: String,
    from reader: ConfigReader,
    fallback: String
  ) throws -> String {
    let value = try reader.string(key, fallback: fallback)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      throw ConfigError.invalidValue(
        path: reader.path(for: key),
        message: "expected a non-empty string"
      )
    }
    return value
  }
}
