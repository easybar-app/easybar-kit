# Built-ins

EasyBar supports native built-in widgets in `config.toml`.

Built-ins are configured under `[builtins.*]`.

If you are deciding whether to use a built-in or write a Lua widget, start with [Built-ins Vs Lua](../getting-started/builtins-vs-lua.md).

Example:

```toml
[builtins.spaces]
enabled = true

[builtins.battery]
enabled = true

[builtins.wifi]
enabled = true

[builtins.calendar]
enabled = true
```

## Theme defaults

Built-ins receive visual defaults from the selected theme.

For example, a theme can provide default colors for:

- text
- surfaces
- borders
- status colors
- popup backgrounds
- active and inactive states

Explicit built-in config still wins.

Example:

```toml
[theme]
name = "default"

[builtins.time.style]
text_color = "#ffffff"
background_color = "#090909"
```

Here the time widget uses the explicit colors instead of the theme defaults.

See [Themes](themes.md).

## Groups

Built-ins can be attached to native groups:

```toml
[builtins.groups.system]
position = "right"
order = 40

[builtins.groups.system.style]

[builtins.battery]
enabled = true
group = "system"

[builtins.wifi]
enabled = true
group = "system"
```

See [Native Groups](native-groups.md).

## Box model

Built-in widgets and native groups share common layout keys:

- `margin_x`
- `margin_y`
- `padding_x`
- `padding_y`
- `spacing`

See [Box Model](box-model.md).

## Detailed guides

The generated [Configuration Reference](reference.md) lists every key and default. These guides explain behavior and interactions for the more complex built-ins:

| Built-in       | Guide                                        |
| -------------- | -------------------------------------------- |
| Spaces         | [Spaces](builtins/spaces.md)                 |
| Inbox          | [Inbox](builtins/inbox.md)                   |
| Privacy Spacer | [Privacy Spacer](builtins/privacy-spacer.md) |
| Wi-Fi          | [Wi-Fi](builtins/wifi.md)                    |
| Calendar       | [Calendar](builtins/calendar.md)             |

## Widget-specific context menus

Interactive built-ins expose their common settings and native actions directly from the bar:

| Built-in       | Context-menu controls                                                                                                                                                        |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Battery        | Display mode, color mode, and refresh.                                                                                                                                       |
| Volume         | Mute or unmute, percentage visibility, hover-slider expansion, and Sound settings. Unsupported device controls are disabled and a non-writable output is rendered read-only. |
| CPU            | Activity Monitor, history size, refresh interval, and history reset. Custom TOML values remain visible as checked, read-only menu entries.                                   |
| Front App      | Hide the focused app, show or hide its icon and name, and show an existing app bundle in Finder. Unavailable actions are disabled.                                           |
| AeroSpace Mode | Change the focused layout, show or hide icon and text, open the active AeroSpace config, and refresh AeroSpace state.                                                        |
| Wi-Fi          | Content mode, visible fields, refresh, and Network settings.                                                                                                                 |
| Calendar       | Popup mode, anchor layout and fields, appointment details, refresh, and Calendar privacy settings.                                                                           |
| Inbox          | Grouping, sorting, unread and empty-state behavior, and publisher actions.                                                                                                   |

Configuration choices are written to `config.toml` immediately. Comments, whitespace, and unrelated
settings are preserved. Runtime actions such as muting audio, hiding an app, resetting CPU history,
or changing an AeroSpace layout do not alter the EasyBar configuration. Failed system actions are logged instead of silently ignored.

## Enable or disable widgets from the bar

Open **Native Widgets** from the menu bar icon or by right-clicking an empty area of the bar to
enable or disable any top-level built-in widget. Checked items are enabled. Each selection
immediately updates the corresponding `builtins.<widget>.enabled` value in `config.toml` and reloads
the bar, while preserving comments, whitespace, and unrelated settings.

Every visible native widget also has a right-click context menu with **Reload Widget** and
**Disable Widget**. Disabling is written to the active config file immediately; use **Native
Widgets** from the bar or controller menu to enable it again. Widgets with interactive settings add
their own controls above these common actions.

## When to switch to Lua

Stay with built-ins when the widget already exists and you mainly need native placement, grouping, theming, or styling.

Switch to Lua when you need:

- custom formatting or composed content
- custom mouse behavior
- popup content driven by your own data
- shell-command integration or app-specific logic

See [Lua Widgets](../lua/overview.md).
