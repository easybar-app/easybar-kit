# Lua Widget Examples

The app repository keeps small, self-contained Lua examples for learning and runtime regression coverage. Installable integrations are maintained in the [official widgets repository](https://github.com/easybar-app/widgets) and discovered through the [widget registry](https://github.com/easybar-app/widget-registry).

```text
widgets/
├── assets/                  Assets used by the inbox demonstration
├── simple/                  Small, self-contained examples
├── compositions/            Examples combining nodes and interaction surfaces
├── inbox/demo/              Native inbox demonstration
└── install-manifest.csv     Local example installer catalog
```

## Lua discovery

EasyBar recursively loads every regular `.lua` file below the configured widgets directory. No directory or filename is a special entrypoint convention in the current runtime.

Reusable modules loaded with `require(...)` must keep their top level side-effect-free because files below the widgets directory are also discovered directly. Installable packages use explicit metadata so the package manager can distinguish widget entrypoints from library exports.

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

The selector reads `install-manifest.csv` and copies each selected example together with its declared README or assets. The manifest controls the development installer only; runtime discovery still loads every installed Lua file.

## Tests

Runtime and example tests live below `Tests/lua/`. Official package behavior tests live with their packages in the widgets repository.
