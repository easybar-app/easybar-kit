# Reusable Modules

EasyBar recursively executes every regular file below `widgets_dir` with a `.lua` extension. Extension matching is case-insensitive. Directory names such as `simple`, `shared`, or `lib`, and filenames such as `widget.lua`, are organizational conventions only.

The widget root, `shared/`, and legacy `lib/` are also added to Lua's module search path before files load, so code can continue to use standard `require(...)` calls without changing `package.path`.

## Recommended layout

```text
~/.config/easybar/widgets/
├── simple/
│   └── clock.lua
├── github/
│   ├── widget.lua
│   └── README.md
├── brew/
│   ├── widget.lua
│   ├── policy.lua
│   └── README.md
├── shared/
│   ├── inbox.lua
│   ├── retry.lua
│   ├── text.lua
│   └── status/
│       └── init.lua
├── lib/
│   └── legacy.lua
└── assets/
    └── github.svg
```

All `.lua` files in this tree run during startup. A reusable module should therefore do only declarative work at top level: create local functions or tables and return its public value. Do not start timers, commands, subscriptions, or inbox publishing until an explicit function is called by the consuming widget.

The same module may later execute through `require(...)`. Direct startup execution does not populate `package.loaded`, while `require(...)` does, so top-level module code must be safe to evaluate more than once.

Keep small examples in the matching category. Use a service directory when an integration gains configuration, helper modules, documentation, tests, or assets. The filename inside that directory is your choice.

Do not install multiple presentation variants for the same service unless duplicate polling is intentional.

## Create a module

A module normally returns one table containing its public functions:

```lua
-- ~/.config/easybar/widgets/shared/text.lua
local M = {}

function M.trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

return M
```

Use it from any Lua file:

```lua
local text = require("text")

local value = text.trim("  ready  ")
```

EasyBar resolves that call from:

```text
<widgets_dir>/shared/text.lua
```

## Package directories

For a larger module, use an `init.lua` file:

```text
shared/
└── status/
    └── init.lua
```

Then load it with:

```lua
local status = require("status")
```

Dots in module names map to subdirectories. For example:

```lua
local format = require("network.format")
```

resolves to:

```text
<widgets_dir>/shared/network/format.lua
```

## Shared text helper

