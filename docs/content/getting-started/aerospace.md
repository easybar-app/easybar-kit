# AeroSpace Integration

EasyBar automatically keeps its spaces, front-app, and AeroSpace mode widgets current. You do not
need to add EasyBar workspace or focus commands to your AeroSpace config.

## Requirements

EasyBar requires AeroSpace 0.21.0 or newer.

Check your AeroSpace versions with:

```bash
aerospace --version
```

Both the CLI client and the running AeroSpace.app server should be at least 0.21.0. If they differ after updating, restart AeroSpace.app.

## Automatic updates

EasyBar listens for AeroSpace changes while an AeroSpace-backed widget is enabled. Focus and
workspace changes update the bar automatically, and EasyBar reconnects if AeroSpace starts or
restarts later.

Lua widgets can subscribe to the corresponding EasyBar events. See
[Subscribe To Events](../lua/guides/subscribe-to-events.md) for the public event API.

## AeroSpace config

No EasyBar commands are required in your AeroSpace config for normal workspace, focus, or layout
updates.

## Manual refresh

You can always trigger one refresh manually:

```bash
easybar refresh
```

## Troubleshooting

Raise EasyBar logging to debug and look for subscription logs:

```toml
[logging]
enabled = true
level = "debug"
```

Useful log messages include:

- `aerospace subscription started`
- `aerospace subscription event received`
- `aerospace subscription disconnected`
- `aerospace subscription ended`
- `aerospace subscription reconnect scheduled`

If a local script needs to notify widgets about a known state change, use EasyBar scripting events from [Runtime Control](../runtime/control.md).

## Related pages

- [Runtime Control](../runtime/control.md)
- [Troubleshooting](../runtime/troubleshooting.md)
