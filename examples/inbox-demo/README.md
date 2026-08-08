# Inbox Demo Widget

This example publishes representative messages to EasyBar's native shared inbox without requiring external services.

Use the inbox source actions to add or clear the demo snapshot. Items with a Dismiss action briefly show item-scoped activity before they are removed.

The demo uses order `10000` for its source groups and context actions so installed inbox widgets appear before it.

Install it with `make install-widgets` and select `inbox-demo/widget.lua`. The native inbox must be enabled for the messages to be visible.
