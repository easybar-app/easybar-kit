# Tailscale Widget

This package contains the implementation for `../../tailscale.lua`.

The widget displays Tailscale state, toggles the connection with a left click, and manages exit-node selection through the native context menu.

## Requirements

The `tailscale` CLI must be available through `[app.env].PATH`, or `TAILSCALE` may contain an absolute executable path.

The top-level file remains the executable entrypoint; `widget.lua` is loaded through `require(...)`.
