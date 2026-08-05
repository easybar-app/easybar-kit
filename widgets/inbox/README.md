# Inbox Widgets

This directory contains examples that publish structured snapshots to EasyBar's native shared inbox.

- `demo/widget.lua` publishes representative local test messages.
- `brew/widget.lua` publishes outdated Homebrew packages and update actions.
- `github/widget.lua` publishes GitHub notifications and guarded pull-request actions.
- `gitlab/widget.lua` publishes assigned GitLab work and guarded merge-request actions.

Each service package has its own README. The service names intentionally also exist at the top level because those directories contain standalone popup presentations.

Install only one presentation for Homebrew, GitHub, or GitLab unless duplicate polling is intentional. The native inbox must be enabled for these publishers to be visible.
