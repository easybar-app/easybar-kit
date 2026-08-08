# App Settings

The `[app]` section controls core EasyBar runtime behavior.

Example:

```toml
[app]
show_menu_bar_icon = true
widgets_dir = "~/.config/easybar/widgets"
lua_path = "lua"
runtime_dir = "~/.local/state/easybar/runtime"
watch_config = true
widget_editor_stub_path = "~/.local/share/easybar/easybar_api.lua"
develop = false
```

## `show_menu_bar_icon`

Controls the persistent EasyBar controller icon in the macOS menu bar.

```toml
[app]
show_menu_bar_icon = true
```

The icon is enabled by default and provides runtime controls even while the EasyBar bar is stopped. Set it to `false` when you do not want the additional menu bar item.

See [Runtime Control](../runtime/control.md#menu-bar-controller) for the available actions and recovery behavior.

## `widgets_dir`

The directory where EasyBar loads manually managed Lua widget files from.

```toml
[app]
widgets_dir = "~/.config/easybar/widgets"
```

EasyBar recursively loads every regular file below this directory with a `.lua` extension. Extension matching is case-insensitive. Discovery does not depend on a category name or a filename such as `widget.lua`. Lua files used as reusable modules are also executed during startup, so keep module top levels side-effect-free and start runtime behavior only from explicit functions.

Packages installed with `easybar widgets install` are kept separately below `~/.local/share/easybar/packages` and loaded automatically. Changing `widgets_dir` affects only your manual widgets; it does not relocate installed packages.

If you are creating your first custom widget, continue with [First Widget](../lua/guides/first-widget.md). For shared helper code, see [Reusable Modules](../lua/guides/modules.md).

## `lua_path`

The Lua executable used for the Lua widget runtime.

```toml
[app]
lua_path = "lua"
```

The default value `lua` is resolved through `PATH`. Use an absolute path only when you want to pin a specific Lua installation.

## `runtime_dir`

The base directory for EasyBar's runtime sockets and lock files.

```toml
[app]
runtime_dir = "~/.local/state/easybar/runtime"
```

By default, EasyBar derives these paths from `runtime_dir`:

```text
easybar.sock
lua-runtime.sock
calendar-agent.sock
network-agent.sock
```

The main-app lock directory also defaults to `runtime_dir`.

`EASYBAR_RUNTIME_DIR` is a real environment override for this setting. It takes precedence over `app.runtime_dir`.

## `lua_socket_path`

Optional dedicated Unix socket override for communication between the main app and the Lua widget runtime.

```toml
[app]
lua_socket_path = "/custom/runtime/lua-runtime.sock"
```

When omitted, EasyBar uses `lua-runtime.sock` inside `runtime_dir`.

See [Runtime Control](../runtime/control.md) and [Lua Runtime Overview](../internals/lua-runtime/overview.md).

## `watch_config`

Controls whether EasyBar watches `config.toml` and reloads automatically when the file changes.

```toml
[app]
watch_config = true
```

When this is `false`, update the running app manually after config edits:

```bash
easybar config reload
```

## `lock_dir`

Optional override for the directory used by EasyBar runtime lock files.

```toml
[app]
lock_dir = "/custom/runtime/locks"
```

When omitted, the lock directory is `runtime_dir`. The lock is part of the single-instance guard that prevents multiple EasyBar app processes from drawing duplicate bars.

## `widget_editor_stub_path`

Path where EasyBar keeps the combined LuaLS/editor stub in sync for widget authoring.

```toml
[app]
widget_editor_stub_path = "~/.local/share/easybar/easybar_api.lua"
```

Point your Lua language server workspace at this file to get autocomplete and diagnostics for the public EasyBar Lua API.

See [Editor Support](../lua/guides/editor-support.md).

## `develop`

The hidden developer menu section can be shown without holding `Shift` with:

```toml
[app]
develop = true
```

By default, the developer section is hidden unless you hold `Shift` and right-click the bar.

See [Developer Menu](developer-menu.md).

## `lua_commands`

Command execution limits for `easybar.exec(...)` and `easybar.exec_async(...)`.

```toml
[app.lua_commands]
timeout_seconds = 5
max_output_bytes = 65536
max_async_jobs = 8
```

- `timeout_seconds`: default hard timeout for one command before EasyBar terminates it. Widgets can override this per `easybar.exec(...)` or `easybar.exec_async(...)` call.
- `max_output_bytes`: default maximum combined stdout and stderr captured for one command. Widgets can override this per call.
- `max_async_jobs`: maximum concurrent `easybar.exec_async(...)` jobs before new jobs are rejected.
