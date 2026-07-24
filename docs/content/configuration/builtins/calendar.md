# Calendar

The calendar built-in combines a configurable time/date anchor with month, upcoming-event, appointment, and composer popups. Calendar data and permission handling belong to the separately installed calendar agent.

## Anchor

The anchor uses an ordered list of `time` and `date` fields. A row places them beside each other, a column stacks them, and a one-element list creates a single-field anchor.

```toml
[builtins.calendar.anchor]
layout = "row"
fields = ["time", "date"]
spacing = 0
separator = ", "

[builtins.calendar.anchor.time]
format = "HH:mm"
text_color = "theme.text"
font_size = 13
font_weight = "semibold"

[builtins.calendar.anchor.date]
format = "EEE, MMM d"
text_color = "theme.text_secondary"
font_size = 12
font_weight = "regular"
```

Each field has its own format, color, optional font family and size, and font weight. `separator` is rendered only in row layouts. The standalone time and date built-ins remain useful when those values belong elsewhere in the bar.

## Appointment details and actions

```toml
[builtins.calendar.appointments]
show_location = true
location_icon = ""
location_icon_color = "theme.accent"
show_travel_time = true
travel_icon = ""
travel_icon_color = "theme.muted_secondary"
meeting_url_patterns = [
  "zoom.us",
  "meet.google.com",
  "teams.microsoft.com",
  "webex.com",
  "whereby.com",
  "jitsi",
  "gotomeeting.com",
  "bluejeans.com",
]
```

Appointment menus provide Edit, Copy Details, Join Meeting or Open URL when available, and Open in
Calendar. `meeting_url_patterns` contains case-insensitive URL substrings that select the **Join
Meeting** title. When omitted, EasyBar uses the built-in list shown above. A configured list replaces
the defaults, so custom services can be added without changing Swift code. Set it to `[]` to label
every valid event link as **Open URL**.

## Filters

Use `included_calendar_names` and `excluded_calendar_names` for calendar titles visible in Calendar.app. Exact ID and source-ID include/exclude lists are also available for advanced matching. Exclusions always win and blank entries are ignored.

## Permissions

macOS grants Calendar access to the calendar agent, not the main EasyBar application. After changing access, restart the agent:

```bash
easybar agent restart calendar
```

## Context menu

Right-click the calendar anchor to select the month, upcoming, or disabled popup mode. The menu can
also change the anchor layout, toggle the time and date fields,
control appointment and birthday details, refresh calendar data, and open Calendar privacy
settings.

At least one anchor field remains enabled so the calendar keeps a visible interaction target.
Each configuration change is written to `config.toml` immediately. Comments, whitespace, and
unrelated settings are preserved.

See the [Configuration Reference](../reference.md) for month, upcoming, selection, composer, appointment, and filter keys. See [Calendar Agent](../../internals/agents/calendar-agent.md) for the process boundary and [Recovery](../../runtime/recovery.md) for permission troubleshooting.
