# EasyBarKit

EasyBarKit is the shared Swift and Lua framework behind EasyBar and EasyBar Native. It provides the
public Lua widget platform and reusable application services for EasyBar frontends.

## Features

- Lua widget loading, events, timers, commands, storage, and logging
- SwiftUI rendering for items, groups, sliders, graphs, popups, and context menus
- Package installation, dependency resolution, validation, and activation
- TOML configuration, themes, generated schemas, and editor support
- Shared Inbox, runtime control, metrics, and diagnostics
- Calendar and network helper-agent products used by EasyBar

Lua packages are the public widget extension model. EasyBarKit does not provide a native Swift widget
plugin API.

## Requirements

- macOS 14 Sonoma or newer
- Swift 5.10 or newer
- Lua 5.5 for Lua runtime checks

## Development

```bash
make build
make test
make check
```

## Documentation

- [EasyBarKit overview](https://easybar.dev/platform/easybar-kit/)
- [Lua widget guides](https://easybar.dev/lua/overview/)
- [Lua API reference](https://easybar.dev/lua/reference/)
- [Configuration reference](https://easybar.dev/products/easybar/configuration/reference/)
- [Architecture and development](https://easybar.dev/internals/overview/)

## License

Licensed under the [Apache License 2.0](./LICENSE).
