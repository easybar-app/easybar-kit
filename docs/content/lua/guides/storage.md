# Widget Settings

Lua widgets can keep user-configurable settings in `config.toml`. Every setting is stored below the reserved `widgets` namespace:

```toml
[widgets.github-inbox]
merge_method = "squash"
confirm_merge = false
```

Read a setting with a fallback value:

```lua
local merge_method = easybar.storage.get("github-inbox", "merge_method", "squash")
```

Persist a new value with:

```lua
local ok, err = easybar.storage.set("github-inbox", "merge_method", "rebase")
if not ok then
    easybar.log(easybar.level.error, err)
end
```

`get(...)` returns the stored value when present. If the key is absent, it returns the optional default argument, or `nil` when no default was provided. A read error raises a Lua error so a widget does not silently continue with corrupted or unreadable configuration.

`set(...)` returns `true` after the value is stored. On failure it returns `false` plus an error message. Writing a changed value causes the normal configuration reload when config watching is enabled; writing the current value again is a no-op.

## Supported values

Storage accepts values that map directly to TOML:

- strings
- booleans
- finite numbers
- arrays containing only strings

Tables, functions, `nil`, mixed arrays, and nested values are not supported. Use separate keys for separate settings.

Widget namespaces and keys may contain letters, numbers, underscores, and hyphens. EasyBar always builds the full path itself as `widgets.<widget>.<key>`; Lua code cannot use this API to write another top-level config section.

The entire `[widgets]` tree is intentionally free-form. `easybar config validate` does not report widget-owned keys as unknown configuration.
