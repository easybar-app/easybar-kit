local root = assert(arg[1], "repository root argument is required")
local host = assert(loadfile(root .. "/Tests/lua/helpers/inbox_host.lua"))()
local state = host.load(root, "inbox/demo/widget.lua")

assert(#state.items == 0, "Inbox demo must start without publishing messages")
assert(state:source_action("refresh") ~= nil, "Inbox demo must expose its add action")
assert(state:source_action("clear") ~= nil, "Inbox demo must expose its clear action")

state.context_action_handler({ action_id = "refresh" })
assert(state:has_busy_source_action(), "Inbox demo refresh must show source activity")
state:run_next_timer()
assert(not state:has_busy_source_action(), "Inbox demo refresh must clear source activity")
assert(#state.items == 10, "Inbox demo refresh must publish the complete snapshot")
assert(state:item("github-review") ~= nil, "Inbox demo must publish the review item")

state.action_handler({ action_id = "dismiss", target_widget_id = "github-review" })
assert(state:item_action_is_busy("github-review", "dismiss"), "Inbox demo dismiss must show item activity")
state:run_next_timer()
assert(state:item("github-review") == nil, "Inbox demo dismiss must remove the selected item")

state.context_action_handler({ action_id = "clear" })
assert(#state.items == 0, "Inbox demo clear must remove the snapshot")

print("Inbox demo widget regression checks passed")
