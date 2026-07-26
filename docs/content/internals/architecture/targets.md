# Targets

EasyBar is split into a few focused targets.

## Target list

- `EasyBarShared`
  Shared models, config loading, socket paths, IPC types, logging utilities, environment keys, and common runtime helpers.
- `EasyBarApp`
  The main macOS status bar application.
- `EasyBarCtl`
  The `easybar` command-line client.
- `EasyBarCalendarAgent`
  Helper app entrypoint for the calendar agent.
- `EasyBarCalendarCore`
  Shared reusable calendar-agent logic used by `EasyBarCalendarAgent` and intended for future standalone calendar clients.
- `CEasyBarEventKitCompat`
  Exception-safe Objective-C bridge used by `EasyBarCalendarCore` to access EventKit's non-public event travel-time value.
- `EasyBarCalendarPresentation`
  Shared reusable calendar request and presentation helpers used by `EasyBar` and intended for future standalone calendar clients.
- `EasyBarCalendarUI`
  Shared reusable calendar SwiftUI components and composer state used by `EasyBar` and intended for future standalone calendar clients.
- `EasyBarNetworkAgent`
  Helper app that owns Wi-Fi and network observation.
- `EasyBarNetworkAgentCore`
  Shared reusable network-agent logic used by `EasyBarNetworkAgent` and also by the standalone `wifi-snitch` project.

## Directory and target intent

A useful way to think about the targets is:

- `Sources/EasyBarShared`
  process-boundary types and shared utilities
- `Sources/EasyBarApp`
  app lifecycle, UI, event coordination, native widgets, Lua supervision
- `Sources/EasyBarCtl`
  command-line control client
- `Sources/EasyBarCalendarAgent`
  calendar-agent executable entrypoint and app lifecycle
- `Sources/EasyBarCalendarCore`
  reusable calendar-agent internals
- `Sources/CEasyBarEventKitCompat`
  Objective-C exception boundary for EventKit travel-time access
- `Sources/EasyBarCalendarPresentation`
  reusable calendar request or presentation logic
- `Sources/EasyBarCalendarUI`
  reusable calendar SwiftUI or calendar-only view state
- `Sources/EasyBarNetworkAgent`
  network-agent executable entrypoint and app lifecycle
- `Sources/EasyBarNetworkAgentCore`
  reusable network-agent internals

That structure reflects runtime responsibilities, not only package-manager convenience.
