# Widget Settings

The `[widgets]` section belongs to Lua widgets. Each widget uses its own named table and can define the keys it needs:

```toml
[widgets.github-inbox]
merge_method = "squash"
confirm_merge = false
```

EasyBar treats all sections below `[widgets]` as valid free-form configuration. Other EasyBar settings cannot be placed there, and widget storage cannot write outside this reserved namespace.

Lua code reads and updates these values through `easybar.storage`:

```lua
local method = easybar.storage.get("github-inbox", "merge_method", "squash")
local ok, err = easybar.storage.set("github-inbox", "merge_method", "rebase")
```

See [Widget Settings for Lua](../lua/guides/storage.md) for supported value types, return values, and validation rules.
