local root = assert(arg[1], "repository root argument is required")
local host = assert(loadfile(root .. "/Tests/lua/helpers/inbox_host.lua"))()
local state = host.load(root, "inbox-demo/widget.lua")

assert(#state.items == 0, "Inbox demo must start without publishing messages")
assert(state:source_action("refresh") ~= nil, "Inbox demo must expose its add action")
assert(state:source_action("clear") ~= nil, "Inbox demo must expose its clear action")

state.context_action_handler({ action_id = "refresh" })
assert(state:has_busy_source_action(), "Inbox demo refresh must show source activity")
state:run_next_timer()
assert(not state:has_busy_source_action(), "Inbox demo refresh must clear source activity")
assert(#state.items == 10, "Inbox demo refresh must publish the complete snapshot")
assert(state:item("github-review") ~= nil, "Inbox demo must publish the review item")
for _, item in ipairs(state.items) do
	assert(not state:item_has_action(item.id, "open"), "Inbox demo must not duplicate the native Open action")
	assert(not state:item_has_action(item.id, "mark_read"), "Inbox demo must not duplicate the native read action")
	assert(not state:item_has_action(item.id, "dismiss"), "Inbox demo must not duplicate the native Dismiss action")
end

state.context_action_handler({ action_id = "clear" })
assert(#state.items == 0, "Inbox demo clear must remove the snapshot")

print("Inbox demo widget regression checks passed")
