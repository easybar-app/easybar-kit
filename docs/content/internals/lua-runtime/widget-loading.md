# Widget Loading

Bootstrap begins in `runtime.lua`.

## Discovery

The Swift host resolves the configured manual widgets directory and the fixed managed activation directory. It passes the manual path as a runtime argument and the managed path through an internal environment variable. Swift does not enumerate files or assign meaning to filenames. After startup, `api.lua` recursively discovers regular files with a `.lua` extension in each root. Extension matching is case-insensitive:

```text
~/.local/share/easybar/packages/active/**/*.lua
<widgets_dir>/**/*.lua
```

Discovery prunes `shared/` and `lib/`, so support modules load only through `require(...)`. The managed activation tree contains only package entrypoints, package assets, and declared exports; complete versioned source remains in the package store and is not scanned.

## Flow

1. Swift resolves `widgets_dir` and the managed activation path, then launches `EasyBarLuaRuntime`
2. the runtime agent forwards `widgets_dir` to `runtime.lua`, while the managed path is inherited through the environment
3. `api.lua` discovers and sorts activated package entrypoints
4. `loader.lua` transactionally executes the managed entrypoints
5. `api.lua` discovers and sorts manual widget files
6. `loader.lua` transactionally executes the manual files

For each root, `loader.lua` prepends these paths to Lua's standard module search path in this order:

```text
<widgets_dir>/?.lua
<widgets_dir>/?/init.lua
<widgets_dir>/shared/?.lua
<widgets_dir>/shared/?/init.lua
<widgets_dir>/lib/?.lua
<widgets_dir>/lib/?/init.lua
```

Root-local modules take precedence over generic shared modules, which take precedence over the legacy `lib/` fallback. The managed root is configured first. The manual root is configured afterward and therefore has precedence for manual widget startup, while managed exports remain available as a fallback.

Inside `loader.lua`:

1. configure root, shared, and legacy module paths
2. create an isolated environment for each discovered file
3. inject a scoped `easybar` API with both the source directory and widgets root
4. execute the file transactionally

## Source identities

Logs and command diagnostics use the file's path relative to the root from which it was loaded, without the `.lua` extension:

```text
brew/widget.lua         -> brew/widget
inbox/github/widget.lua -> inbox/github/widget
shared/text.lua         -> shared/text
```

This rule is generic, preserves directory context, and does not assign special meaning to `widget.lua`.

## Asset roots

`easybar.asset("icon.svg")` resolves from the current file's directory. `easybar.asset("@/assets/icon.svg")` resolves from the configured widgets root. Both forms reject absolute paths and attempts to escape their selected root.

## Important details

- package entrypoints below the managed activation root load first
- every regular file below `widgets_dir` with a `.lua` extension is executed, except files below `shared/`, `lib/`, and legacy `.easybar/` directories
- each file receives isolated widget defaults and local variables
- all files share one runtime registry
- support modules load through `require(...)` and are not directly discovered
- required modules use Lua's process-wide `package.loaded` cache
- reload is a full reset
- widget environments fall back to `_G`, so isolation is about local state, not security

Keep module top levels declarative and avoid starting timers, commands, or subscriptions outside an explicit function called by a widget.

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
