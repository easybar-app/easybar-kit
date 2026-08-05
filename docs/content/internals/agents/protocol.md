# Agent Protocol

Both agents share the same transport and baseline command flow.

## Socket paths

By default, agent sockets are derived from `[app].runtime_dir`:

- calendar agent: `<runtime_dir>/calendar-agent.sock`
- network agent: `<runtime_dir>/network-agent.sock`

The default runtime directory is `~/.local/state/easybar/runtime`. `EASYBAR_RUNTIME_DIR` can override it for all EasyBar processes.

EasyBar connects to those sockets directly.

Other local clients can also connect when they speak the same protocol.

## Transport format

- newline-delimited JSON
- one request per line
- one response per line

Example:

```json
{ "command": "ping" }
```

## Common commands

Common commands include:

- `ping`
- `version`
- `fetch`
- `subscribe`
- `logs`
- `restart`

`version` returns the running binary version and the shared EasyBar IPC protocol version:

```json
{
  "kind": "version",
  "version": {
    "appVersion": "0.4.0",
    "protocolVersion": "2"
  }
}
```

`appVersion` identifies the installed EasyBar build. `protocolVersion` identifies the internal JSON socket contract shared by the app and helper agents.

The calendar agent additionally supports:

- `create_event`
- `update_event`
- `delete_event`

Every response includes a `kind` field.

Common kinds include:

- `pong`
- `version`
- `subscribed`
- `log_subscribed`
- `log_record`
- `restarting`
- `error`

Error responses may include a stable `errorCode` in addition to the human-readable `message`. The
calendar agent uses `invalid_request` when a decoded request violates protocol limits, including its
maximum 366-day date range.

## Live log subscriptions

Both agents accept a `logs` request carrying the same optional filters as the EasyBar control socket:

```json
{
  "command": "logs",
  "logSubscription": {
    "runtime": "agent",
    "minimum_level": "trace"
  }
}
```

The agent acknowledges the subscription with `log_subscribed`. Each matching record is then sent as a `log_record` message. The requested level is independent from `[logging].level`: records needed only by the live client are not written to the retained agent log. Slow clients cannot block the agent because delivery uses a bounded serial queue; an overflowing client is disconnected.

## Request correlation

Calendar requests may include an optional `requestID`. The calendar agent echoes that identifier in
every direct response produced by the request, including `subscribed`, `snapshot`, success, and
`error` messages. Broadcast snapshots caused by EventKit changes are unsolicited and omit it.

EasyBar uses the identifier to reject delayed errors or snapshots from an older subscription. The
client retains a FIFO fallback for older agents that do not yet echo request identifiers.

## Typical behavior

- `ping`
  returns one `pong`, then closes
- `version`
  returns one version payload, then closes
- `fetch`
  returns one data payload, then closes
- `subscribe`
  returns one `subscribed`, returns one immediate data payload, then keeps the socket open for later pushes
- `logs`
  returns one `log_subscribed`, then keeps the socket open and streams matching `log_record` payloads through a bounded per-client queue
- `restart`
  returns one `restarting` acknowledgement, closes the request socket, then exits the agent process cleanly

## Reconnect behavior

Transport failures such as an unavailable socket or an unexpected disconnect are transient. EasyBar
reconnects long-lived subscriptions with bounded backoff.

A structured calendar `invalid_request` response is different: the connection worked, but retrying
the same subscription cannot succeed. EasyBar therefore:

1. logs the rejection once;
2. suspends reconnects for that exact request;
3. retains the last valid snapshot; and
4. resumes immediately when the request or socket configuration changes.

Other calendar errors follow their normal response handling and do not redefine the shared transport
contract.

## Agent restart flow

Both the calendar and network agents accept the following one-shot request:

```json
{ "command": "restart" }
```

The agent confirms that it accepted the request before terminating:

```json
{ "kind": "restarting" }
```

The full restart sequence is:

1. The client sends `restart` over the agent's Unix socket.
2. The agent sends `restarting` so the client knows the request was accepted.
3. The agent exits through its normal AppKit shutdown path.
4. The service supervisor starts a fresh agent process.
5. EasyBar reconnects when the agent socket becomes available again.

Homebrew Services runs the separately installed agents through `launchd` with `keep_alive`, so an acknowledged exit leads to a fresh process. A manually launched standalone agent has no supervisor and therefore stays stopped after it exits.

Restart is available only while the agent socket is responsive. If the agent has already crashed or cannot answer requests, its service supervisor remains responsible for recovery.

The CLI exposes this operation as `easybar agent restart calendar`, `easybar agent restart network`, and `easybar agent restart all`. The combined command attempts both agents before reporting a partial failure with a nonzero exit status.

## EasyBar command behavior

EasyBar keeps long-lived subscriptions open to the agents for normal runtime updates.

A manual refresh:

```bash
easybar refresh
```

- does not reload config
- does not restart agents
- triggers fresh reads and UI updates

A Lua restart:

```bash
easybar runtime restart
```

- restarts only Lua
- does not restart agents

A config reload:

```bash
easybar config reload
```

- reloads `config.toml`
- rebuilds runtime state
- recreates agent-backed subscriptions
