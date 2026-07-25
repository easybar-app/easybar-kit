# Logging

Lua widgets can write structured logs through `easybar.log(...)`.

Use the exported log level constants:

- `easybar.level.trace`
- `easybar.level.debug`
- `easybar.level.info`
- `easybar.level.warn`
- `easybar.level.error`

## Example

```lua
easybar.log(easybar.level.info, "refreshing widget")
easybar.log(easybar.level.debug, "current value", 42)
easybar.log(easybar.level.trace, "raw payload", payload)
```

## Prefixed widget logs

For widgets that repeatedly use the same grep-friendly prefix, create a prefixed logger once:

```lua
local log = easybar.log.with_prefix("[brew_outdated]")

log(easybar.level.debug, "checking outdated packages")
log(easybar.level.warn, "brew update failed", "code=" .. tostring(code))
```

This is equivalent to calling `easybar.log(...)` with the prefix as the first message part, but avoids repeating it at every call site.

## File-backed widget logs

For widgets that need a separate operation log, create a file-backed logger once:

```lua
local log = easybar.log.with_file("brew-widget.log", {
    prefix = "[brew_outdated]",
})
```

The returned logger is callable, so it keeps the same style as `easybar.log(...)`:

```lua
log(easybar.level.debug, "checking outdated packages")
```

It writes to the normal EasyBar host log and appends a line to the widget log file. The file is always created inside `easybar.log_dir`; pass only a plain file name, not a path.

Use `append`, `tail`, and `trim` for command output logs:

```lua
log.append("$ brew update")
log.append(output)
local recent = log.tail(80)
log.trim(4000)
```

`append` is useful for raw command output. `tail` is useful for showing recent failure context in a popup. `trim` keeps long-running widget logs bounded.

## Widget context

EasyBar automatically attaches the widget file name to host log entries. A call from
`github-inbox.lua` is therefore rendered with `widget=github-inbox`; widgets do not need to repeat
their own name in every message.

Prefer compact `key=value` context for operations that span multiple callbacks:

```lua
local log = easybar.log
log(easybar.level.debug, "inbox refresh started reason=manual")
log(easybar.level.trace, "inbox retry scheduled attempt=1 delay_seconds=2")
log(easybar.level.info, "inbox mutation completed operation=mark_read")
```

Avoid logging raw API payloads, credentials, private titles, or complete command output. Put long
command output in a bounded file-backed log only when the widget explicitly needs it.

## Host filtering

The configured host level controls normal console output and retained `easybar.out` records:

- `logging.level = "info"` emits info, warnings, and errors
- `logging.level = "debug"` also emits debug logs
- `logging.level = "trace"` also emits trace logs

A live CLI subscription can request a more verbose level without changing that persistent setting:

```bash
easybar logs --widget brew-inbox --runtime lua --level trace --follow
```

With `logging.level = "info"`, matching trace records are delivered only to the connected CLI and are not appended to `easybar.out`.

## Recommended usage

Use:

- `trace` for retry decisions, protocol diagnostics, and detailed scheduling state
- `debug` for refresh starts, action routing, snapshot counts, and successful read-only completion
- `info` for explicit user-triggered mutations, cancellation, and mutation completion
- `warn` for exhausted retries, invalid responses, and recoverable failures
- `error` for failed mutations or failures that prevent the widget from working
