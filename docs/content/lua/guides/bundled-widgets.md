# Bundled Widgets

EasyBar ships Lua widgets that can be installed selectively with:

```sh
make install-widgets
```

`widgets/install-manifest.csv` is the source of truth for what the installer offers. It also declares the README files, shared modules, and assets copied with each selected widget.

## Catalog

### Small examples

- `simple/simple.lua` — minimal stateful widget.
- `simple/context-menu.lua` — native right-click menu API.
- `simple/network.lua` — native network snapshot.
- `compositions/group_demo.lua` — groups, shared styling, and popups.
- `compositions/popup-context-menu.lua` — popup and context menu on one item.
- `compositions/wifi+vpn.lua` — read-only tunnel indicator.

### Utilities and integrations

- `caffeinate/widget.lua` — keeps macOS awake. Configuration is documented in `widgets/caffeinate/README.md`.
- `brew/widget.lua` — Homebrew updates in a standalone popup.
- `github/widget.lua` — GitHub notifications in a standalone popup.
- `gitlab/widget.lua` — assigned GitLab work in a standalone popup.
- `tailscale/widget.lua` — Tailscale state and controls.
- `wireguard/widget.lua` — Network Extension VPN control.

Each integration package with configuration or external requirements has a README beside its widget.

### Native inbox publishers

- `inbox/demo/widget.lua` — representative native inbox messages and actions.
- `inbox/brew/widget.lua` — Homebrew updates and actions.
- `inbox/github/widget.lua` — GitHub notifications and pull-request actions.
- `inbox/gitlab/widget.lua` — GitLab work items and merge-request actions.

## Choose one presentation

Homebrew, GitHub, and GitLab each have a standalone popup and a native-inbox presentation. Normally install one presentation per service:

```text
brew/widget.lua          or inbox/brew/widget.lua
github/widget.lua        or inbox/github/widget.lua
gitlab/widget.lua        or inbox/gitlab/widget.lua
```

Loading both is supported, but it normally duplicates polling and actions.

## Dependencies and configuration

Package-specific requirements and settings belong in the package README instead of this catalog. Common examples include authenticated `gh` or `glab`, Homebrew availability in `[app.env].PATH`, the Tailscale executable, WireGuard's VPN service name, and the Caffeinate left-click duration.

For process environment behavior, see [Environment](../../configuration/environment.md). For Lua-owned configuration under `[widgets.*]`, see [Widget Settings](storage.md).

## Repository layout

```text
widgets/
├── assets/
├── brew/
├── caffeinate/
├── compositions/
├── github/
├── gitlab/
├── inbox/
├── shared/
├── simple/
├── tailscale/
├── wireguard/
└── install-manifest.csv
```

The directory layout is for organization. EasyBar recursively executes installed `.lua` files; `widget.lua` is not a special runtime filename.
