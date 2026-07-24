# Privacy spacer

The privacy spacer is an invisible, fixed-width native widget placed at the far right by default. It
permanently reserves room for macOS privacy indicators so camera, microphone, screen-recording, and
system-audio indicators do not overlap the final visible widget.

```toml
[builtins.privacy_spacer]
enabled = true
position = "right"
order = 1000
width = 12
```

The predefined spacer supports `enabled`, `position`, `order`, `group`, and `width`. It has no icon,
text, hover state, popup, or action surface. While enabled, it always reserves its configured width.
Automatic resizing is intentionally not supported because public macOS APIs do not provide one
reliable system-wide activity feed covering every privacy indicator and their exact display timing.

Set `enabled = false` to remove the reserved area. Increase `width` when the system indicator still
crowds the final widget. The accepted range is `1` through `100` points.

## Capture events for Lua

The fixed spacer does not subscribe to capture events. Camera and microphone events remain available
to Lua widgets through the demand-driven capture source:

- `easybar.events.capture_devices_changed`
- `easybar.events.capture_activity_changed`
- `easybar.events.camera_activity_changed`
- `easybar.events.microphone_activity_changed`

The source starts only while a Lua widget subscribes to one of these events. When a subscription is
first added, EasyBar emits its current snapshot for that event. Every subsequent event includes
`event.capture` with aggregate activity flags plus the connected camera and microphone arrays.

```lua
widget:subscribe(easybar.events.capture_activity_changed, function(event)
    local capture = event.capture
    if capture and capture.active then
        widget:set({ label = "Recording" })
    else
        widget:set({ label = "" })
    end
end)
```

These events represent camera and microphone device activity. They do not claim to detect unrelated
applications performing screen-only recording. See [Events](../../lua/reference/events.md) for the
complete payload fields.

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

Named spacers are config-only and do not appear individually in **Native Widgets**. Each named spacer
supports `enabled`, `position`, `order`, `group`, and `width`, and always reserves its configured width
while enabled.

## Suggested widths

The default privacy width is `12` points. Smaller values such as `6`–`12` points also work well for
visual separation between widgets.
