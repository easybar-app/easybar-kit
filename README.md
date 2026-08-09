# EasyBar

![EasyBar screenshot](https://easybar.dev/assets/bar.png)

EasyBar is a lightweight, scriptable macOS status bar built with SwiftUI and Lua. It combines
native widgets with custom Lua widgets and integrates with AeroSpace.

## Features

- Native widgets for spaces, apps, system status, calendar, and more
- Scriptable Lua widgets with events, popups, groups, and context menus
- Installable Lua widgets and libraries from the official package registry
- Shared inbox with unread state, grouping, Markdown, and widget actions
- File-based TOML themes and comment-preserving configuration updates
- AeroSpace integration and separate calendar and network helper agents
- Menu bar controller and CLI for runtime control and diagnostics

See screenshots in the [documentation](https://easybar.dev/#screenshots).

## Requirements

- macOS 14 Sonoma or newer
- [Homebrew](https://brew.sh/) for installation
- AeroSpace 0.21.0 or newer when using AeroSpace-backed widgets

## Installation

```bash
brew tap easybar-app/tap
brew install --cask easybar-app/tap/easybar
open -a EasyBar
```

See the [installation guide](https://easybar.dev/getting-started/installation/)
for upgrades, verification, and removal.

## Documentation

The full documentation is available at [easybar.dev](https://easybar.dev/).

- [Quick start](https://easybar.dev/getting-started/quick-start/)
- [Configuration](https://easybar.dev/configuration/overview/)
- [Themes](https://easybar.dev/configuration/themes/)
- [Lua widgets](https://easybar.dev/lua/overview/)
- [Widget packages](https://easybar.dev/runtime/widget-packages/)
- [Runtime and troubleshooting](https://easybar.dev/runtime/troubleshooting/)
- [Development](https://easybar.dev/internals/development/)

The complete defaults and a small starter configuration are also available in
[`config.defaults.toml`](./config.defaults.toml) and [`config.minimal.toml`](./config.minimal.toml).

## License

Licensed under the [Apache License 2.0](./LICENSE).
