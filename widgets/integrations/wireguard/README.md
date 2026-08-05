# WireGuard Widget

This package contains the implementation and local service-name settings for `../../wireguard.lua`.

Edit `secrets.lua` so `vpn_name` matches the service name shown by:

```sh
scutil --nc list
```

The example expects a user-provided icon at `widgets/assets/wireguard.png`.

The top-level file remains the executable entrypoint; files in this directory are loaded through `require(...)`.
