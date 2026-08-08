# Contributing an EasyBar Widget

Contributions to the [official widgets repository](https://github.com/easybar-app/widgets) may add
a widget, a reusable Lua library, or improve an existing package. Keep each package self-contained
below `packages/<name>/` and use lowercase, hyphen-separated names.

## Package layout

A typical widget contains:

```text
packages/<name>/
├── package.toml
├── README.md
├── widget.lua
├── assets/
└── tests/
    └── test.lua
```

Only include directories that the package needs. Library packages export Lua modules instead of
declaring a widget entrypoint. Tests belong inside the package under `tests/`; release archives
exclude that directory.

## Manifest

Start a widget at version `0.1.0` with a manifest like this:

```toml
manifest_version = 1
name = "my-widget"
version = "0.1.0"
kind = "widget"
description = "Describe what the widget shows or controls."
license = "Apache-2.0"
minimum_easybar_version = "0.42.0"
entrypoint = "widget.lua"
readme = "README.md"
categories = ["utilities"]

[repository]
url = "https://github.com/easybar-app/widgets"
path = "packages/my-widget"
```

For a library, set `kind = "library"`, omit `entrypoint`, and declare the public modules:

```toml
[exports]
retry = "retry.lua"
```

Declare package dependencies with a compatible semantic-version constraint:

```toml
[dependencies]
my-library = "^1.0.0"
```

Every non-test Lua file must be either the entrypoint or a declared export. Declare external
commands, optional environment variables, EasyBar settings, and native-inbox use in the manifest
when the package needs them. Existing package manifests demonstrate those optional tables.

## Documentation and tests

The package README should explain its behavior, requirements, settings, permissions, and any
external authentication. Do not include credentials or machine-specific configuration.

Put focused Lua tests in `packages/<name>/tests/`. Shared host implementations are available in
`tests/support/`, and every widget also runs through the cross-package smoke test.

From the widgets repository, with EasyBar checked out as a sibling directory, run:

```sh
make check
make lint-lua
make package PACKAGE=my-widget OUTPUT_DIR=dist
```

Use `EASYBAR_ROOT=/path/to/easybar` with `make check` when the app checkout is elsewhere. The final
command is optional, but it is useful for inspecting the exact package archive before review.

## Pull request checklist

- Keep the change focused on one package or one shared concern.
- Ensure the manifest name matches its directory and all referenced files exist.
- Add focused tests for parsing, state transitions, and actions where applicable.
- Document external tools, permissions, settings, and authentication.
- Run `make check`; run `make lint-lua` when StyLua is installed.
- Do not add generated archives or checksums from `dist/`.

After a package is reviewed and merged, a maintainer creates its first package release. Publication
in the [widget registry](https://github.com/easybar-app/widget-registry) is a separate review step:
new packages need an initial registry entry, while later releases of an existing package are
discovered by the registry automation.
