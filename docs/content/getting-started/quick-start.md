# Quick Start

This is the shortest path from a fresh install to a working EasyBar setup.

EasyBar can start without a custom config. The built-in defaults already show a useful bar with spaces, battery, Wi-Fi, and calendar enabled. Create `config.toml` only when you want to customize the bar.

## 1. Install EasyBar

Add the Homebrew tap and install EasyBar:

```bash
brew tap easybar-app/tap
brew install --cask easybar-app/tap/easybar
```

The cask installs the app and CLI and starts the separately managed calendar and network agent services. [Installation](installation.md) explains the component lifecycle, upgrades, and uninstall behavior.

## 2. Start EasyBar

Open the app from Finder, Spotlight, or the command line:

```bash
open -a EasyBar
```

The agents provide permission-sensitive calendar and network data. macOS asks for Calendar and Location permissions on behalf of the corresponding agent. EasyBar can still start when an agent has no permission, but the related widget may show empty or denied data until access is granted.

EasyBar also shows a controller icon in the macOS menu bar. Use it to stop or restart the bar, reload configuration, restart helper agents, and open EasyBar directories. The icon remains available if you stop only the bar runtime.

## 3. Verify the bar responds

Trigger one refresh through the installed CLI:

```bash
easybar refresh
```

If this fails or the bar does not appear, follow the matching symptom in [Troubleshooting](../runtime/troubleshooting.md). Installation-specific process checks are in [Installation](installation.md).

## 4. Optional: create a custom config

EasyBar reads custom config from:

```text
~/.config/easybar/config.toml
```

The repository includes `config.minimal.toml` as a small starter override. It keeps the default built-ins enabled, groups battery and Wi-Fi, and opens Wi-Fi in details mode.

From a cloned repository:

```bash
mkdir -p ~/.config/easybar
cp config.minimal.toml ~/.config/easybar/config.toml
easybar config reload
```

Use [Example Configs](../configuration/example-configs.md) for the available starter files.

## 5. Customize built-ins first

For most setups, customize native built-ins in `~/.config/easybar/config.toml` before writing Lua.

The default bar already enables:

- spaces
- battery
- Wi-Fi
- calendar

Good next built-ins to enable are:

- time
- date
- volume
- front app

Example:

```toml
[builtins.time]
enabled = true

[builtins.date]
enabled = true

[builtins.volume]
enabled = true
```

Reload config after editing:

```bash
easybar config reload
```

Use [Built-ins](../configuration/builtins.md) for built-in widget behavior and [Native Groups](../configuration/native-groups.md) when several widgets should share one visual container.

## 6. Add Lua only when you need custom behavior

Use Lua when you need custom text, shell commands, project-specific status, custom click behavior, or popup content that is not already covered by a built-in.

Create the widget directory if needed:

```bash
mkdir -p ~/.config/easybar/widgets
```

Then follow [First Widget](../lua/guides/first-widget.md).

## 7. Use references when needed

After the initial setup:

- [Configuration Reference](../configuration/reference.md) for exact config keys and defaults.
- [Lua Reference](../lua/reference/index.md) for exact Lua API shapes.
- [CLI Reference](../runtime/cli.md) for every control and diagnostic command.
