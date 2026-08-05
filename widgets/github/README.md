# GitHub Widget

`widget.lua` displays GitHub notifications in a standalone popup.

## Requirements

Install and authenticate the GitHub CLI:

```sh
gh auth login
```

The `gh` executable must be available through `[app.env].PATH`.

The alternative native-inbox presentation lives in `../inbox/github/`. It adds item actions and guarded pull-request merging. Install only one GitHub presentation unless duplicate polling is intentional.
