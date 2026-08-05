# GitLab Widgets

This package contains the implementation shared by the bundled GitLab entrypoints:

- `../../gitlab.lua` renders assigned work items in a popup.
- `../../gitlab-inbox.lua` publishes assigned work items to the native inbox and supports guarded merge-request merging.

## Requirements

Install and authenticate the GitLab CLI:

```sh
glab auth login
```

The `glab` executable must be available through `[app.env].PATH`. Set `GITLAB_HOST` in `[app.env]` for a self-managed or dedicated instance.

## Merge method setting

The inbox widget stores the preferred merge-request method in `config.toml`:

```toml
[widgets.gitlab-inbox]
merge_method = "merge"
```

Supported values are `merge`, `squash`, and `rebase`. `merge` uses the project's configured merge strategy. The method can also be changed from the GitLab inbox source menu.

Before merging, the widget retrieves the current merge-request state, rejects blocked requests, and asks for confirmation. The merge command matches the inspected source-branch SHA and disables GitLab CLI auto-merge so a blocked or running pipeline is not silently scheduled for later.

Only install one presentation variant at a time. The top-level files remain the executable entrypoints; files in this directory are loaded through `require(...)`.
