# Lua Runtime Logging

Lua logs go to stderr.

Only the structured runtime protocol moved to the dedicated Lua socket.

## Structured format

```text
EASYBAR_LUA_LOG\t<level>\t<context>\tmessage
```

## Public Lua log levels

Valid public Lua log levels are:

- `easybar.level.trace`
- `easybar.level.debug`
- `easybar.level.info`
- `easybar.level.warn`
- `easybar.level.error`

These resolve to the lowercase scripting values used by `easybar.log(...)`.

## Examples

```lua
easybar.log(easybar.level.info, "refreshing widget")
easybar.log(easybar.level.debug, "current value", 42)
easybar.log(easybar.level.trace, "raw payload", payload)
```

## Prefixed widget logs

`easybar.log.with_prefix(prefix)` returns a widget-local callable logger that prepends the prefix before forwarding to the normal host logger. It does not mutate global logging state for the widget file.

```lua
local log = easybar.log.with_prefix("[brew_outdated]")
log(easybar.level.debug, "checking outdated packages")
```

## File-backed widget logs

`easybar.log.with_file(file_name, options?)` returns a widget-local logger that remains callable like `easybar.log(...)` and can also append raw text to a widget log file.

Widget log files are constrained to the configured EasyBar log directory and accept only plain file names. This keeps the Lua API useful for long-running command widgets without exposing arbitrary file-writing paths.

Example:

```lua
local log = easybar.log.with_file("brew-widget.log", {
    prefix = "[brew_outdated]",
})

log(easybar.level.debug, "update started")
log.append(output)
local tail = log.tail(80)
```

`LuaLogBridge.swift` is the translation boundary that maps Lua log levels into the Swift host logger.
Runtime messages receive `component=runtime`; widget messages receive a stable `widget=<file-name>`
field derived from the widget entrypoint rather than the complete filesystem path.

The host keeps one trace line per protocol direction. Higher layers log semantic events such as event
dispatch, command start and completion, refresh lifecycle, retries, and inbox publication instead of
repeating every socket boundary.

That means:

- Lua widgets should log using the public Lua API values.
- Widget messages should describe operations and outcomes, not transport byte movement.
- Swift remains the canonical implementation of filtering and output behavior.
