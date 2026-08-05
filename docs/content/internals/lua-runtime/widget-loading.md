# Widget Loading

Bootstrap begins in `runtime.lua`.

## Discovery

The Swift host resolves the configured widgets directory and passes only that directory to the Lua runtime. It does not enumerate files or assign meaning to any filename. After startup, `api.lua` recursively discovers every regular file with a `.lua` extension. Extension matching is case-insensitive, and discovery does not depend on directory names or an entrypoint filename:

```text
<widgets_dir>/**/*.lua
```

No widget-file list crosses the process boundary. A file can live at the root, in a category directory, in a service directory, or at any deeper path. Because every Lua file is executed during startup, reusable modules should keep their top level side-effect-free. A module that only defines values and returns a table or function is safe to execute directly and can still be loaded through `require(...)`.

## Flow

1. Swift resolves `widgets_dir` and launches `EasyBarLuaRuntime` with fixed runtime arguments
2. the runtime agent forwards `widgets_dir` to `runtime.lua`
3. `api.lua` recursively discovers every regular file with a `.lua` extension
4. `api.lua` sorts the relative paths for deterministic startup
5. `loader.lua` transactionally executes each discovered file

Before `loader.lua` executes the discovered files, it prepends these user-module paths to Lua's standard module search path in this order:

```text
<widgets_dir>/?.lua
<widgets_dir>/?/init.lua
<widgets_dir>/shared/?.lua
<widgets_dir>/shared/?/init.lua
<widgets_dir>/lib/?.lua
<widgets_dir>/lib/?/init.lua
```

Service modules take precedence over generic shared modules, which take precedence over the legacy `lib/` fallback. For example, `require("brew.policy")` resolves `<widgets_dir>/brew/policy.lua`.

Inside `loader.lua`:

1. configure root, shared, and legacy module paths
2. create an isolated environment for each discovered file
3. inject a scoped `easybar` API with both the source directory and widgets root
4. execute the file transactionally

## Source identities

Logs and command diagnostics use the file's path relative to the configured widgets directory, without the `.lua` extension:

```text
brew/widget.lua         -> brew/widget
inbox/github/widget.lua -> inbox/github/widget
shared/text.lua         -> shared/text
```

This rule is generic, preserves directory context, and does not assign special meaning to `widget.lua`.

## Asset roots

`easybar.asset("icon.svg")` resolves from the current file's directory. `easybar.asset("@/assets/icon.svg")` resolves from the configured widgets root. Both forms reject absolute paths and attempts to escape their selected root.

## Important details

- every regular file below `widgets_dir` with a `.lua` extension is executed
- each file receives isolated widget defaults and local variables
- all files share one runtime registry
- module files may also be loaded through `require(...)`
- required modules use Lua's process-wide `package.loaded` cache
- reload is a full reset
- widget environments fall back to `_G`, so isolation is about local state, not security

A module may therefore run once as a discovered source file and once through `require(...)`. Keep module top levels declarative and avoid starting timers, commands, or subscriptions outside an explicit function called by a widget.

## Trust model

EasyBar widget files are trusted local scripts. The per-file environment prevents ordinary local variables and defaults from leaking into other files, but it falls back to `_G`. This is not a sandbox; do not treat third-party Lua files as untrusted code.

## Public widget API shape

Lua widget authors use node handles. `easybar.add(...)` creates one node and returns its handle:

```lua
local clock = easybar.add(easybar.kind.item, "clock", {
    position = "right",
    order = 10,
    label = os.date("%H:%M"),
})
```

The returned handle owns node operations:

- `node.id`
- `node.name`
- `node:set(props)`
- `node:get()`
- `node:remove()`
- `node:subscribe(events, handler)`

Internally, `api.lua` delegates those operations to the registry and subscription modules by id. The id-based functions remain internal implementation details.
