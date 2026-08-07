local root = assert(arg[1], "repository root argument is required")
local host = assert(loadfile(root .. "/Tests/lua/helpers/inbox_host.lua"))()
local json, inbox = host.modules(root)

assert(inbox.decode_array(json, "[]") ~= nil, "JSON arrays must decode")
assert(inbox.decode_array(json, "{}") == nil, "JSON objects must not be accepted as arrays")
assert(inbox.timestamp("1970-01-01T00:00:00Z") == 0, "UTC epoch timestamp must parse")
assert(inbox.timestamp("1970-01-01T01:00:00+01:00") == 0, "positive timezone offset must parse")
assert(inbox.timestamp("1969-12-31T19:00:00-0500") == 0, "compact negative timezone offset must parse")
assert(inbox.timestamp("2000-02-29T12:34:56.789Z") ~= nil, "fractional leap-day timestamp must parse")
assert(inbox.timestamp("2026-02-29T00:00:00Z") == nil, "invalid calendar dates must be rejected")
assert(inbox.timestamp("2026-08-03T09:45:00") == nil, "timestamps without a timezone must be rejected")

print("Shared inbox regression checks passed")
