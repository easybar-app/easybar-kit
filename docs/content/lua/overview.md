# Lua Widgets

EasyBar Lua widgets are node-based.

You create nodes, keep their handles, and update them with methods such as `node:set(...)` and `node:subscribe(...)`. You do not return widget trees directly.

Lua widgets are the right tool when you want:

- custom text, icons, or layout that built-ins do not provide
- shell-command integration or lightweight local scripting
- event-driven behavior tied to app changes, mouse input, timers, or helper-agent updates
- small personal workflows specific to your setup

If you have not decided whether Lua is the right tool yet, read [Built-ins Vs Lua](../getting-started/builtins-vs-lua.md).

Lua widgets are trusted local scripts. EasyBar gives each widget file its own API scope, but it does not sandbox arbitrary widget code.

## Minimal widget

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

## Mental model

Lua widgets follow this model:

1. create nodes with `easybar.add(...)`
2. store returned handles
3. update nodes with `node:set(...)`
4. subscribe to events with `node:subscribe(...)`
5. let EasyBar render the current node state

The Lua runtime is for custom widgets and user-specific behavior. Built-in platform-integrated widgets should usually stay native when possible.

## User-facing guides

- [First Widget](guides/first-widget.md) for a step-by-step starting point.
- [Reusable Modules](guides/modules.md) for service packages below `integrations/` and generic helpers below `shared/`.
- [Subscribe To Events](guides/subscribe-to-events.md) for event-driven updates.
- [Commands](guides/commands.md) for shell-command integration.
- [Widget Settings](guides/storage.md) for reading and persisting widget-owned configuration.
- [Grouping](guides/grouping.md) and [Popups](guides/popups.md) for richer layouts.
- [Editor Support](guides/editor-support.md) for LuaLS setup.
- [Examples](guides/examples.md) for complete patterns.
- [Bundled Widgets](guides/bundled-widgets.md) for shipped examples, dependencies, and inbox variants.

## Exact API reference

The generated API reference is useful when you need exact function names, event names, and property fields:

- [Functions](reference/functions.md)
- [Node kinds](reference/node-kinds.md)
- [Events](reference/events.md)
- [Properties](reference/properties.md)

Use the guides for concepts and patterns. Use the reference pages for exact API details.

