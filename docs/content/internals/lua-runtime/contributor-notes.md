# Contributor Notes

Use this page when changing the Lua runtime or public Lua API.

## Where to change what

### Widget API

- `api.lua`
- `easybar_api.base.lua`
- `easybar_api.events.lua`
- `easybar_api.lua`
- `docs/content/lua/*`

`easybar_api.base.lua` is the hand-edited source stub.
`easybar_api.events.lua` is generated from the event catalog.
`easybar_api.lua` is the combined generated artifact that EasyBar installs for LuaLS/editor support.

### Driver events

- `event_tokens.lua`
- `easybar_api.events.lua`
- `easybar_api.lua`
- Swift event sources

### Event payloads

- `EventHub.swift`
- `EventTypes.swift`
- `events.lua`

### Rendering

- `render.lua`
- `WidgetNodeState.swift`

### Process and runtime

- `RuntimeCoordinator.swift`
- `WidgetEngine.swift`
- `LuaProcessController.swift`
- `LuaTransport.swift`

## Formatting

Install StyLua before running the repository formatting checks:

```bash
brew install stylua
```

The root `.stylua.toml` defines the Lua 5.5 formatting rules used by local development and CI.

Use the Makefile entry points rather than invoking different formatter options manually:

```bash
make fmt       # Format Swift and Lua.
make fmt-all   # Format Swift, Lua, and Markdown.
make lint      # Check Swift and Lua formatting without modifying files.
make fmt-lua   # Format only Lua.
make lint-lua  # Check only Lua formatting.
```

## Generated artifacts

Regenerate every checked-in generated artifact through the Makefile:

```bash
make generate
```

This runs the focused generators wired through the Makefile:

- `scripts/generate/theme_tokens.py` for theme-token Swift and Lua artifacts
- `scripts/generate/event_catalog.py` for event-token Lua artifacts and the combined LuaLS stub
- `EasyBarGenerateConfig` for `config.defaults.toml` and the config reference
- `scripts/generate/lua_docs.py` for Lua reference docs

Use this before committing changes that affect generated Swift, Lua, TOML, or documentation artifacts.

Verify that generated artifacts are current before opening a pull request:

```bash
make check-generated
```

`make test` intentionally does not regenerate checked-in artifacts. Run `make generate` or
`make check-generated` explicitly when changing generated Swift, Lua, or documentation outputs.

## Generated docs

Regenerate only generated documentation through the Makefile:

```bash
make generate-docs
```

Generated docs are produced by `scripts/generate/lua_docs.py` and `EasyBarGenerateConfig config-docs`. Call those directly only when debugging the generation pipeline.

Generated Markdown is formatted automatically as part of `make generate-docs`, so generated-doc comparisons stay stable. Run `make fmt-all` or `make fmt-markdown` only when you intentionally want to format all Markdown with Prettier.

## Helper scripts

Reusable automation scripts live under `scripts/` and are grouped by purpose:

- `scripts/build/` contains build helpers used by the Makefile, such as universal product builds, resource copying, plist stamping, and bundle verification.
- `scripts/ci/` contains CI helpers such as dependency setup and long-running Swift test logging.
- `scripts/dev/` contains local-development wrappers such as the shared run and stop flows.
- `scripts/release/` contains release helpers such as signing, notarization, Homebrew cask rendering, release verification, and tap commits.

Keep stable developer commands in the Makefile and delegate large reusable shell blocks into these scripts. This keeps commands like `make run-debug`, `make generate`, `make build-docs`, and `make package` stable while avoiding duplicated or hard-to-review shell logic.

## Notes

- widget directory is executable Lua
- every regular top-level `*.lua` file is loaded as a widget entrypoint
- service-specific modules live below `integrations/`, generic modules below `shared/`, and legacy `lib/` remains a fallback
- reload is a full reset
- protocol:
  - Lua socket JSON in/out via `EasyBarLuaRuntime`
  - stderr logs

## If you change the Lua API

When changing the Lua API:

1. update runtime code
2. update stubs
3. run `make generate-docs`
4. update hand-written guides and examples



