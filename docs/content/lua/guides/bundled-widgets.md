# Widget Packages And Examples

EasyBar keeps installable integrations separate from the app:

- the [official widgets repository](https://github.com/easybar-app/widgets) owns package source, package metadata, assets, and focused tests
- the [widget registry](https://github.com/easybar-app/widget-registry) owns searchable catalog entries
- this repository keeps small examples for learning and runtime regression coverage

## Official packages

Browse the current packages and their requirements in the
[official widgets repository](https://github.com/easybar-app/widgets/tree/main/packages), or search
the registry from the command line:

```sh
easybar widgets search
easybar widgets search QUERY
```

Install one by registry name, then reload the app:

```sh
easybar widgets install PACKAGE_NAME
easybar config reload
```

The registry is optional. See [Widget Packages](../../runtime/widget-packages.md) to install a self-created package directly from a local directory or archive.

## Local examples

Browse the current learning examples in the
[app repository](https://github.com/easybar-app/easybar/tree/main/examples). They remain small and
self-contained so they can also provide runtime regression coverage.

Install examples from a source checkout with:

```sh
make install-widgets
```

`examples/install-manifest.csv` declares the examples and assets copied by that development
installer. It is not the package registry.

To contribute an installable integration, follow the
[widgets contribution guide](contributing-widget.md).

For process environment behavior, see [Environment](../../configuration/environment.md). For Lua-owned configuration under `[widgets.*]`, see [Widget Settings](storage.md).
