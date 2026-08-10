# EasyBarKit

EasyBarKit is the shared runtime and widget framework used by the EasyBar frontends:

- `easybar`: the customizable full-width top bar.
- `easybar-native`: native macOS menu-bar widgets backed by `NSStatusItem`.
- `widgets`: shared Lua widget packages.

The kit owns configuration parsing, Lua execution, widget state and rendering, events, popups,
context menus, themes, the inbox, system services, helper-agent protocols, package management, and
the reusable SwiftUI widget renderer. Frontends own their application identity and decide where
top-level widget surfaces are hosted.

## Frontend API

A frontend creates its own `EasyBarApplicationIdentity` and starts the shared application shell with
an `EasyBarSurfaceFactory`:

```swift
let identity = EasyBarApplicationIdentity(
  displayName: "My Frontend",
  processName: "my-frontend",
  loggerLabel: "my-frontend",
  logFileName: "my-frontend.out"
)

EasyBarApplication.run(identity: identity) { context in
  MySurfaceController(context: context)
}
```

`EasyBarPresentationModel` exposes top-level `WidgetSurface` values. Each surface provides a
self-contained SwiftUI view, so frontends do not need access to the internal widget tree.

EasyBar places those surfaces in a borderless top-edge panel. EasyBar Native places each surface in
a separate `NSStatusItem`. Lua widget code is shared by both hosts.

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
