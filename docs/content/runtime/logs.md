# Logs

The `easybar logs` command prints retained process logs and can continue with matching live records.

```bash
easybar logs
easybar logs --follow
easybar logs --widget tailscale --runtime lua --level debug
easybar logs --runtime app --since 30m
easybar logs --request-id lua-19 --json
```

Without `--follow`, the command merges retained main-app, calendar-agent, and network-agent history in timestamp order, prints the latest 100 matching entries by default, and exits.

With `--follow`, EasyBar subscribes before printing retained history so records produced during startup are not missed. It then suppresses any overlap between the retained and live streams. The selected runtime filter determines which process sockets are contacted.

| Option                | Purpose                                                                                          |
| --------------------- | ------------------------------------------------------------------------------------------------ |
| `--widget NAME`       | Match a Lua or native widget name.                                                               |
| `--runtime KIND`      | Match `app`, `lua`, or `agent`.                                                                  |
| `--level LEVEL`       | Match `trace`, `debug`, `info`, `warn`, or `error` and higher. In follow mode, also set the live subscription level. |
| `--request-id ID`     | Match one request across every retained process log.                                             |
| `--since TIME`        | Match entries since a duration such as `30m` or an ISO-8601 timestamp.                            |
| `--lines COUNT`, `-n` | Limit the latest matching retained history to a positive number of entries.                      |
| `--all`               | Print all matching retained history.                                                             |
| `--follow`, `-f`      | Continue with new matching records after retained history.                                       |
| `--json`              | Emit JSON Lines with parsed fields, source, runtime, and widget metadata.                         |

Filters compose. This prints errors from the Lua runtime during the last hour and exits:

```bash
easybar logs --runtime lua --level error --since 1h
```

This prints the same retained history and then follows new matches:

```bash
easybar logs --runtime lua --level error --since 1h --follow
```

In follow mode, the requested level is independent from `[logging].level`. For example, the app can retain `info` and higher while one CLI client subscribes at `trace`:

```bash
easybar logs --widget brew-inbox --runtime lua --level trace --follow
```

Trace and debug records requested only by a live subscriber are streamed to that client and are not added to the process log file. Disabled agents are omitted from an unfiltered or `--runtime agent` live subscription. If a requested running process becomes unavailable, the command reports the error and exits.

History is limited to the active files and numbered archives retained by EasyBar's rotation policy. `--all` means all retained history, not records that have already rotated out.

## Related pages

- [Logging configuration](../configuration/logging.md)
- [CLI Reference](cli.md)
- [Troubleshooting](troubleshooting.md)
