local root = assert(arg[1], "repository root argument is required")
local host = assert(loadfile(root .. "/Tests/lua/helpers/inbox_host.lua"))()
local _, inbox = host.modules(root)

local function load_widget()
	return host.load(root, "inbox/github/widget.lua")
end

local function test_item_refresh_stays_inline()
	local state = load_widget()
	state:run_next_timer()
	assert(state:has_busy_source_action(), "GitHub startup refresh must show source activity")
	state:complete_next_command("github-one", 0)
	assert(not state:has_busy_source_action(), "GitHub source activity must end after refresh")
	local item = assert(state:item("thread-1"), "GitHub notification must be published")
	assert(item.url == "https://github.com/easybar/easybar/pull/1", "GitHub notification must use the native URL field")
	assert(item.timestamp == inbox.timestamp("2026-08-03T09:45:00Z"), "GitHub notification must publish updated_at")
	assert(not state:item_has_action("thread-1", "open"), "GitHub notification must not duplicate the native Open action")

	state.action_handler({ action_id = "mark_read", target_widget_id = "thread-1" })
	assert(state:item_action_is_busy("thread-1", "mark_read"), "GitHub item mutation must show inline activity")
	assert(not state:has_busy_source_action(), "GitHub item mutation must not show source activity")

	state:complete_next_command("", 0)
	assert(state:item_action_is_busy("thread-1", "mark_read"), "GitHub post-mutation refresh must stay inline")
	assert(not state:has_busy_source_action(), "GitHub post-mutation refresh must not show source activity")

	state:complete_next_command("github-empty", 0)
	assert(state:item("thread-1") == nil, "GitHub refreshed item must disappear")
	assert(not state:has_busy_source_action(), "GitHub item completion must remain source-idle")
end

local function test_merge_method_setting_persists_and_drives_merge()
	local state = load_widget()
	assert(
		assert(state:source_action("merge_method:squash")).title == "✓ Squash and merge",
		"GitHub must mark the default squash method"
	)
	assert(
		assert(state:source_action("merge_confirmation:immediate")).title == "✓ Merge immediately",
		"GitHub must merge immediately by default"
	)

	state.context_action_handler({ action_id = "merge_confirmation:required" })
	assert(state.storage_values["github-inbox:confirm_merge"] == true, "GitHub must persist required confirmation")
	assert(
		assert(state:source_action("merge_confirmation:required")).title == "✓ Require confirmation",
		"GitHub must mark required confirmation"
	)

	state.context_action_handler({ action_id = "merge_method:rebase" })
	assert(state.storage_values["github-inbox:merge_method"] == "rebase", "GitHub must persist the selected merge method")
	assert(
		assert(state:source_action("merge_method:rebase")).title == "✓ Rebase and merge",
		"GitHub must mark the persisted merge method"
	)

	state:run_next_timer()
	state:complete_next_command("github-one", 0)
	state.action_handler({ action_id = "prepare_merge", target_widget_id = "thread-1" })
	state:complete_next_command("github-pr-ready", 0)
	assert(state:item_has_action("thread-1", "confirm_merge"), "ready pull requests must expose merge confirmation")

	state.action_handler({ action_id = "confirm_merge", target_widget_id = "thread-1" })
	local merge_command = assert(state.commands[1], "GitHub must start a merge command").command
	local arguments = {}
	for _, argument in ipairs(merge_command) do
		arguments[argument] = true
	end
	assert(arguments["--rebase"], "GitHub merge command must use the persisted rebase method")
	assert(not arguments["--squash"], "GitHub merge command must not retain the previous squash method")
end

local function test_merge_confirmation_defaults_to_immediate()
	local state = load_widget()
	assert(
		assert(state:source_action("merge_confirmation:immediate")).title == "✓ Merge immediately",
		"GitHub must mark immediate confirmation"
	)

	state:run_next_timer()
	state:complete_next_command("github-one", 0)
	state.action_handler({ action_id = "prepare_merge", target_widget_id = "thread-1" })
	state:complete_next_command("github-pr-ready", 0)
	assert(
		state:item_action_is_busy("thread-1", "confirm_merge"),
		"GitHub immediate mode must start merging without confirmation"
	)

	local merge_command = assert(state.commands[1], "GitHub immediate mode must start a merge command").command
	local arguments = {}
	for _, argument in ipairs(merge_command) do
		arguments[argument] = true
	end
	assert(arguments.merge, "GitHub immediate mode must execute gh pr merge")
	assert(arguments["--match-head-commit"], "GitHub immediate mode must retain the inspected head guard")
	assert(arguments["0123456789abcdef"], "GitHub immediate mode must merge the inspected head commit")
end

local function test_overlapping_mutations_coalesce_refresh()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command("github-two", 0)

	state.action_handler({ action_id = "mark_read", target_widget_id = "thread-1" })
	state.action_handler({ action_id = "mark_read", target_widget_id = "thread-2" })
	assert(#state.commands == 2, "GitHub mutations must be allowed to overlap across items")

	state:complete_command(1, "", 0)
	assert(#state.commands == 2, "first GitHub mutation must start its refresh")
	state:complete_command(1, "", 0)
	assert(#state.commands == 1, "second GitHub mutation must queue behind the active refresh")
	assert(state:item_action_is_busy("thread-2", "mark_read"), "queued GitHub mutation must remain visibly busy")

	state:complete_next_command("github-second", 0)
	assert(#state.commands == 1, "queued GitHub mutation must start a follow-up refresh")
	assert(state:item_action_is_busy("thread-2", "mark_read"), "queued item must stay busy through the first refresh")
	state:complete_next_command("github-empty", 0)
	assert(state:item("thread-2") == nil, "follow-up refresh must observe the second mutation")
end

local function test_errors_retain_snapshot()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command("github-one", 0)
	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command(string.rep("x", 20000), 1)
	assert(state:item("thread-1") ~= nil, "GitHub refresh errors must retain the last good snapshot")
	assert(state.items[1].id == "error", "GitHub errors must be published before capped snapshot items")
	assert(utf8.len(assert(state:item("error")).body) <= inbox.maximum_error_length, "GitHub errors must be bounded")

	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command("github-object", 0)
	assert(state:item("thread-1") ~= nil, "GitHub malformed responses must retain the last good snapshot")
	assert(state:item("error") ~= nil, "GitHub malformed responses must publish an error")
end

test_item_refresh_stays_inline()
test_merge_method_setting_persists_and_drives_merge()
test_merge_confirmation_defaults_to_immediate()
test_overlapping_mutations_coalesce_refresh()
test_errors_retain_snapshot()

print("GitHub inbox widget regression checks passed")
