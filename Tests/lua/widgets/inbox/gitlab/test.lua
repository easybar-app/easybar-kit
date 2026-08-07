local root = assert(arg[1], "repository root argument is required")
local host = assert(loadfile(root .. "/Tests/lua/helpers/inbox_host.lua"))()
local _, inbox = host.modules(root)

local function load_widget()
	return host.load(root, "inbox/gitlab/widget.lua")
end

local function test_merge_method_setting_persists_and_drives_merge()
	local state = load_widget()
	assert(
		assert(state:source_action("merge_method:merge")).title == "✓ Project default",
		"GitLab must mark the project-default merge method"
	)
	assert(
		assert(state:source_action("merge_confirmation:immediate")).title == "✓ Merge immediately",
		"GitLab must merge immediately by default"
	)

	state.context_action_handler({ action_id = "merge_confirmation:required" })
	assert(state.storage_values["gitlab-inbox:confirm_merge"] == true, "GitLab must persist required confirmation")
	assert(
		assert(state:source_action("merge_confirmation:required")).title == "✓ Require confirmation",
		"GitLab must mark required confirmation"
	)

	state.context_action_handler({ action_id = "merge_method:rebase" })
	assert(state.storage_values["gitlab-inbox:merge_method"] == "rebase", "GitLab must persist the selected merge method")
	assert(
		assert(state:source_action("merge_method:rebase")).title == "✓ Rebase and merge",
		"GitLab must mark the persisted merge method"
	)

	state:run_next_timer()
	state:complete_next_command("gitlab-issues", 0)
	state:complete_next_command("gitlab-merge-requests", 0)
	assert(state:item_has_action("merge_request:2", "prepare_merge"), "GitLab merge requests must expose merge")

	state.action_handler({ action_id = "prepare_merge", target_widget_id = "merge_request:2" })
	local inspect_command = assert(state.commands[1], "GitLab must inspect the merge request before merging").command
	assert(
		inspect_command[#inspect_command] == "projects/123/merge_requests/2?with_merge_status_recheck=true",
		"GitLab must inspect the exact project and merge request"
	)
	state:complete_next_command("gitlab-mr-ready", 0)
	assert(state:item_has_action("merge_request:2", "confirm_merge"), "ready merge requests must expose confirmation")

	state.action_handler({ action_id = "confirm_merge", target_widget_id = "merge_request:2" })
	local merge_command = assert(state.commands[1], "GitLab must start a merge command").command
	local arguments = {}
	for _, argument in ipairs(merge_command) do
		arguments[argument] = true
	end
	assert(arguments["--rebase"], "GitLab merge command must use the persisted rebase method")
	assert(not arguments["--squash"], "GitLab merge command must not use the previous method")
	assert(arguments["--auto-merge=false"], "GitLab merge command must not silently enable auto-merge")
	assert(arguments["--yes"], "GitLab merge command must disable the interactive confirmation prompt")
	assert(arguments["--sha"], "GitLab merge command must guard the reviewed source commit")
	assert(arguments["fedcba9876543210"], "GitLab merge command must match the inspected head commit")
	assert(arguments["https://gitlab.com/easybar/easybar"], "GitLab merge command must target the source project")
end

local function test_merge_confirmation_defaults_to_immediate()
	local state = load_widget()
	assert(
		assert(state:source_action("merge_confirmation:immediate")).title == "✓ Merge immediately",
		"GitLab must mark immediate confirmation"
	)

	state:run_next_timer()
	state:complete_next_command("gitlab-issues", 0)
	state:complete_next_command("gitlab-merge-requests", 0)
	state.action_handler({ action_id = "prepare_merge", target_widget_id = "merge_request:2" })
	state:complete_next_command("gitlab-mr-ready", 0)
	assert(
		state:item_action_is_busy("merge_request:2", "confirm_merge"),
		"GitLab immediate mode must start merging without confirmation"
	)

	local merge_command = assert(state.commands[1], "GitLab immediate mode must start a merge command").command
	local arguments = {}
	for _, argument in ipairs(merge_command) do
		arguments[argument] = true
	end
	assert(arguments.merge, "GitLab immediate mode must execute glab mr merge")
	assert(arguments["--sha"], "GitLab immediate mode must retain the inspected SHA guard")
	assert(arguments["fedcba9876543210"], "GitLab immediate mode must merge the inspected head commit")
end

local function test_mark_read_stays_local()
	local state = load_widget()
	state:run_next_timer()
	assert(state:has_busy_source_action(), "GitLab startup refresh must show source activity")
	state:complete_next_command("gitlab-issues", 0)
	state:complete_next_command("gitlab-merge-requests", 0)
	assert(not state:has_busy_source_action(), "GitLab source activity must end after refresh")
	assert(state.items[1].id == "merge_request:2", "GitLab work items must merge by updated_at")
	local item = assert(state:item("issue:1"), "GitLab issue must be published")
	assert(item.url == "https://gitlab.com/easybar/easybar/-/issues/1", "GitLab issue must use the native URL field")
	assert(item.timestamp == inbox.timestamp("2026-08-03T09:45:00.123+00:00"), "GitLab issue must publish updated_at")
	assert(not state:item_has_action("issue:1", "open"), "GitLab issue must not duplicate the native Open action")

	local command_count = #state.commands
	state.action_handler({ action_id = "mark_read", target_widget_id = "issue:1" })
	assert(#state.commands == command_count, "GitLab local mark-read must not start a refresh")
	assert(not state:has_busy_source_action(), "GitLab local mark-read must not show source activity")
end

local function test_errors_retain_snapshot()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command("gitlab-issues", 0)
	state:complete_next_command("gitlab-empty", 0)
	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command(string.rep("y", 20000), 1)
	assert(state:item("issue:1") ~= nil, "GitLab refresh errors must retain the last good snapshot")
	assert(state.items[1].id == "error", "GitLab errors must be published before capped snapshot items")
	assert(utf8.len(assert(state:item("error")).body) <= inbox.maximum_error_length, "GitLab errors must be bounded")

	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command("gitlab-object", 0)
	assert(state:item("issue:1") ~= nil, "GitLab malformed responses must retain the last good snapshot")
	assert(state:item("error") ~= nil, "GitLab malformed responses must publish an error")
end

test_merge_method_setting_persists_and_drives_merge()
test_merge_confirmation_defaults_to_immediate()
test_mark_read_stays_local()
test_errors_retain_snapshot()

print("GitLab inbox widget regression checks passed")
