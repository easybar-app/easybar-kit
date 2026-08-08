# Widget Packages

EasyBar can install a package by its registry name, from a local directory, or from a direct archive. The [official registry](https://github.com/easybar-app/widget-registry) is a metadata-only catalog for discovery and dependency resolution; package source and release archives remain in their owning repositories. A package does not need to be published in a registry.

## Install an official package

Use a bare package name to resolve the latest immutable release from the official registry. Source for the official packages lives in the separate [widgets repository](https://github.com/easybar-app/widgets):

```bash
easybar widgets install caffeinate
easybar config reload
```

Registry releases contain a versioned archive URL and SHA-256. EasyBar verifies the digest before extracting the archive. Dependencies such as the official `shared` library are installed automatically from the registry when they are not already present at a compatible version.

Use another registry index when needed:

```bash
easybar widgets install my-widget --registry https://example.com/easybar/index.json
```

The registry index may also be a local `index.json` path.

## Install a self-created package

A local package only needs a `package.toml`; it does not need a Git repository or registry entry:

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
