# Style Guidelines

These guidelines keep Lua widgets predictable and easy to debug.

## Use stable IDs

Node IDs should be stable across reloads:

```lua
easybar.add(easybar.kind.item, "brew_outdated", {
    position = "right",
})
```

Avoid dynamic IDs unless you are intentionally creating a dynamic list.

## Store handles

Always keep the handle returned by `easybar.add(...)` when the node needs updates or subscriptions.

```lua
local clock = easybar.add(easybar.kind.item, "clock", {
    label = os.date("%H:%M"),
})
```

## Prefer state-driven rendering

Keep state in Lua variables and render from that state.

```lua
local count = 0
local widget

local function render()
    widget:set({
        label = tostring(count),
    })
end
```

## Prefer groups for composite widgets

Use `group` when multiple child nodes belong together visually.

Use child subscriptions when only specific parts should be clickable.

## Prefer theme values for shared styling

Use `easybar.theme.colors.<token>` when you want one resolved hex color in Lua.

Use `easybar.theme.ref.<token>` when a node color field should stay coupled to the active theme.

## Use events before polling

Prefer event subscriptions for real runtime events.

Use intervals only for polling external state.

## Avoid blocking the runtime

Prefer `easybar.spawn_async(...)` for ordinary executable invocations and `easybar.exec_async(...)` only when shell syntax is required. Use `easybar.after(...)` for delays instead of launching `sleep`.

Avoid expensive synchronous work in mouse handlers, interval callbacks, and frequent events.

## Keep side effects inside handlers

Avoid doing too much work at file load time.

Good places for side effects:

- `on_interval`
- `node:subscribe(...)` handlers
- explicit refresh functions

## Format with StyLua

Use StyLua to keep widget files consistently formatted:

```bash
brew install stylua
stylua ~/.config/easybar/widgets
```

Check formatting without changing files:

```bash
stylua --check ~/.config/easybar/widgets
```
