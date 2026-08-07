local root = assert(arg[1], "repository root argument is required")
local host = assert(loadfile(root .. "/Tests/lua/helpers/inbox_host.lua"))()

local function load_widget()
	return host.load(root, "inbox/brew/widget.lua")
end

local function test_item_refresh_stays_inline()
	local state = load_widget()
	state:run_next_timer()
	assert(state:has_busy_source_action(), "Homebrew startup refresh must show source activity")
	state:complete_next_command('{"scenario":"brew-one"}', 0)
	state:run_next_timer()
	assert(not state:has_busy_source_action(), "Homebrew source activity must end after refresh")

	state.action_handler({ action_id = "upgrade", target_widget_id = "formula:easybar" })
	assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew upgrade must show inline activity")
	assert(not state:has_busy_source_action(), "Homebrew item mutation must not show source activity")

	state:complete_next_command("", 0)
	state:run_next_timer()
	assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew post-mutation refresh must stay inline")
	assert(not state:has_busy_source_action(), "Homebrew post-mutation refresh must not show source activity")

	state:complete_next_command('{"scenario":"brew-empty"}', 0)
	state:run_next_timer()
	assert(state:item("formula:easybar") == nil, "Homebrew refreshed package must disappear")
	assert(not state:has_busy_source_action(), "Homebrew item completion must remain source-idle")
end

local function test_parser_retains_snapshot_and_handles_warning_braces()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command('{"scenario":"brew-one"}', 0)
	state:run_next_timer()

	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command('{"scenario":"brew-malformed"}', 0)
	state:run_next_timer()
	assert(state:item("formula:easybar") ~= nil, "Homebrew malformed responses must retain the last good snapshot")
	assert(state:item("error") ~= nil, "Homebrew malformed responses must publish an error")
	assert(state.items[1].id == "error", "Homebrew errors must be published before capped snapshot items")

	state.context_action_handler({ action_id = "refresh" })
	state:complete_next_command('Warning {details}\n{"scenario":"brew-one"}\nTrailing {hint}', 0)
	state:run_next_timer()
	assert(state:item("formula:easybar") ~= nil, "Homebrew must decode JSON surrounded by brace-containing warnings")
	assert(state:item("warning") ~= nil, "Homebrew must retain surrounding warning output")
	assert(state:item("error") == nil, "a valid Homebrew snapshot must clear the prior error")
end

local function test_refresh_cancellation_clears_activity()
	local state = load_widget()
	state:run_next_timer()
	assert(state:has_busy_source_action(), "Homebrew refresh must start with source activity")
	state.context_action_handler({ action_id = "cancel" })
	assert(state:has_busy_source_action(), "Homebrew cancellation must retain activity during its completion delay")
	state:run_next_timer()
	assert(not state:has_busy_source_action(), "Homebrew cancellation must clear source activity")
end

local function test_mutation_cancellation_reconciles_snapshot()
	local state = load_widget()
	state:run_next_timer()
	state:complete_next_command('{"scenario":"brew-one"}', 0)
	state:run_next_timer()

	state.action_handler({ action_id = "upgrade", target_widget_id = "formula:easybar" })
	state.context_action_handler({ action_id = "cancel" })
	assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew cancellation must stay inline")
	assert(not state:has_busy_source_action(), "Homebrew item cancellation must not show source activity")

	state:complete_next_command("", 130)
	state:run_next_timer()
	assert(#state.commands == 1, "Homebrew cancellation must reconcile package state")
	assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew reconciliation must stay inline")
	state:complete_next_command('{"scenario":"brew-one"}', 0)
	state:run_next_timer()
	assert(
		not state:item_action_is_busy("formula:easybar", "upgrade"),
		"Homebrew reconciliation must finish inline activity"
	)
end

test_item_refresh_stays_inline()
test_parser_retains_snapshot_and_handles_warning_braces()
test_refresh_cancellation_clears_activity()
test_mutation_cancellation_reconciles_snapshot()

print("Homebrew inbox widget regression checks passed")
