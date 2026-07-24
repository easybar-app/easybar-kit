# Privacy Spacer

The native privacy spacer reserves an invisible strip at one edge of the EasyBar window. It is
useful when a macOS privacy indicator appears near the right edge and would otherwise overlap the
last EasyBar widget.

```toml
[builtins.privacy_spacer]
enabled = true
position = "right"
order = 1000
width = 22
```

`width` is measured in points and accepts values from `1` through `100`. The default `order = 1000`
places the spacer after ordinary right-side widgets, so the remaining content is shifted to the
left.

## Behavior

The spacer has a fixed width while enabled. EasyBar does not attempt to detect whether the privacy
indicator is currently visible, so enabling the spacer permanently reserves the configured amount
of room until it is disabled again.

Enable or disable it in either of these ways:

- set `builtins.privacy_spacer.enabled` in `config.toml`
- open **Native Widgets → Privacy Spacer** from the EasyBar menu

The spacer participates in the same native placement and ordering system as other built-ins. Its
default position is `right`, but it can be placed on any bar side.

## Suggested width

Start with `22`. Increase it if the final widget still overlaps the indicator, or reduce it when you
want a smaller permanent gap.
