# Installation

EasyBar is distributed through Homebrew in the `gi8lino/tap` tap.

## Install

Add the tap:

```bash
brew tap gi8lino/tap
```

Install EasyBar:

```bash
brew install --cask gi8lino/tap/easybar
```

The cask installs `EasyBar.app` into `/Applications`, links the `easybar` CLI into Homebrew's executable path, and installs the calendar and network agents as formula dependencies. Installation starts both agent services automatically.

The agents remain separate applications so macOS can assign Calendar and Location permissions to the processes that use them. Homebrew Services keeps them running independently of the main app.

EasyBar can start without a custom config file. Create `~/.config/easybar/config.toml` only when you want to customize the defaults.

## What runs independently

| Component           | Installed as     | Started by                   | Continues if the bar stops      |
| ------------------- | ---------------- | ---------------------------- | ------------------------------- |
| EasyBar app and bar | Homebrew cask    | Finder, Spotlight, or `open` | Controller stays until app quit |
| `easybar` CLI       | Cask binary link | User command                 | Not applicable                  |
| Calendar agent      | Formula service  | Homebrew Services            | Yes                             |
| Network agent       | Formula service  | Homebrew Services            | Yes                             |

Stopping the bar from the controller does not quit the EasyBar application. The controller can therefore start it again. Quitting EasyBar removes both the bar and controller, but does not stop the agent services.

## Upgrade

Upgrade EasyBar and its dependencies with Homebrew:

```bash
brew update
brew upgrade --cask gi8lino/tap/easybar
```

Quit and reopen EasyBar after upgrading if the previous version is still running.

Verify that the app and CLI versions agree:

```bash
easybar --version
/Applications/EasyBar.app/Contents/MacOS/EasyBar --version
```

## Launch EasyBar

Open EasyBar from Finder, Spotlight, or the command line:

```bash
open -a EasyBar
```

## Verify the install

Check that Homebrew installed the app:

```bash
test -d /Applications/EasyBar.app && echo "EasyBar is installed"
```

Check running processes:

```bash
pgrep -fl EasyBar
pgrep -fl EasyBarCalendarAgent
pgrep -fl EasyBarNetworkAgent
```

Check the independently managed agent services:

```bash
brew services list | grep easybar
```

Trigger one refresh through the CLI:

```bash
easybar refresh
```

## Uninstall

Remove the app and CLI link with:

```bash
brew uninstall --cask gi8lino/tap/easybar
```

Homebrew may retain dependency formulae after the cask is removed. If you no longer need the agents, stop and uninstall them explicitly:

```bash
brew services stop easybar-calendar-agent
brew services stop easybar-network-agent
brew uninstall easybar-calendar-agent easybar-network-agent
```

Before removing the formulae, check whether another installed package still depends on them. Homebrew does not remove your configuration, themes, widget files, logs, or inbox state automatically.

Common user data remains under:

```text
~/.config/easybar
~/.local/state/easybar
```

See [Configuration Path](configuration-path.md) and [Logging](../configuration/logging.md) before deleting these directories.
