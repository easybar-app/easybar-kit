# Reusable Modules

EasyBar separates widget entrypoints from two kinds of reusable Lua modules:

- `integrations/<service>/` contains service-specific implementations and settings.
- `shared/` contains generic helpers reusable across unrelated widgets.

Both directories are added to Lua's module search path before widget files load, so entrypoints can
use standard `require(...)` calls without changing `package.path`. The older `lib/` directory
remains a supported fallback so existing widget setups continue to work.

## Recommended layout

```text
~/.config/easybar/widgets/
├── clock.lua
├── github.lua
├── integrations/
│   └── github/
│       ├── README.md
│       └── widget.lua
├── shared/
│   ├── inbox.lua
│   ├── retry.lua
│   ├── text.lua
│   └── status/
│       └── init.lua
└── assets/
    └── github.svg
```

Only regular `*.lua` files directly inside the widgets directory are started as widgets. Lua files
below `integrations/`, `shared/`, or legacy `lib/` run only when a widget requires them.

Keep small, self-contained examples as top-level files. For a larger integration, use a thin
entrypoint and pass its widget-scoped API to the implementation:

```lua
-- github.lua
require("github.widget")(easybar)
```

```lua
-- integrations/github/widget.lua
---@param easybar EasyBar
return function(easybar)
    -- Complete GitHub widget implementation.
end
```

This preserves top-level discovery and source identity while keeping implementation code and its
README together.

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

Use it from any top-level widget:

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

The repository's example widgets include a small text module:

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

The bundled inbox publishers share `shared/inbox.lua` for three data-boundary operations:

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
  `inbox.maximum_error_length` characters, using the fallback when output is empty. The bundled
  value is 12,000 characters, safely below the native inbox body's byte limit even for UTF-8 text.
- `inbox.timestamp(value)` converts an ISO-8601 timestamp with `Z` or a numeric timezone offset to
  Unix seconds. Fractional seconds are accepted and discarded. Invalid dates and timestamps
  without a timezone return `nil`.

These helpers deliberately do not own snapshots, refresh scheduling, or actions. The publishing
widget remains responsible for validating service-specific fields and deciding whether a failed
refresh should retain existing items.

The bundled `retry.lua` module coordinates asynchronous attempts through `easybar.after(...)`. Pass
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

User modules are loaded by Lua's standard module system, not as widget entrypoints. They do not get
a widget-scoped `easybar` value injected automatically.

Keep general modules independent from EasyBar when possible. When a helper needs host-specific data,
pass the value explicitly:

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

Resolve widget-relative files such as images in the widget itself with `easybar.asset(...)`, then
pass the resolved path to a helper only when needed.

## Naming and precedence

EasyBar searches widget modules in this order:

```text
<widgets_dir>/integrations/?.lua
<widgets_dir>/integrations/?/init.lua
<widgets_dir>/shared/?.lua
<widgets_dir>/shared/?/init.lua
<widgets_dir>/lib/?.lua
<widgets_dir>/lib/?/init.lua
```

Dots map to subdirectories within each root. For example, `require("brew.policy")` resolves first
to `integrations/brew/policy.lua`, then to `shared/brew/policy.lua`, and finally to the legacy
`lib/brew/policy.lua` fallback.

Use the service name as the first component for integration modules. Keep generic module names in
`shared/`, and avoid names likely to collide with third-party Lua packages.

## Errors

A missing or failing required module makes that widget fail during startup and writes the normal Lua
loader error to the EasyBar log. Other widget files continue loading.

A broken module that is never required is not executed.

