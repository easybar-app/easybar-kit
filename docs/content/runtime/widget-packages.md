# Widget Packages

EasyBar can install a package by its registry name, from a local directory, or from a direct archive. The [official registry](https://github.com/easybar-app/widget-registry) is a metadata-only catalog for discovery and dependency resolution; package source and release archives remain in their owning repositories. A package does not need to be published in a registry.

## Install an official package

Use a bare package name to resolve the latest immutable release from the official registry. Source for the official packages lives in the separate [widgets repository](https://github.com/easybar-app/widgets):

```bash
easybar widgets install PACKAGE_NAME
easybar config reload
```

Registry releases contain a versioned archive URL and SHA-256. EasyBar verifies the digest before extracting the archive. Dependencies such as the official `shared` library are installed automatically from the registry when they are not already present at a compatible version.

Installing an already installed package is an error. Use `widgets update` for a normal registry
upgrade, or explicitly replace a package from any supported source with:

```bash
easybar widgets install PACKAGE_NAME --force
```

A forced install moves the current managed package state aside before replacing it. EasyBar removes
that backup only after the new package is installed successfully; if downloading, resolving, or
installing fails, it restores the previous state.

Use another registry index when needed:

```bash
easybar widgets install my-widget --registry https://example.com/easybar/index.json
```

The registry index may also be a local `index.json` path.

## Search a registry

List every package in the official registry or filter by name, description, kind, or category:

```bash
easybar widgets search
easybar widgets search QUERY
```

Search another remote or local registry with the same source syntax used by installation:

```bash
easybar widgets search QUERY --registry https://example.com/easybar/index.json
```

The live search results are the package catalog; the documentation does not maintain a duplicate
list.

## List installed packages

Read the local package database and show every installed widget and library with its version:

```bash
easybar widgets installed
```

Filter by package kind or request machine-readable output:

```bash
easybar widgets installed --widgets-only
easybar widgets installed --libraries-only
easybar widgets installed --json
```

This command is offline and reports the versions recorded in
`~/.local/share/easybar/packages/installed.json`.

## Check for and install updates

List newer registry releases for installed packages without changing anything:

```bash
easybar widgets outdated
```

Update one package or every outdated package, then reload EasyBar:

```bash
easybar widgets update PACKAGE_NAME
easybar widgets update --all
easybar config reload
```

Pass `--registry` to any of these commands to use another remote or local registry. Updates only
apply to packages whose recorded installation source matches a release in that registry. Locally
created packages and packages installed from unrelated archives are never replaced by `update
--all`.

## Install a self-created package

Use the [EasyBar widget template](https://github.com/easybar-app/widget-template) for a standalone,
release-ready widget repository. A local package only needs a `package.toml`; it does not need a Git
repository or registry entry:

```bash
easybar widgets install ./my-widget --no-registry
```

The minimum widget manifest is:

```toml
manifest_version = 1
name = "my-widget"
version = "0.1.0"
kind = "widget"
entrypoint = "widget.lua"
```

A reusable Lua library declares exports instead of an entrypoint:

```toml
manifest_version = 1
name = "retry-kit"
version = "1.0.0"
kind = "library"

[exports]
retry = "retry.lua"
```

Install the library and use the normal local Lua binding in a widget:

```lua
local retry = require("retry")
```

Dependencies are package names with exact or caret constraints:

```toml
[dependencies]
retry-kit = "^1.0.0"
```

With `--no-registry`, each dependency must already be installed. Without that option, EasyBar checks installed packages first and asks the selected registry only for missing or incompatible dependencies. This lets private packages depend on other private packages without publishing either one: install the library first, then the widget.

## Install an archive directly

Local archives may be installed by path:

```bash
easybar widgets install ./my-widget-0.1.0.tar.gz
```

A remote archive requires an explicit SHA-256:

```bash
easybar widgets install \
  https://example.com/my-widget-0.1.0.tar.gz \
  --sha256 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

The archive must place `package.toml` at its root. Symbolic links, absolute paths, and parent-directory traversal are rejected.

## Install location

All packages install into EasyBar's managed data directory, whether they come from the official registry, another registry, a local directory, or an archive:

```text
~/.local/share/easybar/packages/
├── installed.json
├── store/
│   └── <name>/
│       └── <version>/
└── active/
    ├── <widget-name>/
    └── shared/
```

`store/` keeps the complete versioned package source. `active/` contains only activated widget files and declared library exports. EasyBar loads this managed activation directory in addition to the manual `[app].widgets_dir`.

The configured `widgets_dir` is reserved for Lua files you manage yourself. Package installation never writes new files there. If EasyBar finds the previous package layout below `<widgets_dir>/.easybar` during an install, it migrates those package-owned files into the managed data directory and leaves unrelated manual widgets untouched.

## Uninstall a package

Remove a package and its managed active files with:

```bash
easybar widgets uninstall PACKAGE_NAME
easybar config reload
```

EasyBar refuses to remove a package while another installed package depends on it. Dependencies
that become unused are left installed so removal is always explicit. Manually managed files in
`[app].widgets_dir` are never removed.
