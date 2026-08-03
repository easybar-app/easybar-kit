# Built-ins Vs Lua

EasyBar supports two ways to build your bar:

- native built-ins configured in `config.toml`
- custom Lua widgets loaded from your widgets directory

Start with built-ins. Add Lua when a widget needs behavior that is specific to your machine, your tools, or your workflow.

## Use built-ins when

Built-ins are the best default for common macOS and system-integrated data:

- spaces and AeroSpace state
- battery
- Wi-Fi and network fields
- calendar and appointments
- time and date
- volume
- front app state
- CPU status

Built-ins keep platform-sensitive behavior in Swift, use the app's native rendering model, and usually need less maintenance than scripts.

Configure them in `config.toml`:

```toml
[builtins.battery]
enabled = true

[builtins.wifi]
enabled = true

[builtins.calendar]
enabled = true
```

Use [Built-ins](../configuration/builtins.md) for supported widgets and [Native Groups](../configuration/native-groups.md) for shared visual containers.

## Use Lua when

Lua widgets are the right fit for custom behavior:

- custom text or icon formatting
- shell-command integration
- local scripts or project status
- mouse, hover, scroll, or slider interactions
- custom popup content
- small personal workflows without touching Swift code

Lua is the extension layer. It is for user-specific behavior, not for replacing native platform integrations that already exist as built-ins.

Start with [First Widget](../lua/guides/first-widget.md).

## A practical decision rule

Ask this first:

> Does EasyBar already provide this as a native built-in?

If yes, configure the built-in first.

If no, or if the built-in cannot express your desired behavior, use Lua.

## Common split

A strong setup often uses both:

- built-ins for platform-aware widgets and stable system integrations
- Lua for custom display logic, local scripts, and project-specific widgets

Examples:

- Use the native `spaces` built-in for workspace state, then add a Lua widget for VPN state.
- Use the native `calendar` built-in for appointments, then add Lua for a custom project deadline widget.
- Use native groups for battery and Wi-Fi, then use Lua groups for interactive custom widgets.
