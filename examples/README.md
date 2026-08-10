# Lua Widget Examples

The app repository keeps small, self-contained Lua examples for learning and runtime regression
coverage. Browse this directory for the current examples. Installable integrations are maintained
in the [official widgets repository](https://github.com/easybar-app/widgets) and discovered through
the [widget registry](https://github.com/easybar-app/registry).

## Lua discovery

EasyBar recursively loads regular `.lua` files below the configured widgets directory, excluding
reusable modules below `shared/`. Package-managed widgets are loaded separately from the managed
store and use their declared entrypoint.

Reusable modules loaded with `require(...)` should keep their top level side-effect-free. Installable packages use explicit metadata so the package manager can distinguish widget entrypoints from library exports.

## Assets

Use a file-relative path for an asset stored beside a widget:

```lua
easybar.asset("icon.svg")
```

Use `@/` for an asset relative to the configured widgets directory:

```lua
easybar.asset("@/assets/github.svg")
```

## Installing the examples

Run:

```sh
make install-widgets
```

The selector reads `install-manifest.csv` and copies each selected example together with its
declared README or assets. The manifest controls the development installer only; runtime discovery
still loads every installed Lua file.

## Tests

Runtime and example tests live below `Tests/lua/`. Official package behavior tests live with their packages in the widgets repository.
