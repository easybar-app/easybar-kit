# Bundled Widgets

The bundled examples are grouped by complexity and presentation instead of keeping every file at the root.

```text
widgets/
├── assets/                  Shared SVG assets
├── simple/                  Small, self-contained examples
├── caffeinate/              Configurable macOS caffeinate widget
├── brew/                    Standalone Homebrew popup widget
├── github/                  Standalone GitHub popup widget
├── gitlab/                  Standalone GitLab popup widget
├── tailscale/               Standalone Tailscale widget
├── wireguard/               Configurable Network Extension VPN widget
├── compositions/            Examples that combine nodes or features
├── inbox/
│   ├── demo/                Native inbox demonstration
│   ├── brew/                Homebrew inbox publisher
│   ├── github/              GitHub inbox publisher
│   └── gitlab/              GitLab inbox publisher
├── shared/                  Reusable Lua modules
└── install-manifest.csv     Installer catalog and dependencies
```

## Lua discovery

EasyBar recursively loads every regular file below the configured widgets directory with a `.lua` extension. Extension matching is case-insensitive. No directory name or filename is treated as a special entrypoint convention.

The bundled integrations still use `widget.lua` as a readable local filename, but EasyBar does not search for that name. A file named `status.lua`, `main.lua`, or anything else ending in `.lua` is discovered in exactly the same way.

Reusable modules are also executed during startup. Keep their top level side-effect-free: define functions and values, return the module, and start timers, commands, or subscriptions only from an explicit function called by another file.

A package with configuration, external dependencies, multiple files, or non-obvious behavior has its own README. Small examples are documented here and in the Lua guide.

## Presentation variants

Homebrew, GitHub, and GitLab each provide two presentations:

- the service directory contains a standalone bar widget with its own popup
- `inbox/<service>/` publishes the same kind of service data into the native shared inbox

Install only one presentation for a service unless duplicate polling and actions are intentional.

## Assets

Use a file-relative path for an asset stored beside the current Lua file:

```lua
easybar.asset("icon.svg")
```

Use the `@/` prefix for an asset relative to the configured widgets directory:

```lua
easybar.asset("@/assets/github.svg")
```

The bundled service widgets use the second form because `assets/` is shared across packages.

## Installation

Run:

```sh
make install-widgets
```

The selector reads `install-manifest.csv`, copies each selected Lua file at its categorized path, and adds its declared modules, README files, and assets. The manifest controls installation choices only; runtime discovery always loads every installed Lua file.

The manifest contains exactly one row per selectable widget:

```text
entrypoint.lua;dependency-one,dependency-two,dependency-three
```

The dependency field may be empty. Paths are relative to `widgets/`.

## Tests

All Lua tests live below `Tests/lua/`:

```text
Tests/lua/
├── helpers/
│   ├── inbox_host.lua
│   └── widget_host.lua
├── runtime/
│   └── test.lua
├── bundled/
│   └── test.lua
└── widgets/
    ├── caffeinate/test.lua
    ├── github/test.lua
    ├── gitlab/test.lua
    ├── tailscale/test.lua
    ├── inbox/
    │   ├── brew/test.lua
    │   ├── demo/test.lua
    │   ├── github/test.lua
    │   └── gitlab/test.lua
    └── shared/
        └── inbox/test.lua
```

`runtime/test.lua` covers the generic EasyBar Lua runtime contract. `bundled/test.lua` smoke-loads every selectable entrypoint from `install-manifest.csv`. Package-specific behavior belongs below `Tests/lua/widgets/`, while reusable test hosts live in `Tests/lua/helpers/`.

Tests intentionally do not live inside `widgets/`. EasyBar recursively executes every `.lua` file below `widgets_dir`, so colocated test files would become runtime files when that directory is used directly.

`make check-lua` validates the widget layout, syntax-checks Lua sources, then automatically discovers and runs every `Tests/lua/**/test.lua` file. Adding a new test therefore does not require editing a central test list.
