# Bundled Widgets

The repository's `widgets/` directory is organized by complexity and presentation. Small examples live in `simple/`, multi-node examples live in `compositions/`, standalone service widgets use their own package directories, and native-inbox publishers live below `inbox/`.

Use `make install-widgets` to select widgets. The installer reads `widgets/install-manifest.csv`, preserves the categorized paths, and copies each selected entrypoint together with its declared modules, README files, assets, and LuaLS configuration.

## Catalog

| Entrypoint                            | Purpose                             | Requirements                                 | Inbox publisher |
| ------------------------------------- | ----------------------------------- | -------------------------------------------- | --------------- |
| `simple/simple.lua`                   | Minimal stateful toggle             | None                                         | No              |
| `simple/caffeinate.lua`               | Prevents display and idle sleep     | macOS `caffeinate`                           | No              |
| `simple/context-menu.lua`             | Native right-click menu API         | `gh` for one example action                  | No              |
| `simple/network.lua`                  | Native network snapshot             | Network agent                                | No              |
| `compositions/group_demo.lua`         | Groups, shared styling, and popups  | None                                         | No              |
| `compositions/popup-context-menu.lua` | Popup and context menu on one item  | None                                         | No              |
| `compositions/wifi+vpn.lua`           | Read-only tunnel indicator          | Network agent                                | No              |
| `inbox/demo/widget.lua`               | Representative inbox messages       | Native inbox enabled                         | Yes             |
| `brew/widget.lua`                     | Homebrew updates in a popup         | `brew` in `[app.env].PATH`                   | No              |
| `inbox/brew/widget.lua`               | Homebrew updates and actions        | `brew` in `[app.env].PATH`                   | Yes             |
| `github/widget.lua`                   | GitHub notifications popup          | Authenticated `gh`                           | No              |
| `inbox/github/widget.lua`             | GitHub notifications and PR actions | Authenticated `gh`                           | Yes             |
| `gitlab/widget.lua`                   | Assigned GitLab work popup          | Authenticated `glab`; optional `GITLAB_HOST` | No              |
| `inbox/gitlab/widget.lua`             | Assigned GitLab work and MR actions | Authenticated `glab`; optional `GITLAB_HOST` | Yes             |
| `tailscale/widget.lua`                | Tailscale state and controls        | `tailscale`; optional `TAILSCALE` executable | No              |
| `wireguard/widget.lua`                | Network Extension VPN control       | VPN service name in widget config            | No              |

The service packages contain their own README files with configuration and behavior details.

The Caffeinate widget uses an indefinite session for left-click by default. Set a bounded default from
1 through 1439 minutes when left-click should start a timed session instead:

```toml
[widgets.caffeinate]
duration_minutes = 60
```

Right-click always exposes the indefinite option and timed presets from 15 minutes through 4 hours.

## Choose one presentation

Homebrew, GitHub, and GitLab each have a standalone popup presentation and a native-inbox presentation:

- choose `brew/widget.lua` or `inbox/brew/widget.lua`
- choose `github/widget.lua` or `inbox/github/widget.lua`
- choose `gitlab/widget.lua` or `inbox/gitlab/widget.lua`

Loading both variants is supported but normally causes duplicate polling and actions.

The inbox variants publish snapshots into the shared native inbox, expose service operations as source actions, and participate in the inbox-wide **Refresh all** action. GitHub and GitLab inbox widgets also provide guarded merge actions and persist their merge choices under `[widgets.github-inbox]` and `[widgets.gitlab-inbox]`.

## GUI environment

Apps opened from Finder or Spotlight do not inherit `.zshrc`. Make required executables and service settings explicit:

```toml
[app.env]
PATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
GITLAB_HOST = "https://gitlab.example.com"
TAILSCALE = "/opt/homebrew/bin/tailscale"
```

Authenticate CLIs in a terminal before starting the matching widget:

```bash
gh auth login
glab auth login --hostname gitlab.example.com
```

WireGuard uses widget configuration instead of an environment variable. Use `scutil --nc list` to find the exact Network Extension service name, then configure it:

```toml
[widgets.wireguard]
vpn_name = "WireGuard"
```

See [Environment](../../configuration/environment.md) and [Widget Settings](storage.md).

## Lua files and support files

EasyBar recursively executes every regular `.lua` file, case-insensitively, below `widgets_dir`:

```text
<widgets_dir>/**/*.lua
```

The categorized directory names and the bundled `widget.lua` filenames are organizational choices, not loader rules. Reusable Lua modules are discovered too, so their top level must remain side-effect-free. Assets, README files, and other non-Lua files are never executed.

The categorized bundled layout is:

```text
widgets/
├── assets/
├── simple/
├── compositions/
├── brew/
├── github/
├── gitlab/
├── tailscale/
├── wireguard/
├── inbox/
│   ├── demo/
│   ├── brew/
│   ├── github/
│   └── gitlab/
├── shared/
└── install-manifest.csv
```

Logs and command diagnostics use each file's relative path without `.lua`. For example, `inbox/github/widget.lua` uses `inbox/github/widget`.

## Shared assets

`easybar.asset(...)` normally resolves relative to the current entrypoint. Prefix a path with `@/` to resolve it from the configured widgets directory:

```lua
local local_icon = easybar.asset("icon.svg")
local shared_icon = easybar.asset("@/assets/github.svg")
```

The bundled service widgets use widgets-root-relative paths because the SVG files are shared across packages. The `@/` prefix does not allow absolute paths or escaping the widgets directory.

## Reliability behavior

The GitHub, GitLab, and Homebrew inbox publishers wait briefly after wake or session activation before contacting network services. Read-only refreshes retry transient network failures. Authentication failures and mutations are not retried automatically.

Failed or malformed refreshes preserve the last valid snapshot and add a bounded error item. Each inbox publisher caps its outgoing snapshot at 500 items; the native inbox may display fewer when its configured `max_items` value is lower.

## Diagnostics

Service widgets emit structured operation logs. Identities are derived generically from relative paths:

```text
brew/widget.lua              -> brew/widget
inbox/brew/widget.lua        -> inbox/brew/widget
inbox/github/widget.lua      -> inbox/github/widget
inbox/gitlab/widget.lua      -> inbox/gitlab/widget
```

Use the log CLI to isolate one publisher:

```bash
easybar logs --widget inbox/github/widget --runtime lua --level debug
easybar logs --widget inbox/brew/widget --runtime lua --level trace --follow
```

See [Logging](logging.md) and [Troubleshooting](../../runtime/troubleshooting.md).