The official [`shared` package](https://github.com/easybar-app/widgets/tree/main/packages/shared) includes a small text module:

```lua
local text = require("text")

local clean = text.trim(command_output)
local short = text.truncate(clean, 80)
```

`text.lua` provides:

- `text.trim(value)`
- `text.truncate(value, maximum_length, omission?)`

This file is an example in the user widget directory, not a built-in part of the public
`easybar` API. You own it and can extend or replace it.

## Inbox data helper

The official inbox packages share the `shared` package's `inbox.lua` for three data-boundary operations:

```lua
local inbox = require("inbox")

local values = inbox.decode_array(easybar.json, command_output)
if values == nil then
    local message = inbox.error_message(command_output, "The service returned invalid data")
    -- Keep the last valid snapshot and publish `message` as an additional error item.
end

local timestamp = inbox.timestamp("2026-08-03T09:45:00.123+02:00")
```

`inbox.lua` provides:

- `inbox.decode_array(json_module, output)` decodes a dense JSON array and returns `nil` for invalid
  JSON or an object-shaped response. Pass `easybar.json` explicitly because modules do not receive
  the widget-scoped API automatically.
- `inbox.error_message(output, fallback)` trims and limits an error body to
  `inbox.maximum_error_length` characters, using the fallback when output is empty. The official
  value is 12,000 characters, safely below the native inbox body's byte limit even for UTF-8 text.
- `inbox.timestamp(value)` converts an ISO-8601 timestamp with `Z` or a numeric timezone offset to
  Unix seconds. Fractional seconds are accepted and discarded. Invalid dates and timestamps
  without a timezone return `nil`.

These helpers deliberately do not own snapshots, refresh scheduling, or actions. The publishing
widget remains responsible for validating service-specific fields and deciding whether a failed
refresh should retain existing items.

The `shared` package's `retry.lua` module coordinates asynchronous attempts through `easybar.after(...)`. Pass
the widget-scoped API explicitly because modules do not receive `easybar` automatically:

```lua
local retry = require("retry")

retry.run(easybar, {
    delays = { 2, 5 },
    attempt = function(done, attempt_number)
        return easybar.spawn_async({ "gh", "api", "notifications" }, {}, done)
    end,
    should_retry = retry.is_transient_network_error,
    on_complete = function(output, code, attempts)
        -- Runs once with the final result.
    end,
})
```

The first attempt starts immediately. `delays[1]` is the wait before attempt 2, `delays[2]` is the
wait before attempt 3, and so on. When no delay remains, the last result is final.

`retry.run(...)` returns a `RetryOperation` with:

- `operation:is_active()`
- `operation:cancel()`

Store that handle only when the widget has an actual cancellation or replacement policy. The retry
callbacks and host timers keep the operation alive until completion, so assigning an unused
`active_refresh` variable adds dead state without changing behavior.

When you do store the handle, clear it in `on_complete` and before cancellation:

```lua
local active_refresh

local function cancel_refresh()
    local operation = active_refresh
    active_refresh = nil

    if operation ~= nil then
        operation:cancel()
    end
end
```

Cancellation stops either the active asynchronous command or the pending backoff timer and does not
call `on_complete`.

`retry.is_transient_network_error(output, code)` is a conservative heuristic for DNS, connection,
timeout, TLS, and common gateway failures. It never retries status `0` and never treats cancellation
status `130` as retryable. The retry helper is intended for idempotent reads. Do not automatically
retry updates, upgrades, acknowledgements, or other mutations because the remote operation may have
succeeded even when the local response was lost.

The module includes LuaLS annotations for `RetryOptions`, `RetryOperation`, attempt callbacks, retry
predicates, and completion callbacks. Keeping these annotations beside the implementation means
editors can validate custom retry policies without adding retry types to the global `easybar` stub.

## Module lifetime and state

Lua caches successful `require(...)` calls in `package.loaded`. Requiring the same module again in
the same runtime returns the same value without executing the module a second time.

That means mutable module state is shared by every widget that requires the module. Prefer stateless
helper modules unless shared state is intentional.

Restarting the Lua runtime or reloading EasyBar clears the process and therefore clears the module
cache.

## EasyBar API access

Every discovered file receives a widget-scoped `easybar` value during direct startup execution. The same file does not receive that injected value when Lua loads it later through standard `require(...)`.

Keep reusable modules independent from `easybar` at top level. When a helper needs host-specific data, pass the value explicitly:

```lua
-- shared/widget_style.lua
local M = {}

function M.label(color, value)
    return {
        string = value,
        color = color,
    }
end

return M
```

```lua
-- clock.lua
local widget_style = require("widget_style")

local label = widget_style.label(easybar.theme.ref.text, os.date("%H:%M"))
```

Resolve files beside the current entrypoint with `easybar.asset(...)`. Use `easybar.asset("@/assets/name.svg")` for assets shared from the configured widgets root, then pass the resolved path to a helper only when needed.

## Naming and precedence

EasyBar searches widget modules in this order:

```text
<widgets_dir>/?.lua
<widgets_dir>/?/init.lua
<widgets_dir>/shared/?.lua
<widgets_dir>/shared/?/init.lua
<widgets_dir>/lib/?.lua
<widgets_dir>/lib/?/init.lua
```

Dots map to subdirectories. For example, `require("brew.policy")` resolves first to
`<widgets_dir>/brew/policy.lua`. A generic `require("text")` normally resolves to
`<widgets_dir>/shared/text.lua` when no top-level `text.lua` or `text/init.lua` exists.

Use the widget name as the first component for private package modules. Keep generic module names in
`shared/`, and avoid names likely to collide with third-party Lua packages.

## Errors

Every discovered `.lua` file is executed. A syntax error or top-level failure is reported for that file, its transactional changes are rolled back, and the remaining files continue loading.

A missing or failing `require(...)` call fails the consuming file in the same way. Because support modules are also discovered directly, a broken module is reported even when no other file requires it.
