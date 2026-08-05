# Native Context Menus

Lua nodes can declare a native macOS menu for right-click actions. Subscribe to
`easybar.events.context_menu.clicked` to handle selections.

```lua
local github = easybar.add(easybar.kind.item, "github", {
    icon = "󰊤",
    label = "GitHub",
    context_menu = {
        { id = "refresh", title = "Refresh" },
        { id = "open_notifications", title = "Open Notifications" },
        { separator = true },
        {
            title = "Filter",
            submenu = {
                { id = "filter_all", title = "All", checked = true },
                { id = "filter_mentions", title = "Mentions" },
            },
        },
    },
})

github:subscribe(easybar.events.context_menu.clicked, function(event)
    if event.action_id == "refresh" then
        refresh()
    elseif event.action_id == "open_notifications" then
        open_notifications()
    end
end)
```

Selectable entries require a non-empty `id` and `title`. `enabled` defaults to `true`; disabled
entries remain visible but cannot emit an action. `checked` defaults to `false` and controls the
native checkmark. A separator uses `{ separator = true }`. A submenu heading requires a `title`
and a non-empty recursive `submenu`, but no action id.

The callback receives the root `event.widget_id`, the concrete `event.target_widget_id`, and the
selected `event.action_id`.

## Replace or remove a menu

`node:set(...)` replaces the complete menu definition, which is useful for checked state and
enabled actions:

```lua
github:set({
    context_menu = {
        { id = "refresh", title = "Refresh", enabled = false },
    },
})
```

Remove it with:

```lua
github:unset("context_menu")
```

When a node has a context menu, its right-click opens that menu and does not also emit the normal
right-button `mouse.clicked` event. Without a context menu, existing right-click subscriptions
continue to work unchanged. Right-clicking empty bar space continues to open EasyBar's application
menu.

Invalid entries are omitted without rejecting the widget tree. Menus support up to eight nested
levels and 256 total entries per node.

See the complete bundled [`widgets/simple/context-menu.lua`](https://github.com/gi8lino/easybar/blob/main/widgets/simple/context-menu.lua)
example for dynamic checked filters and native actions.
