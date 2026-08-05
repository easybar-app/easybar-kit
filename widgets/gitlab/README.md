# GitLab Widget

`widget.lua` displays assigned GitLab issues and merge requests in a standalone popup.

## Requirements

Install and authenticate the GitLab CLI:

```sh
glab auth login
```

The `glab` executable must be available through `[app.env].PATH`. Set `GITLAB_HOST` in `[app.env]` for a self-managed or dedicated GitLab instance.

The alternative native-inbox presentation lives in `../inbox/gitlab/`. It adds item actions and guarded merge-request merging. Install only one GitLab presentation unless duplicate polling is intentional.
