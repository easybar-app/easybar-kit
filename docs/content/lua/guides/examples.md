# Examples

This page explains a few complete Lua widget patterns. For official packages, dependencies, and local examples, use [Widget Packages And Examples](bundled-widgets.md).

If you are just starting out, read [First Widget](first-widget.md) before using these as templates.

## Toggle widget

```lua
local enabled = false
local toggle

local function render()
    toggle:set({
        icon = {
            string = enabled and "󰄬" or "󰄱",
            color = enabled and "#30d158" or "#ff453a",
        },
        label = {
            string = enabled and "ON" or "OFF",
            color = enabled and "#30d158" or "#ff453a",
        },
    })
end

toggle = easybar.add(easybar.kind.item, "toggle_test", {
    position = "right",
    order = 1,
})

toggle:subscribe(easybar.events.forced, function()
    render()
end)

toggle:subscribe(easybar.events.mouse.clicked, function()
    enabled = not enabled
    render()
end)

render()
```

## Official Homebrew package

[`packages/brew/widget.lua`](https://github.com/easybar-app/widgets/blob/main/packages/brew/widget.lua) is a complete
example of a stateful popup widget. It:

- checks formulae and casks with `brew outdated`
- exposes Update and Upgrade actions as clickable popup children
- runs Homebrew commands asynchronously so other widgets remain responsive
- changes Update to Cancel while an operation is active
- returns directly to the idle actions after cancellation while preserving the last known package list
- writes command diagnostics to `brew-widget.log` under the configured EasyBar logging directory

The widget is intentionally more extensive than the snippets on this page. Use it as a reference
for command chaining, cancellation, structured state rendering, popup rows, error presentation,
and bounded file logging.

Use the inbox-only
[`packages/inbox-brew/widget.lua`](https://github.com/easybar-app/widgets/blob/main/packages/inbox-brew/widget.lua)
variant to publish outdated formulae, casks, Homebrew warnings, and command errors into the native
inbox. It supports refresh, `brew update`, individual or complete upgrades, and cancellation while
an update or upgrade is running. Install either `brew` or `inbox-brew`, not both.

## Official GitLab package

[`packages/gitlab/widget.lua`](https://github.com/easybar-app/widgets/blob/main/packages/gitlab/widget.lua) shows the
open issues and merge requests assigned to the authenticated user. It works with GitLab.com and
private GitLab Self-Managed or Dedicated instances through the official `glab` CLI. Use the
inbox-only [`packages/inbox-gitlab/widget.lua`](https://github.com/easybar-app/widgets/blob/main/packages/inbox-gitlab/widget.lua)
variant to publish the same work items into EasyBar's shared [native inbox](inbox.md).

The equivalent inbox-only GitHub publisher is
[`packages/inbox-github/widget.lua`](https://github.com/easybar-app/widgets/blob/main/packages/inbox-github/widget.lua).
Both publishers use EasyBar's native item URL handling, preserve the last valid snapshot when a
refresh fails, and publish service update times for the inbox's default timestamp sorting. Their generic validation, bounded-error, and ISO-8601 parsing functions live in
[`packages/shared/inbox.lua`](https://github.com/easybar-app/widgets/blob/main/packages/shared/inbox.lua). The service publishers remain complete package entrypoints, while the shared helper is
documented under [Reusable Modules](modules.md#inbox-data-helper).
Use [`examples/inbox-demo/widget.lua`](https://github.com/easybar-app/easybar/blob/main/examples/inbox-demo/widget.lua)
to preview inbox grouping, severities, Markdown, unread state, and actions without external services.

Install `glab`, authenticate the instance, and make the CLI and host available to GUI-launched
EasyBar sessions:

```sh
brew install glab
glab auth login --hostname gitlab.example.com
```

```toml
[app.env]
PATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
GITLAB_HOST = "https://gitlab.example.com"
```

The `gitlab` package manifest declares its shared-library dependency and external `glab` requirement.
The widget refreshes every five minutes, orders assigned work by its most recent update, opens an
item when its popup row is clicked, and provides Refresh and Open GitLab actions in its native
right-click menu. `GITLAB_HOST` is optional for GitLab.com.

## Clock widget

```lua
local clock

clock = easybar.add(easybar.kind.item, "clock", {
    position = "right",
    order = 10,
    interval = 60,
    icon = "􀐫",
    label = os.date("%H:%M"),
    on_interval = function()
        clock:set({
            label = os.date("%H:%M"),
        })
    end,
})
```

## Native context menu widget

[`examples/context-menu.lua`](https://github.com/easybar-app/easybar/blob/main/examples/context-menu.lua)
shows a native macOS right-click menu with actions, a separator, checked state, a submenu, and
dynamic menu replacement. See [Native Context Menus](context-menus.md) for the full
API and right-click precedence rules.

## Popup and context menu widget

[`examples/popup-context-menu.lua`](https://github.com/easybar-app/easybar/blob/main/examples/popup-context-menu.lua)
attaches both interaction surfaces to one anchor. Hovering shows status in a popup, while
right-clicking opens a native menu with an action and checked mode submenu. The example also shows
how one render function keeps popup content, anchor content, and menu checkmarks synchronized. The
popup uses EasyBar's native hover tracking, so it remains open while moving from the anchor into
the popup without custom `mouse.entered` or `mouse.exited` handlers.

## Widget-relative image asset

```lua
local github = easybar.add(easybar.kind.item, "github", {
    icon = {
        color = easybar.theme.ref.text,
        image = {
            path = easybar.asset("github.svg"),
            size = 16,
        },
    },
})
```

`easybar.asset()` resolves relative to the Lua entrypoint, so the example expects `github.svg` beside the widget file. Prefix the path with `@/` to resolve it from the configured widgets directory instead:

```lua
easybar.asset("@/assets/github.svg")
```

This is useful for user-managed widgets that share root assets. Installable packages normally keep assets inside their own package directory and use file-relative paths. `easybar.asset(...)` rejects absolute paths; an already absolute path may still be assigned directly to `image.path`.

## Inline SVG image

```lua
local github_svg = [[
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
    <path d="..." />
</svg>
]]

local github = easybar.add(easybar.kind.item, "github", {
    icon = {
        color = easybar.theme.ref.text,
        image = {
            svg = github_svg,
            size = 16,
        },
    },
})
```

Inline SVG is useful for small, self-contained widgets. Set either `path` or `svg`, never both.
Without an icon color, SVG images keep their original colors; setting `icon.color` applies the
same template tint used for file-backed images. Inline SVG does not sandbox a widget: widget files
remain trusted local code.

## Related pages

- [Widget Packages And Examples](bundled-widgets.md)
- [Subscribe To Events](subscribe-to-events.md)
- [Style Popups And Groups](style-popups-and-groups.md)
- [Popups](popups.md)
- [Native Context Menus](context-menus.md)
- [API Summary](../api-summary.md)
