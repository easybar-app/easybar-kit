# Homebrew Inbox Widget

`widget.lua` publishes outdated Homebrew formulae and casks to the native inbox. Source actions support refresh, `brew update`, automatic upgrades, and cancellation. Package actions can upgrade one eligible item.

## Requirements

Homebrew must be available through `[app.env].PATH`, and the native inbox must be enabled.

The widget reuses `../../brew/policy.lua` so packages requiring manual handling remain visible but are not upgraded automatically.

The standalone popup presentation lives in `../../brew/`. Install only one Homebrew presentation unless duplicate polling is intentional.
