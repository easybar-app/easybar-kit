# CLI

The `EasyBarCtl` target builds the `easybar` executable.

It is a thin client for the app and agent control sockets, plus a read-only viewer for shared process logs.

## Responsibilities

The CLI translates user commands into typed operations. Its job is to:

- resolve a user-facing command path
- parse only the options belonging to that command
- map socket-backed commands to `IPC.Command`
- connect to the relevant Unix socket
- encode requests and decode typed responses
- report success or failure to the shell
- merge and filter retained logs, then multiplex live app and agent subscriptions through `EasyBarShared`

This keeps automation simple and avoids forcing users to speak the socket protocol manually.

## Command catalog

`CLICommandDescriptor` is the source of truth for the user-facing command hierarchy. Each descriptor contains:

- the canonical command path, such as `config validate`
- the help description
- command-specific options and positional arguments
- the parser behavior for the command
- an `IPC.Command` mapping when the operation uses the main control socket

The same catalog drives command resolution and help output, preventing the parser and usage text from drifting apart.

The wire protocol remains separate. `IPC.Command` is shared by the CLI and socket server, while CLI names and descriptions remain in `EasyBarCtl`. This is intentional: user-facing paths such as `refresh` do not need to match stable protocol values such as `manual_refresh`. Agent commands use agent-specific protocols, while `logs --follow` can use the main control socket and one or both agent sockets at the same time.

## Common commands

```bash
easybar refresh
easybar runtime restart
easybar config reload
easybar config validate
easybar metrics --watch
easybar agent restart calendar
easybar agent restart network
easybar agent restart all
easybar agent version all
easybar event emit workspace_change
easybar logs --widget tailscale --since 30m
easybar inbox list --unread
```

## Design rule

The CLI should stay small.

Most commands use the main EasyBar control socket. Agent restart and version commands contact the
calendar or network socket directly through the shared agent protocol. Version queries therefore
report the processes that are actually running. `easybar logs` reads retained history from the configured log directory. With `--follow`, it then connects to the EasyBar socket and the selected enabled agent sockets; it does not poll files for new records.

The CLI is a transport client, not a second source of application logic.
