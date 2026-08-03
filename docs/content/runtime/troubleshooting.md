# Troubleshooting

Start with the symptom below. EasyBar keeps the main app, Lua runtime, and permission-sensitive agents separate, so identifying the affected process usually narrows the problem quickly.

## Collect basic status

```bash
pgrep -fl '/EasyBar$'
pgrep -fl EasyBarLuaRuntime
pgrep -fl EasyBarCalendarAgent
pgrep -fl EasyBarNetworkAgent
brew services list | grep easybar
easybar refresh
```

`easybar refresh` confirms that the CLI can reach the main control socket. Use `easybar metrics` for one process and connection snapshot.

## Find the logs

Enable file logging if necessary:

```toml
[logging]
enabled = true
level = "debug"
directory = "~/.local/state/easybar"
```

The default filenames are:

```text
~/.local/state/easybar/easybar.out
~/.local/state/easybar/calendar-agent.out
~/.local/state/easybar/network-agent.out
```

The Homebrew widgets additionally write `brew-widget.log` in the configured logging directory. Temporarily use `trace` only when debug output is insufficient. See [Logging](../configuration/logging.md).

## Bar does not appear

1. Confirm `/Applications/EasyBar.app` exists.
2. Start it with `open -a EasyBar`.
3. Check `easybar.out` for config, lock, screen, font, and Lua startup errors.
4. Confirm another build is not holding the single-instance lock.
5. If Gatekeeper blocks launch, follow [macOS Quarantine](../getting-started/macos-quarantine.md).

## Built-in widget is empty

Check whether the widget is enabled and whether its source process is available:

- spaces and layout state require AeroSpace 0.21.0 or newer
- calendar data requires the calendar agent and Calendar permission
- Wi-Fi details require the network agent and Location Services permission

Restart the relevant agent after changing a permission:

```bash
easybar agent restart calendar
easybar agent restart network
```

Use [Recovery](recovery.md) for source-specific checks and [Agent Debugging](../internals/agents/debugging.md) for raw socket and service diagnostics.

## Lua widget fails to load

Loader errors identify the widget filename and failing API call in `easybar.out`. Check:

- the widget is inside the configured `widgets_dir`
- imported modules such as `shell` and `text` exist under `widgets/lib`
- file-backed assets were copied with the widget
- properties that schedule work, such as `interval`, include their required callback
- required commands are present in `[app.env].PATH`

Validate config separately from Lua source:

```bash
easybar config validate
```

After fixing the widget, restart only the Lua runtime:

```bash
easybar runtime restart
```

See [Bundled Widgets](../lua/guides/bundled-widgets.md), [Commands](../lua/guides/commands.md), and [Lua Logging](../lua/guides/logging.md).

## Widget stops updating or a command is stuck

First request a normal refresh:

```bash
easybar refresh
```

If only Lua is stale, use `easybar runtime restart`. Asynchronous commands must have bounded timeouts and should expose cancellation for long-running user actions. For the Homebrew examples, inspect `brew-widget.log` before restarting so the last operation remains diagnosable.

## Popup or context menu does not open

Hover popups and native context menus use different interactions:

- hovering the widget anchor presents its popup
- right-clicking the anchor presents the widget's native context menu when configured
- right-clicking empty bar space presents EasyBar's bar context menu
- right-clicking popup content targets the popup, not its anchor

If a hover popup covers the anchor, move back to the actual bar icon before right-clicking. See [Popups](../lua/guides/popups.md) and [Native Context Menus](../lua/guides/context-menus.md).

## Config changes do not apply

When `watch_config = false`, reload manually:

```bash
easybar config reload
```

An invalid reload is rejected and the previous valid configuration remains active. Validate the file and inspect the reported key or section:

```bash
easybar config validate --config ~/.config/easybar/config.toml
```

## Homebrew install or upgrade fails

Run the failing Homebrew operation directly in a terminal to distinguish package-manager output from widget presentation:

```bash
brew update
brew upgrade --cask gi8lino/tap/easybar
```

Homebrew installations handle quarantine for the app, CLI, and agent applications. Manual release-archive installs do not. If Homebrew reports a cache extraction or quarantine error, preserve the complete error and check [macOS Quarantine](../getting-started/macos-quarantine.md) before changing extended attributes manually.

## Another instance is already running

EasyBar uses a single-instance guard. Stop the installed app before running a development build:

```bash
pkill -x EasyBar
open -a EasyBar
```

The agent services are separate and do not count as duplicate EasyBar instances.

## Escalation checklist

When reporting a problem, include:

- EasyBar version from `easybar --version`
- macOS and AeroSpace versions when relevant
- installation method: Homebrew or manual archive
- the affected widget or process
- the smallest relevant log excerpt
- whether `easybar refresh` and `easybar config validate` succeed

Do not include access tokens, private URLs, calendar content, or other secrets from widget command output.

## Related pages

- [Recovery](recovery.md)
- [CLI Reference](cli.md)
- [Agent Debugging](../internals/agents/debugging.md)
- [macOS Quarantine](../getting-started/macos-quarantine.md)
- [Configuration Logging](../configuration/logging.md)
