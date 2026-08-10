# EasyBarKit

EasyBarKit is the shared runtime and widget framework used by the EasyBar frontends:

- `easybar`: the customizable full-width top bar.
- `easybar-native`: native macOS menu-bar hosting for Lua widgets backed by `NSStatusItem`.
- `widgets`: shared Lua widget packages.

The kit owns configuration parsing, Lua execution, widget state and rendering, events, popups,
context menus, themes, the inbox, system services, helper-agent protocols, package management, and
the reusable SwiftUI widget renderer. Frontends own their application identity, choose which
EasyBarKit-owned built-in surfaces are enabled, and decide where top-level surfaces are hosted.

Lua packages are the only public widget extension model. EasyBarKit still contains native SwiftUI
implementations for product-owned surfaces, but it does not expose a Swift/native widget plugin API.

## Frontend API

A frontend creates its own `EasyBarApplicationIdentity` and starts the shared application shell with
an `EasyBarSurfaceFactory`:

```swift
let identity = EasyBarApplicationIdentity(
  displayName: "My Frontend",
  processName: "my-frontend",
  loggerLabel: "my-frontend",
  logFileName: "my-frontend.out",
  builtInSurfacePolicy: .inboxOnly
)

EasyBarApplication.run(identity: identity) { context in
  MySurfaceController(context: context)
}
```

`EasyBarPresentationModel` exposes top-level `WidgetSurface` values. Each surface provides a
self-contained SwiftUI view, so frontends do not need access to the internal widget tree.

EasyBar opts into `.all` and places Lua widgets plus the complete built-in surface set in a
borderless top-edge panel. EasyBar Native opts into `.inboxOnly`: Lua widget roots become independent
`NSStatusItem`s, while the shared Inbox remains a host-owned aggregation surface. Regular built-ins
such as Calendar, Battery, Wi-Fi, Spaces, and CPU are not registered by EasyBar Native.

## Package contract

Installable Lua packages use manifest version 2 and declare the minimum compatible EasyBarKit
version with `minimum_easybar_kit_version`. EasyBarKit does not accept manifest version 1. The clean
split starts with EasyBarKit `0.54.0`, which is the baseline for the first official manifest-v2
package releases.

## Development

```bash
make build
make test
make check
```

For sibling development, keep `easybar`, `easybar-native`, `easybar-kit`, and `widgets` next to each
other. The frontend Swift packages resolve `../easybar-kit` directly.

Install the shared CLI, Lua runtime, and helper agents into `~/.local/bin` with:

```bash
make install-local
```

Override the destination with `LOCAL_BIN_DIR=/path/to/bin`.
