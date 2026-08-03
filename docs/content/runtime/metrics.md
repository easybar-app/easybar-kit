# Metrics

EasyBar can stream lightweight internal metrics over the main socket.

## Snapshot

Use:

```bash
easybar metrics
```

for one point-in-time snapshot.

## Watch mode

Use:

```bash
easybar metrics --watch
```

for a rolling terminal view with simple graphs.

## Included metrics

The metrics stream includes:

- EasyBar process CPU, memory, and thread count
- Lua runtime CPU, memory, and thread count
- runtime event and tree-update rates
- Lua transport traffic plus structured warning, error, and raw-stderr counters
- agent connection state plus message, reconnect, and refresh counters
- busiest widget tree roots
- top emitted event names

The periodic sampler stays off until a metrics client asks for it, so normal idle runtime does not keep collecting process samples when nobody is watching.
Consequently, rate fields in a one-shot snapshot are `0.0/s`; use `--watch` to collect meaningful
rates.

Lua output is split by meaning rather than by file descriptor:

- `lua_reads` counts messages received from the Lua transport.
- `lua_writes` counts messages sent to the Lua runtime.
- `lua_logs` counts structured Lua log messages at every level.
- `lua_warn` and `lua_error` count structured warning and error messages.
- `lua_raw_stderr` counts lines that bypassed the structured logging protocol, such as an
  uncaught Lua runtime error.

The **Subscribed events** section lists the sorted global event set currently forwarded to Lua.
It is the union required by all loaded widgets; it is not a per-widget subscription breakdown.
Timer subscriptions are shown with the widget ID and a readable interval.

The **Widget trees** and **Events** sections show the eight highest-volume entries. Widget-tree
timestamps measure tree publications; activity performed through a separate service, such as an
inbox refresh that does not replace a widget tree, does not update them.

Watch mode uses a compact dashboard. Terminals at least 100 columns wide place process and agent
activity side by side, followed by three-column Runtime/Lua/Delivery and
Subscriptions/Widget-trees/Events rows. Narrow terminals stack the same compact tiles vertically.
The renderer checks the terminal width for every frame, so resizing takes effect without restarting
the command. Wide dashboards are capped at 120 columns to keep related columns visually grouped. If
even the compact frame is taller than the viewport, use the scrollable one-shot
`easybar metrics` output.
