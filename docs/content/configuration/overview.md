# Configuration Overview

EasyBar starts with built-in defaults even when no custom config file exists. The default bar enables spaces, battery, Wi-Fi, and calendar.

Lua-owned values live in the free-form `[widgets.<name>]` namespace. See [Widget Settings](widget-settings.md) for the config format and storage API.

When present, EasyBar reads runtime config from:

```text
~/.config/easybar/config.toml
```

You can override that path with:

```bash
EASYBAR_CONFIG_PATH=/path/to/config.toml
```

For a first setup, start with [Quick Start](../getting-started/quick-start.md). Create `config.toml` only when you want to customize the defaults.

## Example files

The repository ships two config examples:

- `config.defaults.toml`
  Full reference file with current defaults, inline comments, and all supported sections.
- `config.minimal.toml`
  Small optional starter override that groups common built-ins and enables Wi-Fi details.

Use `config.minimal.toml` when you want a compact customization starting point. Use `config.defaults.toml` when you need to discover every supported key.

The generated [Configuration Reference](reference.md) mirrors `config.defaults.toml`. It is useful for exact defaults, but the hand-written pages are better for concepts and examples.

## What belongs in config

Use `config.toml` for stable user-facing behavior:

- app paths, runtime directory, and reload behavior
- environment variables visible to Lua widgets
- selected theme and theme overrides
- logging settings
- helper-agent sockets and behavior
- bar height and bar colors
- native built-in widgets
- native built-in groups

Use Lua only when you need custom logic that config cannot express. The decision guide is [Built-ins Vs Lua](../getting-started/builtins-vs-lua.md).

## Important sections

- `[app]`
  App-level paths, the shared runtime directory, and runtime behavior.
- `[app.env]`
  Environment variables visible to Lua widgets and widget shell commands.
- `[app.lua_commands]`
  Default command limits for Lua command execution.
- `[theme]`
  Selected theme name and custom theme directory.
- `[theme.colors]`
  Optional theme color token overrides.
- `[logging]`
  Shared logging config for EasyBar and helper agents.
- `[agents.calendar]`
  Calendar helper agent settings.
- `[agents.network]`
  Network helper agent settings.
- `[bar]`
  Bar height, padding, and top-edge behavior.
- `[bar.colors]`
  Bar background and border colors.
- `[builtins.*]`
  Native built-in widget configuration.
- `[builtins.groups.*]`
  Native widget groups.

## Theme and override model

Themes provide shared visual defaults.

Explicit config values still win.

The practical order is:

```text
built-in app defaults
→ selected theme
→ [theme.colors] overrides
→ explicit [bar] and [builtins.*] values
→ Lua widget props
```

That means a theme can set the default palette, while a specific widget can still use exact colors.

Example:

```toml
[theme]
name = "default"
themes_dir = "~/.config/easybar/themes"

[theme.colors]
accent = "#8aadf4"

[bar.colors]
background = "#090909"
```

See [Themes](themes.md).

## Where to go next

| Goal                                | Page                                    |
| ----------------------------------- | --------------------------------------- |
| Copy a starter config               | [Example Configs](example-configs.md)   |
| Configure app paths                 | [App Settings](app.md)                  |
| Configure shell command environment | [Environment](environment.md)           |
| Choose colors                       | [Themes](themes.md)                     |
| Configure native widgets            | [Built-ins](builtins.md)                |
| Configure spaces behavior           | [Spaces](builtins/spaces.md)            |
| Configure the shared inbox          | [Inbox](builtins/inbox.md)              |
| Configure Wi-Fi details             | [Wi-Fi](builtins/wifi.md)               |
| Configure calendar behavior         | [Calendar](builtins/calendar.md)        |
| Group native widgets                | [Native Groups](native-groups.md)       |
| Configure helper agents             | [Agents](agents.md)                     |
| Debug logging                       | [Logging](logging.md)                   |
| Check exact defaults                | [Configuration Reference](reference.md) |
| Control the running app             | [CLI Reference](../runtime/cli.md)      |
