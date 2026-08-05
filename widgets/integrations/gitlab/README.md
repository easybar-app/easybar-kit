# GitLab Widgets

This package contains the implementation shared by the bundled GitLab entrypoints:

- `../../gitlab.lua` renders assigned work items in a popup.
- `../../gitlab-inbox.lua` publishes assigned work items to the native inbox.

## Requirements

Install and authenticate the GitLab CLI:

```sh
glab auth login
```

The `glab` executable must be available through `[app.env].PATH`. Set `GITLAB_HOST` in `[app.env]` for a self-managed or dedicated GitLab instance.

Only install one presentation variant at a time. The top-level files remain the executable entrypoints; files in this directory are loaded through `require(...)`.
