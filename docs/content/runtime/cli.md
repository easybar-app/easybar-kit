# CLI Reference

The `easybar` command controls the running app, validates configuration, restarts helper agents, and exposes diagnostics. Commands that operate on the app use its Unix control socket. Agent commands contact the selected helper-agent socket directly. `easybar logs` reads retained history; follow mode opens live subscriptions to the selected running processes.

## Command structure

EasyBar uses commands for actions and options only to modify those actions:

```text
usage:
  easybar <command> [options]

commands:
  refresh                     Refresh the bar, widgets, and agent-backed data
  logs                        Show retained and live process logs
  metrics                     Show runtime metrics
  inbox                       Manage native inbox messages
  config                      Reload or validate configuration
  runtime                     Manage the Lua widget runtime
  agent                       Manage calendar and network agents
  event                       Emit EasyBar scripting events
```

Run command-specific help when needed:

```bash
easybar inbox --help
easybar inbox send --help
easybar config --help
easybar logs --help
```

## Runtime commands

| Command                   | Purpose                                                                       |
| ------------------------- | ----------------------------------------------------------------------------- |
| `easybar refresh`         | Refresh the bar, widgets, and agent-backed data without reloading config.     |
| `easybar config reload`   | Read `config.toml` again and rebuild the current bar.                         |
| `easybar runtime restart` | Restart only the Lua widget runtime using the currently loaded configuration. |
| `easybar metrics`         | Print one runtime metrics snapshot.                                           |
| `easybar metrics --watch` | Continuously display runtime metrics and rolling graphs.                      |
| `easybar logs`            | Print recent retained logs and exit.                                          |
| `easybar logs --follow`   | Print retained history, then subscribe to matching live process records.      |

See [Runtime Control](control.md) for the difference between refresh, reload, and restart operations. See [Metrics](metrics.md) for the fields included in a snapshot.

## Inbox commands

Local scripts can publish structured notifications directly to the native inbox:

```bash
easybar inbox send \
  --source backup \
  --severity error \
  --title "Backup failed" \
  --message "The nightly MinIO backup failed after 3 attempts." \
  --category "backup:minio" \
  --url "https://grafana.example.com/backup-logs"
```

`--source` and `--title` are required. Severity defaults to `info` and accepts `info`, `success`, `warning`, or `error`. `--category` supplies the category used by category grouping. An HTTP(S) `--url` adds an **Open** action. New messages are unread unless `--read` is supplied.

By default, `send` generates a unique message ID. Use `--id` when a recurring script should update the same notification instead of creating another one:

```bash
easybar inbox send --source backup --id minio-nightly \
  --severity success --title "Backup completed"
```

List currently visible messages without changing their state:

```bash
easybar inbox list
easybar inbox list --source backup --unread
easybar inbox list --json
```

Use explicit mutation commands to change message state:

```bash
easybar inbox mark-read --source backup --id minio-nightly
easybar inbox mark-unread --source backup --id minio-nightly
easybar inbox dismiss --source backup --id minio-nightly
easybar inbox remove --source backup --id minio-nightly
easybar inbox clear --source backup
easybar inbox clear --all
```

Omitting `--id` from `mark-read`, `mark-unread`, or `dismiss` applies the operation to every visible message from the selected source. `remove` requires both `--source` and `--id`. `clear` accepts either `--source` or `--all`, never both.

CLI-published message content remains in memory until cleared or until EasyBar restarts. Local read, unread, and dismissed state is persisted for stable source/ID pairs. See [Native Inbox](../lua/guides/inbox.md) for the complete inbox model.

## Logs

`easybar logs` merges the main app, calendar-agent, and network-agent history in timestamp order. By default it prints the latest 100 matching retained entries and exits. Add `--follow` or `-f` to subscribe directly to the EasyBar control socket and the sockets of every enabled agent selected by the runtime filter.

```bash
easybar logs
easybar logs --follow
easybar logs --widget tailscale --runtime lua --level debug
easybar logs --runtime app --since 30m
easybar logs --request-id lua-19 --json
```

`--request-id` and `--since` search all matching retained history by default. Use `--lines` to limit that history explicitly. Request-correlated entries also carry a `run_id`, which distinguishes repeated request IDs from different EasyBar process runs.

| Option                | Purpose                                                                   |
| --------------------- | ------------------------------------------------------------------------- |
| `--widget NAME`       | Match a Lua or native widget name.                                        |
| `--runtime KIND`      | Match `app`, `lua`, or `agent`.                                           |
| `--level LEVEL`       | Match the selected severity and higher; in follow mode this is also the live subscription level. |
| `--request-id ID`     | Match one request across every retained process log.                      |
| `--since TIME`        | Match entries since a duration such as `30m` or an ISO-8601 timestamp.    |
| `--lines COUNT`, `-n` | Limit the latest matching retained history.                               |
| `--all`               | Print all matching retained history.                                      |
| `--follow`, `-f`      | Continue following new matching entries after retained history.           |
| `--json`              | Emit JSON Lines with parsed fields, source, runtime, and widget metadata. |

