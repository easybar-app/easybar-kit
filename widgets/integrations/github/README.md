# GitHub Widgets

This package contains the implementation shared by the bundled GitHub entrypoints:

- `../../github.lua` renders unread notifications in a popup.
- `../../github-inbox.lua` publishes notifications to the native inbox and supports guarded pull-request merging.

## Requirements

Install and authenticate the GitHub CLI:

```sh
gh auth login
```

The `gh` executable must be available through `[app.env].PATH`.

## Merge method setting

The inbox widget stores the preferred pull-request merge method in `config.toml`:

```toml
[widgets.github-inbox]
merge_method = "squash"
```

Supported values are `merge`, `squash`, and `rebase`. The method can also be changed from the GitHub inbox source menu.

Only install one presentation variant at a time. The top-level files remain the executable entrypoints; files in this directory are loaded through `require(...)`.
