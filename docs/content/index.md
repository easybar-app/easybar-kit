# EasyBar

[![EasyBar screenshot](assets/bar.png)](assets/bar.png)

EasyBar is a lightweight, scriptable macOS status bar built with SwiftUI and Lua.

Use native built-ins for common system data such as spaces, battery, Wi-Fi, calendar, time, date, and volume. Add Lua widgets only when you need custom display logic, shell-command integration, or personal workflow behavior.

EasyBar is designed for a clean macOS workflow and integrates especially well with AeroSpace. EasyBar requires AeroSpace 0.21.0 or newer for AeroSpace-backed widgets.

## Start here

New users should follow the user path first:

1. [Quick Start](getting-started/quick-start.md): install EasyBar, start the services, verify that the bar responds, and optionally create a custom config.
2. [Built-ins Vs Lua](getting-started/builtins-vs-lua.md): choose whether a widget belongs in `config.toml` or in a Lua file.
3. [Configuration Overview](configuration/overview.md): learn where config lives and which pages explain each config area.
4. [Lua Widgets](lua/overview.md): add custom widgets after the built-ins cover the basics.
5. [Troubleshooting](runtime/troubleshooting.md): fix startup, service, config, permission, and runtime issues.

## Common tasks

| Goal                            | Start with                                           |
| ------------------------------- | ---------------------------------------------------- |
| Install and see the bar         | [Quick Start](getting-started/quick-start.md)        |
| Find the runtime config path    | [Config Path](getting-started/configuration-path.md) |
| Enable native widgets           | [Built-ins](configuration/builtins.md)               |
| See all command-line controls   | [CLI Reference](runtime/cli.md)                      |
| Group built-in widgets visually | [Native Groups](configuration/native-groups.md)      |
| Pick or customize colors        | [Themes](configuration/themes.md)                    |
| Add a custom widget             | [First Widget](lua/guides/first-widget.md)           |
| Browse bundled widget examples  | [Bundled Widgets](lua/guides/bundled-widgets.md)     |
| Debug a stuck bar               | [Troubleshooting](runtime/troubleshooting.md)        |
| Understand process boundaries   | [Internals](internals/overview.md)                   |

## Features

- Native macOS bar window built with SwiftUI
- Configurable native widgets for spaces, applications, system status, calendar, and more
- Object-style Lua widgets with events, timers, asynchronous commands, popups, and groups
- Native right-click context menus for Lua widgets
- Shared native inbox with unread state, grouping, persistence, Markdown, and publisher actions
- File-based themes with bundled and custom TOML palettes
- AeroSpace integration for spaces, focused app state, and layout mode state
- Calendar and network helper agents for permission-sensitive data
- Persistent menu bar controller and CLI commands for reloads, restarts, and diagnostics
- Homebrew cask installation into `/Applications` with separate permission-agent services
- Config-driven logging, troubleshooting diagnostics, and lightweight runtime metrics

## How EasyBar is meant to be used

Start with the native built-ins because they keep platform-sensitive behavior in Swift and require less maintenance. Use `config.toml` for placement, grouping, themes, and built-in behavior. Reach for Lua when a widget needs custom formatting, shell commands, custom interactions, or project-specific status.

## Screenshots

### Calendar

The native [Calendar widget](configuration/builtins/calendar.md) can open a full month view from its
time and date anchor. Days with events are marked for quick scanning.

[![Calendar screenshot](assets/month.png){ .screenshot-compact .screenshot-month }](assets/month.png)

### Upcoming

The Calendar widget can also show upcoming events in a compact agenda, including their calendar,
time, and location.

[![Upcoming screenshot](assets/upcoming.png){ .screenshot-compact .screenshot-upcoming }](assets/upcoming.png)

### Inbox

The native [Inbox](configuration/builtins/inbox.md) collects notifications from Lua sources and the
`easybar inbox` CLI. It can group them by source or category, and items may expose actions such as
opening, dismissing, or marking them as read.

[![Inbox screenshot](assets/inbox.png){ .screenshot-compact .screenshot-inbox }](assets/inbox.png)

### CPU

The CPU popup shows current processor activity and a short usage history. Its context menu provides
controls for the refresh interval and history.

[![CPU screenshot](assets/cpu.png){ .screenshot-compact .screenshot-cpu }](assets/cpu.png)

### Wi-Fi

The native [Wi-Fi widget](configuration/builtins/wifi.md) can display connection and network details
such as the SSID, signal strength, and IP addresses.

[![Wi-Fi screenshot](assets/wifi.png){ .screenshot-compact .screenshot-wifi }](assets/wifi.png)

### Tailscale

The Lua [Tailscale widget](https://github.com/gi8lino/easybar/blob/main/widgets/tailscale.lua)
shows whether Tailscale is running and which exit node is active. Left-click the widget to start or
stop Tailscale. Right-click it to select or disable an exit node, or to refresh the current status.

#### Enabled with an exit node

[![Tailscale enabled with an exit node](assets/tailscale_enabled.png){ .screenshot-compact .screenshot-tailscale }](assets/tailscale_enabled.png)

#### Disabled

[![Tailscale disabled](assets/tailscale_disabled.png){ .screenshot-compact .screenshot-tailscale }](assets/tailscale_disabled.png)

### Spaces

The native [Spaces widget](configuration/builtins/spaces.md) displays AeroSpace workspaces and
highlights the currently focused workspace. This example shows the widget without Front App.

[![Spaces screenshot](assets/spaces.png){ .screenshot-compact .screenshot-spaces }](assets/spaces.png)

### Spaces with Front App

When front-app display is enabled, the Spaces widget adds the focused application's icon and name
beside the workspace buttons. The screenshot uses these layout settings:

```toml
[builtins.spaces.layout]
hide_empty = false # Hides spaces that have no apps.
show_label = true  # Shows the workspace label.
show_icons = false # Shows app icons inside each space pill.
```

[![Spaces with Front app screenshot](assets/spaces_front_app.png){ .screenshot-compact .screenshot-spaces-front-app }](assets/spaces_front_app.png)

### Native widget controls

Right-click empty space in the bar to open EasyBar's context menu. The **Native Widgets** submenu
lets you enable or disable built-in widgets without editing the configuration file manually.

[![Native widget controls](assets/native_widgets.png){ .screenshot-compact .screenshot-native-widgets }](assets/native_widgets.png)

### Custom context menu

Lua widgets can build custom context menus with nested actions, toggles, disabled entries, and
keyboard shortcuts.

[![Context menu screenshot](assets/custom_context.png){ .screenshot-compact .screenshot-context }](assets/custom_context.png)

### Top bar app context menu

Right-clicking an application in the top bar opens controls for focusing, hiding, or quitting that
application without leaving the current workspace.

[![Topbar App](assets/topbar_app.png){ .screenshot-compact .screenshot-topbar }](assets/topbar_app.png)
