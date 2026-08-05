# WireGuard Widget

`widget.lua` controls a macOS Network Extension VPN service through `scutil --nc`. The service name is read from EasyBar's widget configuration.

## Configuration

Set the exact service name shown by `scutil --nc list`:

```toml
[widgets.wireguard]
vpn_name = "WireGuard"
```

The default is `WireGuard`. Reload the configuration after changing the value:

```sh
easybar config reload
```

## Behavior

- left click starts or stops the configured service
- the popup shows the configured VPN name and current status
- network and forced-refresh events update the state

This example controls a Network Extension service. It does not invoke `wg-quick` or infer a tunnel name from an interface.
