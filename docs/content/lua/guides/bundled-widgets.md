# Bundled Widgets

The repository's `widgets/` directory contains examples ranging from minimal API demonstrations to complete integrations. Copy only the widgets you want into your configured `widgets_dir`, together with the `lib/` directory when the widget imports shared modules.

## Catalog

| Widget                   | Purpose                            | Requirements                                      | Inbox publisher |
| ------------------------ | ---------------------------------- | ------------------------------------------------- | --------------- |
| `simple.lua`             | Minimal stateful toggle            | None                                              | No              |
| `group_demo.lua`         | Groups, shared styling, and popups | None                                              | No              |
| `context-menu.lua`       | Native right-click menu API        | `gh` for its example action                       | No              |
| `popup-context-menu.lua` | Popup and context menu on one item | None                                              | No              |
| `inbox-demo.lua`         | Representative inbox test messages | Native inbox enabled                              | Yes             |
| `brew.lua`               | Homebrew updates in its own popup  | `brew` in `[app.env].PATH`                        | No              |
| `brew-inbox.lua`         | Homebrew updates and actions       | `brew` in `[app.env].PATH`                        | Yes             |
| `github.lua`             | GitHub notifications popup         | Authenticated `gh`; bundled GitHub SVG asset      | No              |
| `github-inbox.lua`       | GitHub notifications               | Authenticated `gh`                                | Yes             |
| `gitlab.lua`             | Assigned GitLab work items         | Authenticated `glab`; optional `GITLAB_HOST`      | No              |
| `gitlab-inbox.lua`       | Assigned GitLab work items         | Authenticated `glab`; optional `GITLAB_HOST`      | Yes             |
| `network.lua`            | Native network snapshot            | Network agent                                     | No              |
| `wifi+vpn.lua`           | Read-only tunnel indicator         | Network agent                                     | No              |
| `tailscale.lua`          | Tailscale state and controls       | `tailscale`; optional `TAILSCALE` command setting | No              |
| `wireguard.lua`          | Network Extension VPN control      | Service name in `lib/secrets.lua`                 | No              |

## Choose one presentation

Do not load both presentation variants for the same service:

- choose `brew.lua` or `brew-inbox.lua`
- choose `github.lua` or `github-inbox.lua`
- choose `gitlab.lua` or `gitlab-inbox.lua`

The regular variants own a bar icon and popup. The inbox variants publish snapshots into the shared
native inbox, register their operations as source actions, and opt their refresh action into the
inbox-wide **Refresh all** command.

The Tailscale widget uses left click to bring Tailscale up or down. Its right-click menu lists the
currently advertised exit nodes and a **Disabled** option. Selecting one changes Tailscale's own
persistent state; EasyBar does not duplicate the selected node in `config.toml`.

GitHub and GitLab inbox items expose a dedicated **Mark as read** action. GitHub also acknowledges the notification through the GitHub API. GitLab publishes assigned work items rather than notification records, so its action updates EasyBar's persistent local read state.

The GitHub inbox uses squash merging by default. Choose the pull-request merge strategy with widget settings:

```toml
[widgets.github-inbox]
merge_method = "squash" # merge, rebase, or squash
```

Unsupported values fall back to `squash` and produce a widget log warning. See [Widget Settings](storage.md) for the Lua storage API.

GitHub and GitLab publish each item's native `url` and `timestamp`, so EasyBar supplies the **Open**
button and sorts mixed sources by their service-provided update time. Failed or malformed refreshes
keep the last valid snapshot visible and add a bounded error item. GitHub coalesces refreshes that
finish while another refresh is active, ensuring overlapping notification acknowledgements receive
one final server snapshot.

Homebrew also preserves its last valid package snapshot when command output is malformed or a
refresh fails. Its parser validates formula, cask, and installed-version shapes before replacing
the snapshot, while still publishing warnings printed around Homebrew's JSON response.

Each inbox publisher sends at most 500 items per snapshot and prioritizes error and warning
records. GitLab merges issues and merge requests by update time before applying that limit, while
GitHub preserves the API's notification order. The native inbox may display fewer items when
`max_items` has a lower value.

## GUI environment

Apps opened from Finder or Spotlight do not inherit `.zshrc`. Make required CLIs and instance settings explicit:

```toml
[app.env]
PATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
GITLAB_HOST = "https://gitlab.example.com"
TAILSCALE = "/opt/homebrew/bin/tailscale"
```

Authenticate tools in a terminal before starting the corresponding widget:

```bash
gh auth login
glab auth login --hostname gitlab.example.com
```

See [Environment](../../configuration/environment.md) for precedence and GUI-launch behavior.

## Shared modules and assets

Several examples import `inbox`, `retry`, `text`, or `secrets` from `widgets/lib`. Preserve that directory structure when copying them. File-backed assets are resolved relative to the widget with `easybar.asset(...)`; copy those assets as well.

The inbox publishers use `lib/inbox.lua` to reject object-shaped responses where arrays are
expected, bound external error messages, and convert ISO-8601 update times without depending on the
Mac's local timezone. See [Reusable Modules](modules.md#inbox-data-helper) for its public functions.

Keep the secrets helper at `widgets/lib/secrets.lua`. Do not place a copy at the top level: EasyBar executes every top-level `*.lua` file as a widget entrypoint, while files below `lib/` are loaded only through `require(...)`. Edit the module before copying `wireguard.lua`, then copy `lib/secrets.lua` with the widget.

The GitHub, GitLab, and Homebrew inbox widgets wait briefly after the Mac wakes before contacting
network services. They retry transient read-only failures, but authentication failures and
state-changing operations are not retried automatically.

## Diagnostics

The GitHub, GitLab, and Homebrew inbox widgets emit semantic operation logs:

- `debug` for refresh reasons, action routing, and published item counts
- `trace` for command attempts, retry scheduling, and wake-delay handling
- `info` for user-triggered mutations and cancellation
- `warn` or `error` for invalid responses, exhausted retries, and failed mutations

The widget file name is attached automatically as a structured `widget` field.

Lua loader and command failures also appear in EasyBar's logs. The Homebrew examples maintain a
bounded `brew-widget.log` in the configured logging directory. Use [Lua Logging](logging.md),
[Commands](commands.md), and [Troubleshooting](../../runtime/troubleshooting.md) when an example does
not update.
