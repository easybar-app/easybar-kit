# Native Inbox

EasyBar provides one shared native inbox for messages published by Lua widgets. The bar icon shows
the total unread count, and the popup can group messages from GitHub, GitLab, Homebrew, agents, or
any other widget source.

Copy [`widgets/inbox-demo.lua`](https://github.com/gi8lino/easybar/blob/main/widgets/inbox-demo.lua)
into your widgets directory to populate every severity with test data. Inbox-only GitHub and GitLab
publishers are available as `widgets/github-inbox.lua` and `widgets/gitlab-inbox.lua`; the original
widgets remain standalone alternatives.

[`widgets/brew-inbox.lua`](https://github.com/gi8lino/easybar/blob/main/widgets/brew-inbox.lua)
publishes outdated formulae and casks. Its source action panel provides refresh, update, upgrade-all,
and cancellation actions without adding control messages to the inbox.

## Publish a source snapshot

Use `replace` to atomically replace all current messages owned by one source:

```lua
easybar.inbox.replace("gitlab", {
    {
        id = "project!42",
        title = "Review merge request",
        body = "**Pipeline passed** · waiting for review",
        format = "markdown",
        timestamp = os.time(),
        category = "Merge requests",
        severity = "success",
        url = "https://gitlab.example.com/project/-/merge_requests/42",
        source = {
            name = "GitLab",
            icon = easybar.asset("assets/gitlab.svg"),
            color = "#FC6D26",
        },
        unread = true,
        actions = {
            { id = "open", title = "Open" },
            { id = "dismiss", title = "Dismiss" },
        },
    },
})
```

Stable `id` values preserve locally read messages across repeated source refreshes. Items omitted
from the next snapshot are removed. Clear the complete source explicitly with:

```lua
easybar.inbox.clear("gitlab")
```

Message content is owned by publishers and remains in memory. EasyBar persists only local read,
unread, and dismissed state in `inbox-state.json` inside `app.runtime_dir`.

Set `url` to add a native **Open** action. CLI-published URLs are restricted to HTTP(S); Lua
publishers should use HTTP(S) URLs as well.

Click a message to mark it read. Click its status dot to toggle read/unread, or right-click the
message to change its state or dismiss it. **Dismiss all** suppresses every currently displayed
message. Local changes survive restarts and publisher refreshes while the source and item ID remain
stable. Once a publisher omits an item, EasyBar removes its saved local state as well.

Optional per-item `source` metadata makes the origin more prominent without changing the stable
publisher name used for grouping and action routing. Set `name`, `icon`, and `color` independently;
the publisher source and the inbox's neutral text color are used as fallbacks. Source color identifies
the origin, while `severity` remains reserved for message status. `icon` accepts either text or an
image path resolved with `easybar.asset(...)`; SVG and raster images use the configured source color.

Set `dismissible = false` on persistent controls or status rows that must remain available. Such
items are excluded from both the per-message dismiss action and **Dismiss all**.

## Handle actions

Actions are routed to the widget that registered the matching source handler. EasyBar does not
execute arbitrary commands stored in inbox messages:

```lua
easybar.inbox.on_action("gitlab", function(event)
    if event.action_id == "open" then
        open_work_item(event.target_widget_id)
    elseif event.action_id == "dismiss" then
        dismiss_work_item(event.target_widget_id)
    end
end)
```

The event contains `source`, `target_widget_id` (the item id), and `action_id`.

## Add source actions to the icon menu

A publisher can add commands to its own submenu under the actions button in the inbox popup header.
Configure presentation separately from the handler so item actions and source-wide commands remain
distinct:

```lua
easybar.inbox.configure("gitlab", {
    actions = {
        {
            id = "refresh",
            title = "Refresh",
            include_in_refresh_all = true,
        },
    },
})

easybar.inbox.on_context_action("gitlab", function(event)
    if event.action_id == "refresh" then
        refresh_work_items()
    end
end)
```

Calling `configure` again replaces the source's complete action list, which allows widgets to
change their menu while work is running—for example, Homebrew replaces Update and Upgrade with
Cancel. Passing an empty `actions` array removes the submenu. Clearing a source's messages leaves
its independently configured actions available.

Set `include_in_refresh_all = true` on at most one source action to opt that source into the native
**Refresh all** button. EasyBar sends the existing `inbox.context_action` event with that action's
`id`; the action id does not need to be `refresh`. Disabled and busy actions remain visible but are
skipped by **Refresh all** until they become available. Item actions cannot opt in.

## Show asynchronous activity

Item and source actions accept optional `enabled` and `busy` fields. A busy item action is rendered
as a small progress indicator in the item. A busy source action is disabled in its submenu and shown
as a compact progress row below the inbox header after selection. The popup remains open until the
reported source activity finishes. A disabled action remains visible but cannot be selected. The
`enabled` and `busy` fields default to `true` and `false`, respectively.

Choose one busy scope for each operation:

| Operation scope                                                                    | Set `busy = true` on                                       | Progress location        |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------- | ------------------------ |
| Source-wide work, such as refresh, update, or upgrade all                          | The source action passed to `easybar.inbox.configure(...)` | Below the inbox header   |
| Item-specific work, such as marking one notification read or upgrading one package | The affected item's action in `easybar.inbox.replace(...)` | Inside the affected item |

Do not mark both a source action and an item action as busy for the same operation. One operation
should produce one progress indicator. While a source-wide refresh is busy, a matching inline
`refresh` action is shown as disabled `Refreshing…` status text instead of a second spinner.

For a source-wide refresh, republish the source configuration before and after the asynchronous work:

```lua
easybar.inbox.configure("gitlab", {
    actions = {
        {
            id = "refresh",
            title = "Refreshing…",
            enabled = false,
            busy = true,
            include_in_refresh_all = true,
        },
    },
})

fetch_async(function()
    publish_items()
    easybar.inbox.configure("gitlab", {
        actions = {
            {
                id = "refresh",
                title = "Refresh",
                include_in_refresh_all = true,
            },
        },
    })
end)
```

Use the same fields on an item's `actions` array for an item-specific operation. EasyBar deliberately
does not infer activity from `spawn_async`; the publisher owns the complete operation lifecycle,
including retries, pagination, follow-up commands, cancellation, and failures.

Active source operations remain visible as compact status rows after the actions menu closes. Item
activity always appears directly in the affected item.

## Text and Markdown

`body` defaults to plain text. Set `format = "markdown"` for limited inline Markdown such as
emphasis, strong text, inline code, and links. EasyBar deliberately does not render raw HTML,
remote images, tables, or embedded content in inbox messages.

## Configure the native center

```toml
[builtins.inbox]
enabled = true
position = "right"
order = 5

[builtins.inbox.style]
unread_icon = "􀛬"
read_icon = "􀍕"
unread_icon_color = "theme.text_secondary"
read_icon_color = "theme.muted"
unread_count_color = "theme.accent"

[builtins.inbox.colors]
background = "theme.background"
border = "theme.border_strong"
title = "theme.text"
text = "theme.text_secondary"
muted = "theme.muted"
item_background = "theme.surface"
action = "theme.accent"
info = "theme.accent"
success = "theme.success"
warning = "theme.warning"
error = "theme.error"

[builtins.inbox.content]
group_by = "source"       # source | date | category | severity | none
sort_by = "timestamp"     # timestamp | source | severity | title
sort_descending = true
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
max_items = 100
```

When there are no unread messages, EasyBar uses `read_icon` and `read_icon_color`. Unread messages
use `unread_icon` and `unread_icon_color`. Set `use_inactive_style_when_read = false` to keep the
unread icon and color after everything is read. Set
`show_when_empty = false` to remove the native icon when the inbox contains no messages. Set
`show_unread_count = false` to keep the stateful icon without displaying its numeric badge.
Set `show_source_actions = false` to hide the popup's publisher action-panel button while keeping
Mark all as read and Dismiss all available.
The three inbox-wide controls each have a `show_*` option and an `*_icon` SF Symbol name. Their
corresponding `*_tooltip` values provide both the hover tooltip and accessible label.

`popup_width` controls the complete popup width. `popup_max_height` limits the message list before
it becomes scrollable, while short inboxes continue to size naturally.

The `colors` section controls the complete native popup independently from the anchor's `style`.
Every value accepts a theme reference or a literal color, so a theme remains the default while
individual users can override only the parts they want.

The supported grouping modes are:

- `source`: publisher names such as GitHub and GitLab
- `date`: Today, Yesterday, an older date, or No date
- `category`: the item-provided category, with Other as a fallback
- `severity`: Info, Success, Warning, or Error
- `none`: one flat sorted list
