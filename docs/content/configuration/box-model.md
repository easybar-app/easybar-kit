# Box Model

Built-in widgets and native groups use the same shared box-model keys.

## Keys

- `margin_x`
- `margin_y`
- `padding_x`
- `padding_y`
- `spacing`

## Meaning

`margin_x` and `margin_y` control outer spacing around a widget or group.

`padding_x` and `padding_y` control inner spacing inside a widget or group.

`spacing` controls the gap between children inside a group or layout.

## Spaces widget

For the native `spaces` widget:

- `[builtins.spaces]` controls the outer container placement and shared box model.
- `[builtins.spaces.layout]` controls the layout inside each workspace pill.

This keeps outer bar placement separate from workspace button layout.
