# Intervals

Use `interval` with `on_interval` when a widget needs to poll.

EasyBar schedules intervals per widget. If a widget sets `interval = 1800`,
the backend starts that widget's timer when the widget registers its interval
handler and fires `on_interval` 1800 seconds later, then every 1800 seconds
after that. It does not wait for the next wall-clock boundary.

```lua
local clock

clock = easybar.add(easybar.kind.item, "clock", {
    position = "right",
    order = 10,
    interval = 60,
    label = os.date("%H:%M"),
    on_interval = function()
        clock:set({
            label = os.date("%H:%M"),
        })
    end,
})
```

## Flow

```mermaid
flowchart TD
    A["Widget loads in Lua"] --> B["Widget declares interval and on_interval"]
    B --> C["Lua publishes widget-scoped interval subscription"]
    C --> D["Swift EventManager stores widget schedule"]
    D --> E["Swift TimerEvents starts repeating timer for that widget"]
    E --> F["Interval elapses"]
    F --> G["Swift emits targeted interval_tick for that widget"]
    G --> H["Lua dispatches only that widget's on_interval handler"]
    H --> I["Widget updates state and re-renders"]
    I --> E
```

## Timing semantics

- `interval = 60` means 60 seconds after registration, then every 60 seconds after that.
- Each widget owns its own cadence.
- Changing `interval` replaces that widget's schedule with a new one.
- Removing the widget removes its interval schedule.

## Referencing the node itself

When an interval callback needs to reference its own handle, declare the variable before assigning it:

```lua
local clock

clock = easybar.add(easybar.kind.item, "clock", {
    interval = 60,
    on_interval = function()
        clock:set({
            label = os.date("%H:%M"),
        })
    end,
})
```

Do not write this:

```lua
local clock = easybar.add(easybar.kind.item, "clock", {
    interval = 60,
    on_interval = function()
        clock:set({
            label = os.date("%H:%M"),
        })
    end,
})
```

The callback may close over `clock` before it has been assigned.

## When to use intervals

Use intervals for polling:

- package manager state
- shell command output
- API checks
- periodic time-based updates

Use event subscriptions for real events:

- `network_change`
- `wifi_change`
- `volume_change`
- `system_woke`
- mouse events

## One-shot delays

Use `easybar.after(delay_seconds, callback)` for one non-blocking callback. It does not launch
`sleep`, consume an async command slot, or block the Lua runtime.

```lua
local pending_refresh

local function schedule_refresh()
    if pending_refresh ~= nil then
        pending_refresh:cancel()
    end

    pending_refresh = easybar.after(3, function()
        pending_refresh = nil
        refresh()
    end)
end
```

The returned timer handle supports `timer:cancel()`. Cancellation returns `true` only while the
callback is still pending. Timer handles belong to the current Lua runtime session and should not be
persisted across reloads.

## Network work after wake

`system_woke` is emitted promptly after macOS reports wake. EasyBar does not delay the event globally
because non-network widgets may need to react immediately. A widget that depends on Wi-Fi, VPN
routes, or DNS should schedule its own short delay and then use bounded retries for transient network
failures.

The official GitHub, GitLab, and Homebrew inbox packages use a three-second wake delay and retry
read-only checks after two and five seconds. Authentication failures and mutating operations are not
retried.
