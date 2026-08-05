# Inbox

Manage structured messages in the native inbox. Run `easybar inbox --help` to list the available subcommands.

CLI-published message content remains in memory until it is cleared or EasyBar restarts. Local read, unread, and dismissed state is persisted for stable source and ID pairs. See [Native Inbox](../lua/guides/inbox.md) for the complete inbox model.

## `easybar inbox send`

Add a new native inbox message or update an existing message with the same source and stable ID.

```bash
easybar inbox send \
  --source backup \
  --severity error \
  --title "Backup failed" \
  --message "The nightly MinIO backup failed after 3 attempts." \
  --category "backup:minio" \
  --url "https://grafana.example.com/backup-logs"
```

`--source` and `--title` are required. Severity defaults to `info` and accepts `info`, `success`, `warning`, or `error`. An HTTP(S) URL adds an **Open** action. New messages are unread unless `--read` is supplied.

By default, the command generates a unique message ID. Supply `--id` when a recurring script should update the same notification:

```bash
easybar inbox send \
  --source backup \
  --id minio-nightly \
  --severity success \
  --title "Backup completed"
```

| Option             | Required | Purpose                                                      |
| ------------------ | -------- | ------------------------------------------------------------ |
| `--source NAME`    | Yes      | Set the publisher source.                                    |
| `--title TEXT`     | Yes      | Set the message title.                                       |
| `--id ID`          | No       | Use a stable message identifier instead of a generated UUID. |
| `--message TEXT`   | No       | Set the message body.                                        |
| `--severity LEVEL` | No       | Set `info`, `success`, `warning`, or `error`.                |
| `--category NAME`  | No       | Set the value used by inbox category grouping.               |
| `--url URL`        | No       | Add an HTTP(S) URL opened by the message action.             |
| `--read`           | No       | Create or update the message in the read state.              |

## `easybar inbox list`

List currently visible messages without changing their state.

```bash
easybar inbox list
easybar inbox list --source backup
easybar inbox list --source backup --unread
easybar inbox list --json
```

| Option          | Purpose                             |
| --------------- | ----------------------------------- |
| `--source NAME` | Match one publisher source.         |
| `--unread`      | Return only unread messages.        |
| `--json`        | Print machine-readable JSON output. |

## `easybar inbox mark-read`

Mark one message or every visible message from a source as read.

```bash
easybar inbox mark-read --source backup --id minio-nightly
easybar inbox mark-read --source backup
```

`--source` is required. Omit `--id` to apply the operation to every visible message from the selected source.

## `easybar inbox mark-unread`

Mark one message or every visible message from a source as unread.

```bash
easybar inbox mark-unread --source backup --id minio-nightly
easybar inbox mark-unread --source backup
```

`--source` is required. Omit `--id` to apply the operation to every visible message from the selected source.

## `easybar inbox dismiss`

Dismiss one message or every dismissible visible message from a source.

```bash
easybar inbox dismiss --source backup --id minio-nightly
easybar inbox dismiss --source backup
```

`--source` is required. Omit `--id` to apply the operation to every visible message from the selected source.

## `easybar inbox remove`

Delete one message by its source and stable ID.

```bash
easybar inbox remove --source backup --id minio-nightly
```

Both `--source` and `--id` are required.

## `easybar inbox clear`

Remove all messages from one source or clear every inbox source.

```bash
easybar inbox clear --source backup
easybar inbox clear --all
```

The command accepts either `--source` or `--all`, never both.

## Related pages

- [Native Inbox for Lua](../lua/guides/inbox.md)
- [Inbox configuration](../configuration/builtins/inbox.md)
- [CLI Reference](cli.md)
