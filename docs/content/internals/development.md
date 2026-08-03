# Development

## Tools

Install the local development dependencies:

```bash
brew install imagemagick librsvg lua stylua
```

EasyBar consumes the lossless TOML parser and editor from the versioned `SwiftTOMLEdit` Swift
package. Its prebuilt native artifact is resolved by SwiftPM, so EasyBar contributors do not need a
Rust toolchain for normal builds or tests. Lua formatting uses the repository's `.stylua.toml` file
and the `stylua` executable from `PATH`. Release-style bundles use `rsvg-convert` from librsvg to
render the SVG app icons and ImageMagick to validate the rendered colors.

## Common commands

```bash
make fmt
make lint
make test
make stop
make run-debug
```

Other useful targets:

- `make verify` checks the built bundle structure and key packaged files.
- `make build` builds the app, agents, and CLI.
- `make validate-config CONFIG=/path/to/config.toml` validates a config without reloading.
- `make generate` refreshes all checked-in generated artifacts.
- `make generate-docs` refreshes generated documentation only.
- `make check-generated` verifies that generated files are current.
- `make screenshots` applies the documented crops and padding to raw screenshots.
- `make check-screenshots` verifies that the generated screenshots are current.

## Screenshots

Put full-resolution captures in `docs/screenshots/raw`. The pipe-separated
`docs/screenshots/screenshots.manifest` file defines each output's crop rectangle and padding in
pixels. Run `make screenshots` to write deterministic PNGs to `docs/content/assets`.

Keep `bar.png` as the complete overview. Crop feature screenshots around the relevant widget or
popup and use the shared padding from the manifest. Update the crop rectangle when a raw capture's
dimensions or popup position changes.

For the EasyBar context-menu screenshot, run `make screenshot-context-menu`, hover **Native
Widgets** to open its submenu, and take a full-screen screenshot. Save it as
`docs/screenshots/raw/native_widgets.png`; the manifest crop assumes a 1728-point Retina display.

## Test release bundles

Build ad-hoc-signed bundles and launch the agents before the app:

```bash
make bundle ARCH=arm64 VERSION=dev
open -g dist/EasyBarCalendarAgent.app
open -g dist/EasyBarNetworkAgent.app
open dist/EasyBar.app
```

Quit any installed EasyBar app before launching `dist/EasyBar.app`; the single-instance guard exits
the second copy.

The agents are standalone apps that communicate with EasyBar over Unix sockets. Restart them with
`easybar agent restart calendar`, `easybar agent restart network`, or
`easybar agent restart all`.

## Install the current checkout

Install a release-mode development build without Homebrew:

```bash
make install-local
```

The default destinations are:

```text
~/Applications/EasyBar.app
~/.local/bin/easybar
~/Library/Application Support/EasyBar/Agents/EasyBarCalendarAgent.app
~/Library/Application Support/EasyBar/Agents/EasyBarNetworkAgent.app
~/Library/LaunchAgents/io.github.gi8lino.easybar.local.*.plist
```

The installer stops released Homebrew agent services to avoid duplicates and records their state.
It assigns a Git-derived version such as `0.5.0-dev.218886be`; a modified checkout adds `-dirty`.

Inspect and compare the version with:

```bash
make print-local-version
~/.local/bin/easybar --version
```

Repeat `make install-local` to update the installation. Destinations and architecture can be
overridden:

```bash
make install-local LOCAL_INSTALL_ARCH=universal
make install-local LOCAL_APP_DIR=/Applications
make install-local LOCAL_BIN_DIR=/usr/local/bin
```

Remove it and restore the recorded Homebrew service states with:

```bash
make uninstall-local
```

## Generated artifacts

Build and install targets consume checked-in generated files without rewriting them. Run
`make generate` after changing theme tokens, event catalog data, Lua API stubs, or generated Lua
reference documentation, then use `make check-generated` before committing.

The build version is written to the untracked `.build/easybar-build-version` input. The SwiftPM
plugin generates `BuildInfo` in its work directory, and direct SwiftPM builds without that input
use `dev`. Lua API versions are stamped only into the copy under `dist/`.

## Bundled theme resources

The repository root `themes/` directory is the source of truth for bundled themes. SwiftPM does not
automatically package that directory, so use `make run` for local testing and `make bundle` for a
release-style app. Both targets copy the themes into:

```text
EasyBar.app/Contents/Resources/Themes/
```

The bundle checks require `default.toml`. Other app-owned resources are staged separately under
`EasyBar.app/Contents/Resources/EasyBar/`.

Plain `swift run EasyBar` does not stage bundled themes and is therefore unsuitable for testing
them.

## Repository layout

- `Sources/EasyBarApp/App` contains the app shell and startup wiring.
- `Sources/EasyBarApp/Runtime` contains reload, file-watching, and socket orchestration.
- `Sources/EasyBarApp/Widgets` contains native and Lua widget rendering.
- `Sources/EasyBarCalendarAgent` and `Sources/EasyBarNetworkAgent` contain the helper apps.
- `Sources/EasyBarShared` contains shared runtime, logging, socket, and protocol code.
- `scripts/ci`, `scripts/dev`, and `scripts/release` contain reusable workflow implementations.

Continue with [Architecture](architecture/overview.md), [Agents](agents/overview.md), or the
[Lua runtime](lua-runtime/overview.md) for subsystem details.
