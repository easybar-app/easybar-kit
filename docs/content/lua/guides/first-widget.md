# First Widget

This guide walks through the smallest useful Lua widget and explains each piece.

## What we are building

We will create one clock widget that:

- appears on the right side of the bar
- shows the current time
- refreshes once per minute

## Minimal example

```lua
local clock

clock = easybar.add(easybar.kind.item, "clock", {
    position = "right",
    order = 10,
    label = os.date("%H:%M"),
    interval = 60,
    on_interval = function()
        clock:set({
            label = os.date("%H:%M"),
        })
    end,
})
```

## How it works

`easybar.add(...)` creates one node and returns its handle.

The arguments are:

1. the node kind, here `easybar.kind.item`
2. a stable node id, here `"clock"`
3. a property table describing placement, content, and behavior

## Important fields

- `position = "right"` places the node on the right side of the bar
- `order = 10` controls render ordering among other root nodes
- `label = ...` sets the displayed text
- `interval = 60` asks EasyBar to call `on_interval` 60 seconds after the widget registers, then every 60 seconds after that
- `on_interval = function() ... end` updates the node in place

The `clock` variable stores the handle returned by EasyBar, which lets the callback call `clock:set(...)` later.

## Where this widget goes

EasyBar recursively loads every `.lua` file below the configured widgets directory. The app
repository keeps its single-file examples flat below `examples/`; only the multi-file inbox demo
uses a subdirectory. No category or filename is required by the loader. Generic helpers can live
below `shared/`, while `lib/` remains on the module search path for compatibility.

That directory is configured with `[app].widgets_dir` in `config.toml`.

See [App Settings](../../configuration/app.md).

## Expanding the widget

Once the basic widget works, you can add:

- an icon through `icon = { string = "..." }`
- colors through `label.color` or `color`
- theme-driven colors through `easybar.theme.colors.text` or `easybar.theme.ref.text`
- click behavior through `node:subscribe(...)`
- a popup through the `popup` property

## Next steps

- Read [Reusable Modules](modules.md) when several widgets need the same helper functions.
- Read [Subscribe To Events](subscribe-to-events.md) to make the widget interactive.
- Read [Style Popups And Groups](style-popups-and-groups.md) to shape more complex widgets.
- Keep [API Summary](../api-summary.md) open as a quick reference.
