# Bundled Widgets

EasyBar executes every regular `*.lua` file directly in this directory as a widget entrypoint.

The bundled layout separates executable entrypoints from reusable implementation code:

```text
widgets/
├── github.lua
├── github-inbox.lua
├── integrations/
│   └── github/
│       ├── README.md
│       ├── widget.lua
│       └── inbox.lua
├── shared/
│   ├── inbox.lua
│   ├── retry.lua
│   └── text.lua
└── assets/
```

- `integrations/<service>/` contains service-specific implementations, settings modules, and README files.
- `shared/` contains generic helpers reusable across unrelated integrations.
- `assets/` contains file-backed images resolved by top-level entrypoints.
- `lib/` remains a legacy module-search fallback for user configurations.

Use `make install-widgets` to select entrypoints and copy their declared dependencies from `install-manifest.csv`.
