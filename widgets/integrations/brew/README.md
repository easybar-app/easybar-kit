# Homebrew Widgets

This package contains the implementation shared by the bundled Homebrew entrypoints:

- `../../brew.lua` renders an icon and popup.
- `../../brew-inbox.lua` publishes Homebrew updates to the native inbox.

## Requirements

Homebrew must be available through `[app.env].PATH`.

## Modules

- `widget.lua`: popup implementation
- `inbox.lua`: native-inbox implementation
- `policy.lua`: manual-upgrade policy used by both variants

Only install one presentation variant at a time. The top-level files remain the executable entrypoints; files in this directory are loaded through `require(...)`.
