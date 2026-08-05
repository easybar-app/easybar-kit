# GitHub Inbox Widget

`widget.lua` publishes GitHub notifications to the native inbox and supports marking notifications read, refreshing, and guarded pull-request merging.

## Requirements

Authenticate the GitHub CLI and make `gh` available through `[app.env].PATH`:

```sh
gh auth login
```

## Merge settings

```toml
[widgets.github-inbox]
merge_method = "squash"
confirm_merge = false
```

Supported methods are `merge`, `squash`, and `rebase`. `confirm_merge = false` performs the merge after the readiness check; set it to `true` to require a second action. Both settings can also be changed from the inbox source menu.

The standalone popup presentation lives in `../../github/`.
