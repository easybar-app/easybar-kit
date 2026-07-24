# Privacy Spacer

EasyBar provides invisible native spacers that reserve a fixed amount of bar width. They are useful
when the macOS privacy indicator or another system element would otherwise overlap the final widget,
or when you want an intentional gap between widgets.

## Predefined privacy spacer

The predefined spacer is the convenient system-edge instance:

```toml
[builtins.privacy_spacer]
enabled = true
position = "right"
order = 1000
width = 22
```

It is the only spacer shown under **Native Widgets → Privacy Spacer**. Toggling that menu item writes
`builtins.privacy_spacer.enabled` just like the other top-level native widgets.

The default `order = 1000` places it after ordinary right-side widgets, shifting the remaining bar
content to the left. EasyBar does not detect whether the macOS privacy indicator is visible, so the
configured width is always reserved while the spacer is enabled.

## Additional named spacers

Declare any number of additional spacers below `builtins.spacers`. The section name is the spacer's
identifier and must be unique:

```toml
[builtins.spacers.before_clock]
enabled = true
position = "right"
order = 55
width = 8

[builtins.spacers.after_inbox]
enabled = true
position = "right"
order = 10
width = 12
```

Named spacers are intentionally config-only. They do not appear individually in **Native Widgets**,
which keeps that menu compact. Edit or remove their TOML sections to manage them.

Each named spacer supports:

- `enabled`: enables or disables that spacer; defaults to `true` when the section exists
- `position`: `left`, `center`, or `right`
- `order`: placement among other widgets in the same position
- `group`: optional native group id
- `width`: reserved width from `1` through `100` points; defaults to `8`

All named spacers use the same native renderer as the predefined privacy spacer. They have no text,
icon, hover behavior, popup, or action surface.

## Suggested widths

Use around `22` points for the macOS privacy indicator. Smaller values such as `6`–`12` points work
well for visual separation between widgets.
