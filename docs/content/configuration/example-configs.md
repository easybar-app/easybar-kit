# Example Configs

EasyBar does not require a custom config file for first launch. The built-in defaults already enable spaces, battery, Wi-Fi, and calendar.

The repository includes two config examples for customization:

- `config.defaults.toml`
- `config.minimal.toml`

## `config.defaults.toml`

Use this when you want the complete reference file with current defaults and supported sections.

It is useful for:

- discovering all available keys
- checking default values
- seeing all supported built-ins
- checking theme configuration
- comparing your local config against the project defaults

The defaults file includes the default theme section:

```toml
[theme]
name = "default"
themes_dir = "~/.config/easybar/themes"
```

## `config.minimal.toml`

Use this when you want a smaller customization starting point.

It keeps the default built-ins enabled and adds a compact setup for common tweaks:

- one native `system` group
- battery inside the `system` group
- Wi-Fi inside the `system` group
- Wi-Fi details mode with SSID enabled

It intentionally omits theme settings and uses the app defaults. Add a `[theme]` section only when you want to select a different bundled or custom theme.

Example optional theme override:

```toml
[theme]
name = "default"
themes_dir = "~/.config/easybar/themes"
```

## Copy a starter config

From a cloned repository:

```bash
mkdir -p ~/.config/easybar
cp config.minimal.toml ~/.config/easybar/config.toml
```

Then reload EasyBar:

```bash
easybar config reload
```

## Add a custom theme

Create a custom theme directory:

```bash
mkdir -p ~/.config/easybar/themes
```

Add a custom theme file:

```text
~/.config/easybar/themes/my-theme.toml
```

Then select it in `config.toml`:

```toml
[theme]
name = "my-theme"
themes_dir = "~/.config/easybar/themes"
```

See [Themes](themes.md) for the theme file format.
