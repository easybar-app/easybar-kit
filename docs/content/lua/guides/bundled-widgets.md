# Widget Packages And Examples

EasyBar keeps installable integrations separate from the app:

- the [official widgets repository](https://github.com/easybar-app/widgets) owns package source, package metadata, assets, and focused tests
- the [widget registry](https://github.com/easybar-app/widget-registry) owns searchable catalog entries
- this repository keeps small examples for learning and runtime regression coverage

## Official packages

The official catalog currently contains:

- `brew` — Homebrew updates in a standalone popup
- `caffeinate` — timed or indefinite sleep prevention
- `github` — GitHub notifications in a standalone popup
- `gitlab` — assigned GitLab work in a standalone popup
- `inbox-brew` — Homebrew updates and actions in the native inbox
- `inbox-github` — GitHub notifications and pull-request actions in the native inbox
- `inbox-gitlab` — GitLab work items and merge-request actions in the native inbox
- `tailscale` — Tailscale state and exit-node controls
- `wireguard` — Network Extension VPN control
- `shared` — reusable `text`, `retry`, and `inbox` Lua modules used as dependencies

Homebrew, GitHub, and GitLab each have a standalone and native-inbox presentation. Normally install one presentation per service to avoid duplicate polling and actions.

Package-specific requirements and settings are documented beside each package. Common requirements include authenticated `gh` or `glab`, Homebrew availability in `[app.env].PATH`, the Tailscale executable, WireGuard's VPN service name, and the Caffeinate duration setting.

Install one by registry name, then reload the app:

```sh
easybar widgets install caffeinate
easybar config reload
```

The registry is optional. See [Widget Packages](../../runtime/widget-packages.md) to install a self-created package directly from a local directory or archive.

## Local examples

The app repository ships these selectable examples:

- `simple/simple.lua` — minimal stateful widget
- `simple/context-menu.lua` — native right-click menu API
- `simple/network.lua` — native network snapshot
- `compositions/group_demo.lua` — groups, shared styling, and popups
- `compositions/popup-context-menu.lua` — popup and context menu on one item
- `compositions/wifi+vpn.lua` — read-only tunnel indicator
- `inbox/demo/widget.lua` — representative native inbox messages and actions

Install examples from a source checkout with:

```sh
make install-widgets
```

`widgets/install-manifest.csv` declares the examples and assets copied by that development installer. It is not the package registry.

For process environment behavior, see [Environment](../../configuration/environment.md). For Lua-owned configuration under `[widgets.*]`, see [Widget Settings](storage.md).
