# Homebrew Widget

`widget.lua` renders a compact Homebrew status item and a popup for outdated formulae and casks. It supports refresh, update, upgrade, cancellation, warnings, and a conservative manual-upgrade policy.

## Requirements

Homebrew must be available through `[app.env].PATH`.

## Files

- `widget.lua`: standalone bar and popup implementation
- `policy.lua`: manual-upgrade policy shared with the inbox publisher

The alternative native-inbox presentation lives in `../inbox/brew/`. Install only one Homebrew presentation unless duplicate polling is intentional.
