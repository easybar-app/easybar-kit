# Calendar Agent

`easybar-calendar-agent` owns EventKit.

It is responsible for:

- requesting calendar access
- observing changes
- building normalized snapshots
- grouping popup sections
- handling event mutations
- pushing updates to subscribers

## Requests

```json
{
  "requestID": "month-42",
  "command": "ping | version | fetch | subscribe | logs | create_event | update_event | delete_event",
  "query": {
    "startDate": "2026-03-29T00:00:00Z",
    "endDate": "2026-04-01T00:00:00Z"
  }
}
```

Notes:

- `requestID` is optional and is echoed by every direct response for request correlation
- `query` is required for `fetch` and `subscribe`
- date range is inclusive/exclusive, must be forward and finite, and may span at most 366 days
- section counts, filter arrays, text, identifiers, alerts, and mutation durations are bounded before EventKit work begins
- filters are applied server-side to regular and birthday calendars

## Responses

```json
{
  "kind": "snapshot",
  "requestID": "month-42",
  "snapshot": { ... }
}
```

Other kinds:

- `pong`
- `version`
- `subscribed`
- `log_subscribed`
- `log_record`
- `created`
- `updated`
- `deleted`
- `error`

Errors include a stable `errorCode` and a human-readable `message`:

```json
{
  "kind": "error",
  "errorCode": "invalid_request",
  "message": "The calendar date range exceeds the supported maximum."
}
```

`invalid_request` means the request itself is unsupported and retrying the same payload cannot
succeed. Other error codes describe permission, event lookup, writable-calendar, or mutation
failures.

## Snapshot

```json
{
  "accessGranted": true,
  "permissionState": "authorized",
  "generatedAt": "2026-03-29T12:34:56Z",
  "events": [],
  "sections": []
}
```

## Event fields

- `id`
- `title`
- `startDate`
- `endDate`
- `isAllDay`
- `calendarName`
- `calendarColorHex`
- `location`
- `url` (direct EventKit URL, or the first URL EasyBar can extract from location or notes)
- `isHoliday`
- `hasAlert`
- `travelTimeSeconds`

## Behavior notes

- the month client derives its preload radius from the shared 366-day request limit instead of
  using a hard-coded radius
- EasyBar assigns request identifiers to subscriptions and ignores delayed direct responses that
  belong to an older request; unsolicited broadcast snapshots intentionally omit an identifier
- no access returns an empty snapshot
- birthdays are separated and use the same calendar filters as regular events
- occurrence ids are deterministic even when EventKit omits an event identifier
- relative and absolute alarms are normalized into visible lead times
- EventKit exposes no public event travel-time API; compatibility access is isolated behind an
  exception-safe Objective-C adapter and invalid values fail closed
- sections are optional, day-bucketed once, and clamp multi-day display times to each section day
- EasyBar treats `invalid_request` as permanent for the exact rejected subscription: it logs the
  rejection once, suspends reconnects, and retains the last valid snapshot
- when the subscription request or socket configuration changes, EasyBar clears the permanent
  block and reconnects immediately

## Boundary

The calendar agent collects calendar data and performs calendar mutations.

EasyBar decides how calendar data is rendered.




