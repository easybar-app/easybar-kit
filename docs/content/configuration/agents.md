# Agents

EasyBar uses two helper agents:

- `easybar-calendar-agent`
- `easybar-network-agent`

Both helper agents are enabled by default.

Agent sockets are derived from `[app].runtime_dir` unless explicitly overridden.

## Calendar agent

```toml
[agents.calendar]
enabled = true
```

The default socket is `calendar-agent.sock` inside `app.runtime_dir`.

Use `socket_path` only when the calendar agent needs a separate location:

```toml
[agents.calendar]
socket_path = "/custom/runtime/calendar-agent.sock"
```

The calendar agent owns EventKit access, calendar permission handling, event snapshots, and event mutations.

## Network agent

```toml
[agents.network]
enabled = true
refresh_interval_seconds = 60
allow_unauthorized_non_sensitive_fields = false
```

The default socket is `network-agent.sock` inside `app.runtime_dir`.

Use `socket_path` only when the network agent needs a separate location:

```toml
[agents.network]
socket_path = "/custom/runtime/network-agent.sock"
```

The network agent owns Wi-Fi and network observation.

## Disable an agent

```toml
[agents.calendar]
enabled = false

[agents.network]
enabled = false
```

When an agent is disabled, its helper app exits immediately without opening its socket.

## Network permission behavior

```toml
[agents.network]
allow_unauthorized_non_sensitive_fields = false
```

When this is `false`, Wi-Fi field requests fail while location permission is denied.

When this is `true`, non-Wi-Fi fields may still be returned without location access.

The default is privacy-first: requests for Wi-Fi fields fail until location access is granted.

## Troubleshooting

Query the versions of both running agents and compare them with EasyBar:

```bash
easybar agent version all
```

Use `easybar agent version calendar` or `easybar agent version network` to query one agent. Add
`--json` when consuming the result from a script.

For agent process checks, socket probes, permission issues, raw field inspection, and Homebrew service logs, use [Debugging Agents](../internals/agents/debugging.md).
