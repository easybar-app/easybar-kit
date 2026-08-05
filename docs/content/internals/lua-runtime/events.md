# Lua Runtime Events

Events are the main data path from Swift into Lua.

## 1. Swift emits events

From `EventHub.swift`.

Each event:

- notifies Swift listeners
- is sent to Lua as JSON over the dedicated socket

## 2. Lua declares subscriptions

After loading widgets:

- Lua sends required events
- Swift enables only those

The subscription list can change at runtime. Native widgets contribute to the same merged demand set.
Camera and microphone observation starts only while a Lua widget or native consumer subscribes to a
capture event, and stops again when the final subscriber disappears. The fixed privacy spacer does
not subscribe to capture events.

Core Media I/O camera listeners plus Core Audio microphone inventory, process-list, process-state,
and input-device wakeup listeners feed one normalized capture snapshot to subscribers. Microphone
activity prefers `kAudioProcessPropertyIsRunningInput`. Input-device running state is used as an
activation fallback for microphone-only capture and is suppressed across a camera session until the
input device returns idle. Each native Core Audio notification also schedules one short settling read;
this is a one-shot verification rather than periodic polling. A newly added capture subscription
receives the current snapshot once, even when another subscriber already keeps the source active.

For example, `interval` plus `on_interval` causes Lua to request one
widget-scoped interval schedule such as `interval_tick:brew:1800`.

## 3. Initial events

Once Lua has published both its subscriptions and `ready`, `WidgetEngine` emits the currently subscribed initial event batch and then triggers one normal refresh pass.

This prevents empty UI on startup.

## 4. Manual refresh

Refresh events go through the same pipeline.

There is no special path.

## 5. Lua dispatch

Lua runtime:

1. reads JSON line
2. decodes it
3. normalizes with `events.lua`
4. dispatches through subscriptions
5. renders dirty trees

## Interval flow

```mermaid
flowchart LR
    A["Lua widget registers interval handler"] --> B["Lua exports interval_tick:<widget_id>:<seconds>"]
    B --> C["Swift EventManager parses widget schedule"]
    C --> D["TimerEvents starts per-widget repeating timer"]
    D --> E["Timer fires for that widget"]
    E --> F["EventHub emits interval_tick with widget_id"]
    F --> G["Lua subscriptions dispatch that widget's on_interval"]
    G --> H["Widget mutates registry state"]
    H --> I["Renderer flushes updated tree"]
```

## End-to-end data flow

Complete runtime path from system event to UI:

1. system event occurs, for example Wi-Fi change
2. Swift event source emits through `EventHub`
3. event is forwarded to Lua via socket JSON
4. Lua normalizes and dispatches it
5. widget handlers update registry state through node handles
6. renderer builds a new tree
7. Lua emits JSON tree via the same socket
8. Swift decodes and applies it to `WidgetStore`
9. Swift UI updates accordingly

Important properties:

- no shared memory between Swift and Lua
- all communication is JSON-based
- rendering is always derived, never incremental mutation

Screen recording by another process is intentionally not part of the capture event source. The public
ScreenCaptureKit APIs describe streams and shareable content for the calling application; they do not
provide a supported system-wide start/stop subscription for unrelated screen-capture sessions.
