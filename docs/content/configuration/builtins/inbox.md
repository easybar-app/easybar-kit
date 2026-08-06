# Inbox

The native inbox collects structured messages published by Lua widgets or the `easybar inbox` CLI
into one bar item. It displays the total unread count and can group messages by source, date,
category, severity, or not at all.

```toml
[builtins.inbox]
enabled = true
position = "right"
order = 5

[builtins.inbox.content]
group_by = "source"
show_unread_count = true
show_source_actions = true
show_refresh_all = true
refresh_all_icon = "arrow.clockwise"
refresh_all_tooltip = "Refresh all"
show_mark_all_read = true
mark_all_read_icon = "envelope.open"
mark_all_read_tooltip = "Mark all read"
show_dismiss_all = true
dismiss_all_icon = "xmark.circle"
dismiss_all_tooltip = "Dismiss all"
popup_width = 360
popup_max_height = 540
use_inactive_style_when_read = true
show_when_empty = true
```

## Appearance

The unread and read states have independent icons and colors:

```toml
[builtins.inbox.style]
unread_icon = "􀛬"
read_icon = "􀍕"
unread_icon_color = "theme.text_secondary"
read_icon_color = "theme.muted"
unread_count_color = "theme.accent"
```

`[builtins.inbox.colors]` controls the popup background, border, title, body, muted labels, item background, actions, and severity indicators.

## Behavior

When there are no unread messages, `use_inactive_style_when_read` selects `read_icon` and `read_icon_color`. Otherwise the anchor uses `unread_icon` and `unread_icon_color`. Set `show_when_empty = false` to hide the anchor when no messages exist. Set `show_unread_count = false` to retain the stateful icon without its numeric badge.

The popup header can show publisher-provided source actions and an inbox-wide **Refresh all** button.
Set `show_source_actions = false` to hide the source menus; **Refresh all** remains available for
participating sources.

The **Refresh all**, **Mark all read**, and **Dismiss all** header controls can each be hidden with
their `show_*` option. Their icons accept configurable SF Symbol names, and their tooltip text is
shown on hover and used as the accessible button label.

While refresh activity and message snapshots change, the popup remeasures its content and adjusts
its panel height. Temporary progress rows therefore do not leave stale empty space or clip the
updated message list.

See [Native Inbox for Lua](../../lua/guides/inbox.md) for publishing snapshots, limited Markdown,
item actions, source actions, activity states, persistence, and dismissal behavior. Local shell scripts can instead
use [`easybar inbox`](../../runtime/inbox.md) to send, inspect, update, dismiss, remove,
and clear messages through the control socket.

## Context menu

Right-click the inbox anchor to change grouping, sorting, unread-count visibility, inactive styling,
empty-state visibility, or source-action visibility. Each change is written to `config.toml`
immediately while preserving comments, whitespace, and unrelated settings.
