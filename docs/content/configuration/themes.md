# Themes

EasyBar supports file-based themes.

A theme is a TOML file that defines shared color tokens. Those tokens are used as visual defaults for the bar, native built-ins, popups, and other themed surfaces.

Themes control appearance only. Layout, ordering, grouping, enabled state, formats, filters, and behavior stay in `config.toml`.

## Configure a theme

Select a theme in `config.toml`:

```toml
[theme]
name = "default"
themes_dir = "~/.config/easybar/themes"
```

`name` is the theme file name without `.toml`.

Examples:

```text
default -> default.toml
tokyo-night -> tokyo-night.toml
my-theme -> my-theme.toml
```

`themes_dir` is the custom theme directory.

## Switch themes from the menus

You can switch themes live from either EasyBar menu:

```text
right-click the bar -> Theme -> <theme name>
menu bar icon      -> Theme -> <theme name>
```

Selecting a theme immediately updates `theme.name` in `config.toml` and reloads EasyBar. Comments,
whitespace, and unrelated settings are preserved.

The menus list themes bundled with EasyBar and `.toml` themes found in the configured `themes_dir`.

## Lookup order

EasyBar resolves themes in this order:

```text
1. user theme: themes_dir/<name>.toml
2. bundled theme: EasyBar.app/Contents/Resources/Themes/<name>.toml
3. error if the theme does not exist
```

A user theme overrides a bundled theme with the same name.

Example:

```text
~/.config/easybar/themes/default.toml
```

wins over the bundled `default.toml`.

## Default theme

The default bundled theme is:

```toml
[theme]
name = "default"
```

This resolves to:

```text
default.toml
```

The complete default config also uses this theme name.

## Bundled themes

EasyBar includes these themes:

- `default`
- `dracula`
- `everforest-dark`
- `frappe`
- `gruvbox-dark`
- `latte`
- `macchiato`
- `mocha`
- `nord`
- `rose-pine`
- `solarized-dark`
- `tokyo-night`

Bundled themes are included with the app and do not need to be copied into `themes_dir`. To
customize one, create a theme with the same name in `themes_dir`; the custom file takes precedence.

## Custom themes

Create a custom theme in your configured `themes_dir`:

```bash
mkdir -p ~/.config/easybar/themes
$EDITOR ~/.config/easybar/themes/my-theme.toml
```

Then select it:

```toml
[theme]
name = "my-theme"
themes_dir = "~/.config/easybar/themes"
```

Reload EasyBar:

```bash
easybar config reload
```

## Theme file format

```toml
[colors]
background = "#111111"
surface = "#1a1a1a"
surface_elevated = "#2b2b2b"
surface_hover = "#202020"
text = "#ffffff"
text_secondary = "#d0d0d0"
text_tertiary = "#c0c0c0"
muted = "#6c7086"
muted_secondary = "#8a8a8a"
outside_month = "#6e738d"
accent = "#91d7e3"
accent_secondary = "#89B4FA"
accent_soft = "#8bd5ca"
success = "#a6e3a1"
success_secondary = "#a6da95"
warning = "#f9e2af"
orange = "#fab387"
error = "#f38ba8"
danger = "#FF0000"
border = "#333333"
border_strong = "#444444"
border_subtle = "#00000000"
selection_text = "#0B1020"
selection_background = "#89B4FA"
transparent = "#00000000"
overlay_outline = "#000000F0"
overlay_text = "#FFFFFFFF"
```

## Required color tokens

Every complete theme should define the full semantic palette:

