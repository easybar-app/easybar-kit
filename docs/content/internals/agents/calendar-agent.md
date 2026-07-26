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
- sections are optional, day-bucketed once, and clamp multi-day display times to each section day
- EasyBar treats `invalid_request` as permanent for the exact rejected subscription: it logs the
  rejection once, suspends reconnects, and retains the last valid snapshot
- when the subscription request or socket configuration changes, EasyBar clears the permanent
  block and reconnects immediately

## Event travel-time bridge

EventKit does not expose a public, typed API for reading or writing an event's native travel-time
value. EasyBar therefore accesses the runtime `travelTime` property through
`EventKitTravelTimeAdapter`, with the dynamic Objective-C work isolated in
`CEasyBarEventKitCompat`.

The Objective-C boundary is intentional:

- KVC access can raise an Objective-C exception, which Swift `do`/`catch` cannot catch.
- the bridge checks that the runtime getter or setter exists before using it
- Objective-C catches any KVC exception and reports failure to Swift instead of crashing the agent
- the Swift adapter rejects non-finite, negative, zero-on-read, or excessively large values

A pure Swift KVC implementation might work on the current EventKit implementation, but it would
lose the exception boundary. Calling the Objective-C method implementation directly from Swift
would instead introduce unsafe runtime calling conventions and would still not catch Objective-C
exceptions.

The bridge is a separate Swift Package Manager target because a target cannot mix Swift and
Objective-C sources. It can be removed if travel-time support is removed, or if EventKit gains a
public typed API that covers both reading and writing the native value.

## Boundary

The calendar agent collects calendar data and performs calendar mutations.

EasyBar decides how calendar data is rendered.



