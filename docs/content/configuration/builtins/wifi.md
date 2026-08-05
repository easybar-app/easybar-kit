# Wi-Fi

The native Wi-Fi widget always renders signal bars as its anchor. Its content mode controls whether additional network values appear inline or in a popup.

```toml
[builtins.wifi]
enabled = true
position = "right"
order = 30

[builtins.wifi.content]
mode = "details" # icon | inline | details
surface = "hover" # always | hover
```

## Content modes

| Mode      | Behavior                                                           |
| --------- | ------------------------------------------------------------------ |
| `icon`    | Shows only the Wi-Fi signal bars.                                  |
| `inline`  | Joins enabled field values into one string beside the signal bars. |
| `details` | Shows enabled fields as label/value rows in a popup.               |

`surface` controls whether the selected content appears immediately or on hover. Inline content always renders in the bar and details always render in the popup; there is no separate `hover_surface` setting.

## Fields

The same `[builtins.wifi.fields]` toggles drive inline and details mode:

```toml
[builtins.wifi.fields]
ssid = true
ipv4_address = true
ipv6_address = true
rssi = true
link_quality = true
tx_rate = true
```

Available values include SSID, IP addresses, BSSID, interface and hardware address, power and service state, RSSI, noise, SNR, link quality, transmit rate, channel details, security, PHY and interface modes, country code, roaming state, and change timestamps. See the [Configuration Reference](../reference.md) for every exact key.

Inline mode joins enabled values with `inline_separator`. Details mode renders named rows and uses `[builtins.wifi.popup]` for its background, border, padding, and text colors.

## Permissions

The separately installed network agent owns Wi-Fi observation. Wi-Fi-specific fields require Location Services permission on macOS. If permission is missing, the widget shows its configured `denied_text` for SSID.

After changing permission, restart the network agent:

```bash
easybar agent restart network
```

## Context menu

Right-click the Wi-Fi anchor to change its content mode or toggle individual fields. The menu also
provides Refresh and Open Network Settings actions.

Configuration changes are written to `config.toml` immediately. Comments, whitespace, and
unrelated settings are preserved. Checked menu items show the persisted values.

See [Agents](../agents.md) and [Recovery](../../runtime/recovery.md) for further checks.
