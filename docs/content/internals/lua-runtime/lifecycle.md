# Lua Runtime Lifecycle

The Lua runtime has three main lifecycle paths:

- start
- shutdown
- reload

## Start

Swift entry:

- `AppController.swift`
  hands off runtime startup to `RuntimeCoordinator.shared.start()`

Runner flow:

- `RuntimeCoordinator.swift`
  starts the widget engine as part of runtime startup
- `WidgetEngine.swift`
  registers for Lua transport lines
- `LuaRuntime.swift`
  starts the launcher, opens the Lua socket listener, and attaches transport
- `LuaProcessController.swift`
  launches the Lua launcher with:
  - configured Lua socket path
  - bundled `runtime.lua`
  - configured widget directory

Important detail:

- Lua runs in its own process group
- shutdown kills the entire group

This prevents orphaned processes.

## Shutdown

Shutdown path:

- `RuntimeCoordinator.stop()`
- `WidgetEngine.shutdown()`
- `EventManager.stopLuaSubscriptions()`
- `LuaRuntime.shutdown()`
- `LuaTransport.shutdown()`
- `LuaProcessController.shutdown()`

This:

- removes observers
- stops handlers
- closes the Lua socket
- terminates the process group

## Reload

Reload is always a full restart:

1. stop runtime
2. clear state
3. start again

This guarantees:

- no stale widget state
- no dangling subscriptions
- deterministic behavior

## Refresh behavior

Three different concepts matter.

### Normal runtime events

Examples:

- `wifi_change`
- `network_change`
- `minute_tick`
- `mouse.clicked`
- `context_menu.clicked`

### Manual refresh

Triggered via:

```bash
easybar refresh
```

This:

- keeps current config
- pulls fresh data
- emits refresh events
- does not restart Lua

### Lua runtime restart

Triggered via:

```bash
easybar runtime restart
```

This:

- fully restarts Lua
- resets all widget state

### Config reload

```bash
easybar config reload
```

This:

- reloads config file
- rebuilds runtime state
