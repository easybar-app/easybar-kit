# Logging

EasyBar uses one shared log directory for the main app and helper agents.

When file logging is enabled, EasyBar writes:

- `easybar.out`
- `calendar-agent.out`
- `network-agent.out`

Each process log rotates automatically before it grows beyond 10 MiB. EasyBar retains three
numbered archives beside the active file, for example `easybar.out.1` through `easybar.out.3`.
Rotation is a built-in safety limit and does not require additional configuration.

Use the CLI to read the retained files as one timestamp-ordered stream:

```bash
easybar logs
easybar logs --widget tailscale --level debug
easybar logs --since 30m
```

The command prints recent retained history and exits. Add `--follow` to subscribe directly to the running EasyBar app and every enabled helper agent. See the [Logs](../runtime/logs.md) for every filter and output option.

Live follow subscriptions have their own minimum level. They do not change `[logging].level` and do not force additional records into the retained files:

```toml
[logging]
enabled = true
level = "info"
```

```bash
easybar logs --widget brew-inbox --runtime lua --level trace --follow
```

With this combination, the CLI receives matching trace records live, while `easybar.out` continues
to retain only info and higher. The same independent level applies to calendar and network agent
subscriptions.

## Config

```toml
[logging]
enabled = true
level = "info"
directory = "~/.local/state/easybar"
```

## Logging control

| Setting           | Config key          | Environment override |
| ----------------- | ------------------- | -------------------- |
| File logging      | `logging.enabled`   | none                 |
| Minimum log level | `logging.level`     | `EASYBAR_LOG_LEVEL`  |
| Log directory     | `logging.directory` | none                 |

Only the minimum log level has an environment override. File logging and the log directory remain
config-only.

## Change the log level from EasyBar

The shared **Log Level** submenu is available from both native menus:

- hold `Shift` while right-clicking empty bar space
- open the menu bar icon when `[app].develop = true`

Selecting a level writes it to `[logging].level` in the active `config.toml`, preserving comments,
whitespace, and unrelated settings. EasyBar applies the selected level immediately, reloads the
bar runtime when it is running, and keeps the selection active after restart.

When `EASYBAR_LOG_LEVEL` is set, that temporary environment override remains the effective level
for the current process even though the menu selection is persisted for later launches.

## Supported levels

- `trace`
- `debug`
- `info`
- `warn`
- `error`

## Level meaning

- `trace`
  Info, debug, warnings, errors, and very verbose trace logs.
- `debug`
  Info plus debug logs.
- `info`
  Normal runtime logs.
- `warn`
  Warnings and errors only.
- `error`
  Error logs only.

## Notes

The main app and helper agents use the shared logging config from `config.toml`.

`logging.enabled` and `logging.directory` are config-only settings. They are not controlled by environment variables.

`EASYBAR_LOG_LEVEL` is the only logging environment override. It temporarily overrides
`logging.level` for troubleshooting without changing `config.toml`.

`EASYBAR_CONFIG_PATH` remains the public environment override for selecting the runtime config file.

The `easybar` CLI can enable its own debug output explicitly with `--debug`. This does not change the main app or agent log level. In `logs --follow`, `--level` controls only that client's live subscription and output filter.

Structured request logs include both `request_id` and `run_id`. A request ID identifies one operation within a process; the run ID distinguishes it from the same counter value after a restart. `easybar logs --request-id ID` searches every retained app and agent log, while the printed `run_id` exposes any cross-run matches.

## Temporary log-level override

Use `EASYBAR_LOG_LEVEL` when you want more or less verbose logs without editing `config.toml`:

```bash
EASYBAR_LOG_LEVEL=debug easybar refresh
EASYBAR_LOG_LEVEL=trace open /Applications/EasyBar.app
```

This override affects only the minimum log level. File logging still depends on `logging.enabled` and `logging.directory` from `config.toml`.

## CLI debug output

Use `--debug` when you want CLI-side diagnostics:

```bash
easybar metrics --debug
easybar config validate --config /path/to/config.toml --debug
easybar logs --debug --runtime lua
```

This keeps validation explicit:

```bash
easybar config validate --config /path/to/config.toml
```

or:

```bash
EASYBAR_CONFIG_PATH=/path/to/config.toml easybar config validate
```