Filters compose. This prints errors from the Lua runtime during the last hour and exits:

```bash
easybar logs --runtime lua --level error --since 1h
```

This prints the same retained history and then follows new matches:

```bash
easybar logs --runtime lua --level error --since 1h --follow
```

In follow mode, the requested level is independent from `[logging].level`. For example, the app can keep `level = "info"` for stdout and retained files while one CLI client subscribes at `trace`:

```bash
easybar logs --widget brew-inbox --runtime lua --level trace --follow
```

Trace and debug records requested only by a live subscriber are streamed to that client and are not added to the process log file. Each process gives every client a bounded serial socket queue. Logging never waits for the client to read; a stalled or overflowing subscriber is disconnected. Follow mode does not fall back to file polling: when any requested running-process socket is unavailable or closes, the command reports that error and exits. Disabled agents are omitted from an unfiltered or `--runtime agent` subscription.

`--socket` can override the EasyBar control socket only when following `--runtime lua` or `--runtime native`. Agent and unfiltered follow mode use the configured process socket paths because they may require more than one connection.

History is limited to the active files and numbered archives retained by EasyBar's rotation policy. `--all` means all retained history, not logs that have already rotated out.

## Helper-agent commands

| Command                          | Purpose                                                  |
| -------------------------------- | -------------------------------------------------------- |
| `easybar agent version calendar` | Query the running calendar agent version.                |
| `easybar agent version network`  | Query the running network agent version.                 |
| `easybar agent version all`      | Show EasyBar and both running agent versions.            |
| `easybar agent restart calendar` | Restart the calendar agent through its socket.           |
| `easybar agent restart network`  | Restart the network agent through its socket.            |
| `easybar agent restart all`      | Attempt both agent restarts and report partial failures. |

Version commands query the running processes rather than inspecting binaries on disk. They include
the shared agent-protocol version and mark a result when it does not match the current EasyBar CLI:

```text
EasyBar: 0.23.0 (protocol 2)
Calendar agent: 0.23.0 (protocol 2)
Network agent: 0.23.0 (protocol 2)
```

Use `--json` for scripts and diagnostics:

```bash
easybar agent version all --json
```

`easybar --version` remains the short command for the EasyBar CLI alone. A version command exits
nonzero when a selected agent is unreachable or returns an invalid response. A different version is
shown with `[mismatch]` and `matches_easybar: false`, but the query itself still succeeds.

The agent acknowledges its restart request before exiting. Its Homebrew keep-alive service then launches it again. `--socket` can override the calendar or network socket for a single-agent restart. It cannot be used with `agent restart all`, because that operation needs two different sockets.

## Configuration validation

Validate the active configuration through the running app:

```bash
easybar config validate
```

Validate another file:

```bash
easybar config validate --config /path/to/config.toml
```

`EASYBAR_CONFIG_PATH` can select the file instead. A rejected live reload leaves the last valid configuration active.

## Scripting events

```bash
easybar event emit workspace_change
easybar event emit focus_change
easybar event emit space_mode_change
```

Hyphens and underscores are accepted in event names. These commands emit driver events for Lua widgets and refresh the corresponding current state.

## Global options

| Option                | Purpose                                                  |
| --------------------- | -------------------------------------------------------- |
| `--socket PATH`, `-s` | Override the socket contacted by the selected operation. |
| `--debug`, `-d`       | Print CLI diagnostics without changing app log levels.   |
| `--version`, `-v`     | Print the installed CLI version.                         |
| `--help`, `-h`        | Print root, group, or command-specific usage.            |

Command-specific options such as `--config`, `--watch`, inbox fields, and log filters appear only in the relevant command's help.

## Socket resolution failures

Without `--socket`, the CLI resolves control and helper-agent sockets from the same shared runtime configuration used by EasyBar and its agents. A missing config file is valid and uses built-in defaults. A present but malformed config is an error and is reported directly; the CLI does not silently fall back to another socket.

Use an explicit socket to diagnose or recover while the shared config is malformed:

```bash
easybar refresh --socket ~/.local/state/easybar/runtime/easybar.sock
easybar agent restart calendar --socket ~/.local/state/easybar/runtime/calendar-agent.sock
```

With `--debug`, the CLI reports whether each socket came from `--socket` or the shared config file.
Agent operations targeting `all` cannot bypass config resolution because they need two different
agent sockets.

The CLI and running app versions should normally match after a Homebrew upgrade:

```bash
easybar --version
/Applications/EasyBar.app/Contents/MacOS/EasyBar --version
```

## Related pages

- [Runtime Control](control.md)
- [Metrics](metrics.md)
- [Logging](../configuration/logging.md)
- [Control Socket](../internals/architecture/control-socket.md)
