# Editor Support

EasyBar installs a bundled LuaLS stub into:

```text
~/.local/share/easybar/easybar_api.lua
```

That installed file is the combined public stub.

## LuaLS workspace setup

If your editor uses LuaLS, add a `.luarc.json` in the workspace where you edit widgets.

That gives you:

- no `unknown global 'easybar'` warning
- hover documentation
- autocomplete for the `easybar` API
- named command callbacks, command status values, async tokens, and timer handles
- diagnostics and autocomplete for supported node properties such as `background.border_width`, `popup.drawing`, `interval`, and `on_interval`

Suggested setup:

1. start EasyBar once so it installs `~/.local/share/easybar/easybar_api.lua`
2. add `~/.config/easybar/widgets/.luarc.json`
3. open `~/.config/easybar/widgets` or `~/.config` as your editor workspace

Example `.luarc.json`:

```json
{
  "$schema": "https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json",
  "runtime": {
    "version": "Lua 5.5",
    "path": [
      "?.lua",
      "?/init.lua",
      "shared/?.lua",
      "shared/?/init.lua",
      "lib/?.lua",
      "lib/?/init.lua"
    ]
  },
  "workspace": {
    "library": ["~/.local/share/easybar/easybar_api.lua"]
  },
  "diagnostics": {
    "globals": ["easybar"]
  }
}
```

If your editor still only knows about the `easybar` global but not nested property tables, restart EasyBar once so it reinstalls the latest `easybar_api.lua` stub.

## User modules

The `runtime.path` entries above let LuaLS resolve the same widget-local modules that EasyBar
loads from preferred `shared/` and legacy `lib/`. See [Reusable Modules](modules.md) for directory
layout, `require(...)` behavior, and module lifetime.

Keep reusable-module annotations beside the module implementation. For example, the bundled
`shared/retry.lua` declares `RetryOptions` and `RetryOperation` locally, so LuaLS can validate retry
callbacks when the module is required without polluting the global EasyBar API.

