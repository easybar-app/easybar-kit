# CLI Reference

The `easybar` command controls the running app, validates configuration, restarts helper agents, manages native inbox messages, and exposes diagnostics. Commands that operate on the app use its Unix control socket. Agent commands contact the selected helper-agent socket directly. `easybar logs` reads retained history and can subscribe to live records from the selected running processes.

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
easybar refresh --help
easybar inbox --help
easybar inbox send --help
easybar config --help
easybar logs --help
```

## `easybar refresh`

Refresh the bar, native widgets, Lua widgets, and agent-backed data without reloading configuration or restarting the Lua runtime.

```bash
easybar refresh
```

The command also emits `easybar.events.forced` to subscribed Lua widgets so they can refresh immediately.

Use this when the loaded configuration is already correct and only the displayed or agent-backed state needs to be updated. See [Runtime Control](control.md#refresh) for the difference between refresh, reload, and restart operations.

## `easybar logs`

Read retained logs or follow live process records. See [Logs](logs.md) for filters, live subscriptions,
JSON output, rotation behavior, and examples.

## `easybar metrics`

Inspect one runtime snapshot or open the rolling terminal dashboard. See [Metrics](metrics.md) for
included fields, rate behavior, and watch-mode display details.

## `easybar inbox`

Publish and manage native inbox messages from local scripts. See [Inbox](inbox.md) for every inbox
subcommand, option, and persistence rule.

## `easybar config`

Reload or validate EasyBar configuration. Run `easybar config --help` to list the available subcommands.

### `easybar config reload`

Read `config.toml` from disk and rebuild EasyBar using the updated configuration.

```bash
easybar config reload
```

A rejected reload leaves the last valid configuration active. Use this command after changing the active config when automatic config watching is disabled or when an explicit reload is needed. See [Runtime Control](control.md#reload-config).

### `easybar config validate`

Ask the running app to validate configuration without applying it.

Validate the active configuration:

```bash
easybar config validate
```

Validate another file:

```bash
easybar config validate --config /path/to/config.toml
```

| Option          | Purpose                                                 |
| --------------- | ------------------------------------------------------- |
| `--config PATH` | Validate this file instead of the active configuration. |

`EASYBAR_CONFIG_PATH` can also select the active configuration file.

## `easybar runtime`

Manage the separate Lua widget runtime. Run `easybar runtime --help` to list the available subcommands.

### `easybar runtime restart`

Restart only the Lua widget runtime using the currently loaded EasyBar configuration.

```bash
easybar runtime restart
```

The command stops the current Lua process, starts a fresh one, reloads Lua widget files, and resets Lua-side widget state. It does not reread `config.toml` from disk. See [Runtime Control](control.md#restart-lua-runtime).

## `easybar agent`

Manage the running calendar and network helper agents. Run `easybar agent --help`, `easybar agent restart --help`, or `easybar agent version --help` to inspect the available targets.

### `easybar agent restart calendar`

Request a calendar-agent restart through its socket.

```bash
easybar agent restart calendar
```

The agent acknowledges the request before exiting. Its Homebrew keep-alive service then launches it again. `--socket PATH` can override the calendar-agent socket for this command.

### `easybar agent restart network`

Request a network-agent restart through its socket.

```bash
easybar agent restart network
```

The agent acknowledges the request before exiting. Its Homebrew keep-alive service then launches it again. `--socket PATH` can override the network-agent socket for this command.

### `easybar agent restart all`

Attempt to restart both helper agents and report partial failures.

```bash
easybar agent restart all
```

The command exits nonzero when either request fails. It does not accept `--socket` because the calendar and network agents use different sockets.

### `easybar agent version calendar`

Query the running calendar agent's application and protocol versions.

```bash
easybar agent version calendar
easybar agent version calendar --json
```

A single-agent version command accepts `--socket PATH` and `--json`.

### `easybar agent version network`

Query the running network agent's application and protocol versions.

```bash
easybar agent version network
easybar agent version network --json
```

A single-agent version command accepts `--socket PATH` and `--json`.

### `easybar agent version all`

Show the EasyBar CLI version and query both running helper agents.

```bash
easybar agent version all
easybar agent version all --json
```

Example text output:

```text
EasyBar: 0.23.0 (protocol 2)
Calendar agent: 0.23.0 (protocol 2)
Network agent: 0.23.0 (protocol 2)
```

Version queries report the processes that are actually running rather than inspecting binaries on disk. A selected agent that is unreachable or returns an invalid response causes a nonzero exit status. A version or protocol difference is shown with `[mismatch]` and `matches_easybar: false`, but the query itself still succeeds.

The combined command accepts `--json` but not `--socket` because it needs two different agent sockets. `easybar --version` remains the short command for the CLI alone.

## `easybar event`

Emit scripting events into the running EasyBar app. Run `easybar event --help` for the available subcommands.

### `easybar event emit`

Emit one supported EasyBar driver event and refresh the corresponding current state.

```bash
easybar event emit workspace_change
easybar event emit focus_change
easybar event emit space_mode_change
```

Hyphens and underscores are accepted in event names. Use this from local scripts when an external action should notify Lua widgets that workspace, focus, or layout-related state may have changed.

## Global options

| Option                | Purpose                                                 |
| --------------------- | ------------------------------------------------------- |
| `--socket PATH`, `-s` | Override the socket contacted by a supported operation. |
| `--debug`, `-d`       | Print CLI diagnostics without changing app log levels.  |
| `--version`, `-v`     | Print the installed CLI version.                        |
| `--help`, `-h`        | Print root, group, or command-specific usage.           |

Command-specific options such as `--config`, `--watch`, inbox fields, and log filters appear only in the relevant command's help.

`--socket` is not accepted by `easybar logs`, `easybar agent restart all`, or `easybar agent version all`. Log streaming resolves the selected process sockets from shared runtime configuration, while each combined agent operation needs two different helper-agent sockets. Use a single-agent command when diagnosing one explicit agent socket.

## Socket resolution failures

Without `--socket`, the CLI resolves control and helper-agent sockets from the same shared runtime configuration used by EasyBar and its agents. A missing config file is valid and uses built-in defaults. A present but malformed config is reported directly; the CLI does not silently fall back to another socket.

Use an explicit socket to diagnose or recover while the shared config is malformed:

```bash
easybar refresh --socket ~/.local/state/easybar/runtime/easybar.sock
easybar agent restart calendar --socket ~/.local/state/easybar/runtime/calendar-agent.sock
```

With `--debug`, the CLI reports whether each socket came from `--socket` or the shared config file. Combined agent operations cannot bypass config resolution because they need two different agent sockets.

The CLI and running app versions should normally match after a Homebrew upgrade:

```bash
easybar --version
/Applications/EasyBar.app/Contents/MacOS/EasyBar --version
```

## Related pages

- [Runtime Control](control.md)
- [Metrics](metrics.md)
- [Logs](logs.md)
- [Inbox](inbox.md)
- [Logging configuration](../configuration/logging.md)
- [Native Inbox for Lua](../lua/guides/inbox.md)
- [Control Socket](../internals/architecture/control-socket.md)