| Token                  | Purpose                                             |
| ---------------------- | --------------------------------------------------- |
| `background`           | Main bar and popup background.                      |
| `surface`              | Normal widget or inactive surface background.       |
| `surface_elevated`     | Focused, active, or raised surface background.      |
| `surface_hover`        | Hover or highlighted surface background.            |
| `text`                 | Primary text color.                                 |
| `text_secondary`       | Secondary body or label text color.                 |
| `text_tertiary`        | Tertiary text color for quieter labels.             |
| `muted`                | Secondary, inactive, or unavailable text color.     |
| `muted_secondary`      | Secondary muted tone for softer supporting content. |
| `outside_month`        | Calendar text color for days outside the month.     |
| `accent`               | Accent color for highlights and secondary details.  |
| `accent_secondary`     | Secondary accent for supporting highlights.         |
| `accent_soft`          | Softer accent for subtle emphasis.                  |
| `success`              | Positive or healthy status color.                   |
| `success_secondary`    | Secondary positive color for supporting signals.    |
| `warning`              | Warning status color.                               |
| `orange`               | Orange status color for low or degraded states.     |
| `error`                | Error or critical status color.                     |
| `danger`               | Strong danger color for urgent attention.           |
| `border`               | Normal border color.                                |
| `border_strong`        | Emphasized border color.                            |
| `border_subtle`        | Subtle or transparent border color.                 |
| `selection_text`       | Text color drawn on selected surfaces.              |
| `selection_background` | Background color used for selected surfaces.        |
| `transparent`          | Fully transparent color, usually `#00000000`.       |
| `overlay_outline`      | Overlay outline color with alpha.                   |
| `overlay_text`         | High-contrast overlay glyph or text color.          |

## Color references

Config color fields can reference theme tokens:

```toml
[bar.colors]
background = "theme.background"
border = "theme.transparent"

[builtins.time.style]
text_color = "theme.text"
background_color = "theme.surface"
border_color = "theme.border"
```

Theme references use this form:

```text
theme.<token>
```

Examples:

```text
theme.background
theme.surface
theme.surface_elevated
theme.surface_hover
theme.text
theme.text_secondary
theme.text_tertiary
theme.muted
theme.muted_secondary
theme.outside_month
theme.accent
theme.accent_secondary
theme.accent_soft
theme.success
theme.success_secondary
theme.warning
theme.orange
theme.error
theme.danger
theme.border
theme.border_strong
theme.border_subtle
theme.selection_text
theme.selection_background
theme.transparent
theme.overlay_outline
theme.overlay_text
```

Plain hex colors still work everywhere.

## Lua widgets

Lua widgets receive the active theme through `easybar.theme`.

Use resolved colors when the widget should render a concrete hex value:

```lua
easybar.add(easybar.kind.item, "clock", {
    label = {
        string = os.date("%H:%M"),
        color = easybar.theme.colors.text,
    },
})
```

Use theme references when a node color field should stay tied to the current theme:

```lua
easybar.add(easybar.kind.item, "clock", {
    color = easybar.theme.ref.text,
    background = {
        color = easybar.theme.ref.surface,
    },
})
```

`easybar.theme.ref.<token>` always mirrors the supported theme token names.

## Override theme colors

You can override individual theme tokens in `config.toml`:

```toml
[theme]
name = "default"

[theme.colors]
accent = "#8aadf4"
error = "#ff6b6b"
```

This keeps the selected theme and changes only the listed tokens.

## Override widget colors

Explicit widget config always wins over theme defaults.

```toml
[theme]
name = "default"

[builtins.battery.colors]
critical = "#ff0000"
```

Here the battery critical color uses `#ff0000`, even if the theme has a different `error` color.

## What belongs in a theme

Good theme content:

- shared color tokens
- surface colors
- text colors
- status colors
- border colors

Do not put behavior or layout in theme files:

- `enabled`
- `position`
- `order`
- `group`
- date or time formats
- polling intervals
- calendar filters
- widget-specific behavior

## Troubleshooting

### Theme not found

If you see:

```text
theme 'default' was not found in ~/.config/easybar/themes or bundled themes
```

For a custom theme, check that the file exists in `themes_dir`:

```text
~/.config/easybar/themes/default.toml
```

For a bundled theme, check that `name` matches one of the names in
[Bundled themes](#bundled-themes). If a bundled theme is missing from an installed app, reinstall or
upgrade EasyBar.

### Theme changes do not apply

Reload config:

```bash
easybar config reload
```

If `watch_config = false`, EasyBar will not reload automatically.

### A widget ignores the theme

Check whether that widget has an explicit color in `config.toml`.

Explicit widget colors override theme defaults.
