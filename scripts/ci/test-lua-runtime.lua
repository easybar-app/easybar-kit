local root = assert(arg[1], "usage: test-lua-runtime.lua <repository-root>")
package.path = root .. "/Sources/EasyBarApp/Lua/?.lua;" .. root .. "/Sources/EasyBarApp/Lua/?/init.lua;" .. package.path

local lua_root = root .. "/Sources/EasyBarApp/Lua/easybar/"
local theme_tokens = assert(loadfile(lua_root .. "theme_tokens.lua"))().keys
local json = assert(loadfile(lua_root .. "json.lua"))()
local colors = {}
for _, key in ipairs(theme_tokens) do
	colors[key] = "#000000"
end
local test_theme_json = json.encode({ name = "test", colors = colors })
local real_getenv = os.getenv
os.getenv = function(name)
	if name == "EASYBAR_INTERNAL_THEME_JSON" then
		return test_theme_json
	end
	if name == "EASYBAR_INTERNAL_LOGGING_DIRECTORY" then
		return "/tmp"
	end
	return real_getenv(name)
end

local api_module = require("easybar.api")
local loader = require("easybar.loader")
local tree = require("easybar.render.tree")

local function assert_contains(value, expected)
	assert(
		tostring(value):find(expected, 1, true),
		"expected '" .. tostring(value) .. "' to contain '" .. expected .. "'"
	)
end

local function expect_error(expected, body)
	local ok, err = pcall(body)
	assert(not ok, "expected error containing: " .. expected)
	assert_contains(err, expected)
end

local cancelled_commands = {}
local cancelled_timers = {}
local async_sequence = 0
local timer_sequence = 0
local warnings = {}
local inbox_publish_count = 0
local widget_logs = {}
local last_command_context = nil
local last_async_hook_options = nil
local last_completed_hook_options = nil
local storage_values = {}

local log = {
	trace = function() end,
	debug = function() end,
	info = function() end,
	warn = function(message)
		warnings[#warnings + 1] = tostring(message)
	end,
	error = function(message)
		warnings[#warnings + 1] = tostring(message)
	end,
	widget = function(source, level, message)
		widget_logs[#widget_logs + 1] = {
			source = source,
			level = level,
			message = message,
		}
	end,
}

local function new_api()
	return api_module.new(log, {
		on_mutation = function() end,
		before_exec_callback = function() end,
		before_async_callback = function() end,
		on_async_job_started = function(_, _, _, options)
			last_async_hook_options = options
		end,
		on_async_job_completed = function(_, _, _, _, options)
			last_completed_hook_options = options
		end,
		request_sync_command = function(_, options, context)
			last_command_context = context
			if options and options.raw_output then
				return "raw\r\n", 0
			end
			return "trimmed\r\n", 0
		end,
		request_async_command = function(_, _, context)
			last_command_context = context
			async_sequence = async_sequence + 1
			return "async:" .. tostring(async_sequence)
		end,
		request_async_process = function(_, _, context)
			last_command_context = context
			async_sequence = async_sequence + 1
			return "process:" .. tostring(async_sequence)
		end,
		request_cancel_async = function(token)
			cancelled_commands[#cancelled_commands + 1] = token
		end,
		request_timer = function()
			timer_sequence = timer_sequence + 1
			return "timer:" .. tostring(timer_sequence)
		end,
		request_cancel_timer = function(token)
			cancelled_timers[#cancelled_timers + 1] = token
		end,
		storage_get = function(widget, key)
			local value = storage_values[widget .. ":" .. key]
			return { ok = true, found = value ~= nil, value = value }
		end,
		storage_set = function(widget, key, value)
			storage_values[widget .. ":" .. key] = value
			return { ok = true, found = true, value = value }
		end,
		publish_inbox = function()
			inbox_publish_count = inbox_publish_count + 1
		end,
		clear_inbox = function() end,
		configure_inbox = function() end,
		default_exec_options = {
			timeout_seconds = 5,
			max_output_bytes = 65536,
		},
	})
end

-- Widget storage uses validated namespace segments and returns defaults for missing values.
do
	local api = new_api()
	local widget = api.make_widget_api("/widgets/github-inbox.lua")
	assert(widget.storage.get("github-inbox", "merge_method", "squash") == "squash")
	assert(widget.storage.set("github-inbox", "merge_method", "rebase") == true)
	assert(widget.storage.get("github-inbox", "merge_method") == "rebase")
	expect_error("storage widget", function()
		widget.storage.get("../app", "merge_method")
	end)
	expect_error("finite", function()
		widget.storage.set("github-inbox", "bad_number", math.huge)
	end)
end

-- Widget host logs use a stable entrypoint name instead of the complete source path.
do
	local api = new_api()
	local widget = api.make_widget_api("/widgets/github-inbox.lua")
	widget.log(widget.level.debug, "refresh started")
	local entry = widget_logs[#widget_logs]
	assert(entry.source == "github-inbox")
	assert(entry.level == "DEBUG")
	assert(entry.message == "refresh started")
end

-- Duplicate ids identify both owners and do not overwrite the first node.
do
	local api = new_api()
	local first = api.make_widget_api("/widgets/first.lua")
	local second = api.make_widget_api("/widgets/second.lua")
	first.add(first.kind.item, "duplicate", { label = "first" })
	expect_error("owner=/widgets/first.lua", function()
		second.add(second.kind.item, "duplicate", { label = "second" })
	end)
	assert(api._state.items.duplicate.source == "/widgets/first.lua")
	assert(api._state.items.duplicate.props.label.string == "first")
end

-- Dispatch snapshots handlers and disposable registrations affect only future turns.
do
	local api = new_api()
	local widget = api.make_widget_api("/widgets/subscriptions.lua")
	local node = widget.add(widget.kind.item, "subscription-node", {})
	local first_calls = 0
	local late_calls = 0
	local late_handle
	local first_handle = node:subscribe(widget.events.forced, function()
		first_calls = first_calls + 1
		if late_handle == nil then
			late_handle = node:subscribe(widget.events.forced, function()
				late_calls = late_calls + 1
			end)
		end
	end)
	api.handle_event({ name = "forced" })
	assert(first_calls == 1 and late_calls == 0, "new handler ran during the same dispatch turn")
	api.handle_event({ name = "forced" })
	assert(first_calls == 2 and late_calls == 1)
	assert(first_handle:dispose() == true)
	assert(first_handle:unsubscribe() == false)
	api.handle_event({ name = "forced" })
	assert(first_calls == 2 and late_calls == 2)
	assert(late_handle:dispose() == true)
end

-- Numeric command/timer/interval options reject non-finite and excessive values consistently.
do
	local api = new_api()
	local widget = api.make_widget_api("/widgets/validation.lua")
	expect_error("finite", function()
		widget.exec("true", { timeout_seconds = math.huge })
	end)
	expect_error("positive integer", function()
		widget.exec("true", { max_output_bytes = 1.5 })
	end)
	expect_error("finite", function()
		widget.after(0 / 0, function() end)
	end)
	expect_error("on_interval requires interval > 0", function()
		widget.add(widget.kind.item, "bad-interval", {
			interval = math.huge,
			on_interval = function() end,
		})
	end)
	local trimmed = widget.exec("true")
	local raw = widget.exec("true", { raw_output = true })
	assert(trimmed == "trimmed")
	assert(raw == "raw\r\n")
end

-- Widget-scoped commands propagate diagnostic context and completion metadata.
do
	local api = new_api()
	local widget = api.make_widget_api("/widgets/github-inbox.lua")
	local completed = nil
	local token = widget.spawn_async({ "printf", "ok" }, { log_operation = "refresh" }, function(_, _, metadata)
		completed = metadata
	end)
	assert(last_command_context.widget == "github-inbox")
	assert(last_command_context.operation == "refresh")
	assert(last_async_hook_options.log_operation == "refresh")
	assert(api.handle_command_response(token, "ok", 0, { duration_ms = 42 }) == true)
	assert(last_completed_hook_options.log_operation == "refresh")
	assert(completed.duration_ms == 42)
end

-- Unknown response tokens are dropped rather than retained forever.
do
	local api = new_api()
	assert(api.handle_command_response("unknown", "payload", 0) == false)
	assert(next(api._state.pending_command_responses) == nil)
	assert(next(api._state.pending_sync_commands) == nil)
end

-- A host-side timer rejection releases the pending callback deterministically.
do
	local api = new_api()
	local handle = api.after(60, function() end)
	assert(api._state.pending_timers[handle.token] ~= nil)
	assert(api.handle_timer_rejected(handle.token) == true)
	assert(api._state.pending_timers[handle.token] == nil)
	assert(api.handle_timer_rejected(handle.token) == false)
	assert(handle:cancel() == false)
end

-- Integration modules are preferred, followed by generic shared modules and the legacy lib fallback.
do
	local temp_dir = os.tmpname() .. "-easybar-module-paths"
	os.remove(temp_dir)
	assert(os.execute('mkdir -p "' .. temp_dir .. '/integrations" "' .. temp_dir .. '/shared" "' .. temp_dir .. '/lib"'))

	local function write_module(relative_path, value)
		local module_file = assert(io.open(temp_dir .. "/" .. relative_path, "w"))
		module_file:write("return " .. string.format("%q", value) .. "\n")
		module_file:close()
	end

	write_module("integrations/integration_resolution.lua", "integration")
	write_module("shared/shared_resolution.lua", "shared")
	write_module("lib/legacy_resolution.lua", "legacy")
	write_module("integrations/precedence_resolution.lua", "integration")
	write_module("shared/precedence_resolution.lua", "shared")
	write_module("lib/precedence_resolution.lua", "legacy")

	local widget_file = assert(io.open(temp_dir .. "/modules.lua", "w"))
	widget_file:write([[
local integration = require("integration_resolution")
local shared = require("shared_resolution")
local legacy = require("legacy_resolution")
local precedence = require("precedence_resolution")
easybar.add(easybar.kind.item, "module-resolution", {
	label = integration .. ":" .. shared .. ":" .. legacy .. ":" .. precedence,
})
]])
	widget_file:close()

	local api = new_api()
	local loaded, failed = loader.load_widgets(temp_dir, { "modules.lua" }, api, log)
	assert(loaded == 1 and failed == 0)
	assert(api._state.items["module-resolution"].props.label.string == "integration:shared:legacy:integration")

	for _, module_name in ipairs({
		"integration_resolution",
		"shared_resolution",
		"legacy_resolution",
		"precedence_resolution",
	}) do
		package.loaded[module_name] = nil
	end
	os.remove(temp_dir .. "/modules.lua")
	os.remove(temp_dir .. "/integrations/integration_resolution.lua")
	os.remove(temp_dir .. "/integrations/precedence_resolution.lua")
	os.remove(temp_dir .. "/shared/shared_resolution.lua")
	os.remove(temp_dir .. "/shared/precedence_resolution.lua")
	os.remove(temp_dir .. "/lib/legacy_resolution.lua")
	os.remove(temp_dir .. "/lib/precedence_resolution.lua")
	os.execute('rmdir "' .. temp_dir .. '/integrations" "' .. temp_dir .. '/shared" "' .. temp_dir .. '/lib"')
	os.execute('rmdir "' .. temp_dir .. '"')
end

-- A failed widget load rolls back nodes, subscriptions, jobs, timers, and inbox handlers.
do
	local temp_dir = os.tmpname() .. "-easybar-widget-test"
	os.remove(temp_dir)
	assert(os.execute('mkdir -p "' .. temp_dir .. '/shared"'))
	local module_file = assert(io.open(temp_dir .. "/shared/rollback_probe.lua", "w"))
	module_file:write("return { loaded = true }\n")
	module_file:close()
	local file = assert(io.open(temp_dir .. "/broken.lua", "w"))
	file:write([[
local probe = require("rollback_probe")
assert(probe.loaded)
local node = easybar.add(easybar.kind.item, "partial", { label = "partial" })
node:subscribe(easybar.events.forced, function() end)
easybar.inbox.on_action("rollback-test", function() end)
easybar.inbox.replace("rollback-test", {})
easybar.exec_async("true", nil, function() end)
easybar.after(10, function() end)
error("intentional widget failure")
]])
	file:close()

	local api = new_api()
	loader.load_widgets(temp_dir, { "broken.lua" }, api, log)
	assert(next(api._state.items) == nil)
	assert(next(api._state.subscriptions) == nil)
	assert(next(api._state.pending_async_commands) == nil)
	assert(next(api._state.pending_timers) == nil)
	assert(next(api._state.inbox_action_handlers) == nil)
	assert(package.loaded.rollback_probe == nil)
	assert(inbox_publish_count == 0)
	assert(#cancelled_commands >= 1)
	assert(#cancelled_timers >= 1)
	os.remove(temp_dir .. "/broken.lua")
	os.remove(temp_dir .. "/shared/rollback_probe.lua")
	os.execute('rmdir "' .. temp_dir .. '/shared"')
	os.execute('rmdir "' .. temp_dir .. '"')
end

-- A failed transaction preserves the identity and disposability of existing registrations.
do
	local temp_dir = os.tmpname() .. "-easybar-existing-state"
	os.remove(temp_dir)
	assert(os.execute('mkdir -p "' .. temp_dir .. '"'))
	local file = assert(io.open(temp_dir .. "/broken.lua", "w"))
	file:write([[easybar.add(easybar.kind.item, "temporary", {})
error("rollback existing state")
]])
	file:close()

	local api = new_api()
	local widget = api.make_widget_api("/widgets/existing.lua")
	local node = widget.add(widget.kind.item, "existing", {})
	local calls = 0
	local handle = node:subscribe(widget.events.forced, function()
		calls = calls + 1
	end)
	loader.load_widgets(temp_dir, { "broken.lua" }, api, log)
	assert(api._state.items.existing ~= nil and api._state.items.temporary == nil)
	api.handle_event({ name = "forced" })
	assert(calls == 1)
	assert(handle:dispose() == true)
	api.handle_event({ name = "forced" })
	assert(calls == 1)

	os.remove(temp_dir .. "/broken.lua")
	os.execute('rmdir "' .. temp_dir .. '"')
end

-- Render graph validation diagnoses dangling parents, cycles, and reserved ids without recursion.
do
	local api = new_api()
	local widget = api.make_widget_api("/widgets/tree.lua")
	widget.add(widget.kind.item, "dangling", { parent = "missing" })
	expect_error("dangling parent=missing", function()
		tree.prepare(api)
	end)
	widget.remove("dangling")

	widget.add(widget.kind.row, "cycle-a", {})
	widget.add(widget.kind.row, "cycle-b", { parent = "cycle-a" })
	widget.set("cycle-a", { parent = "cycle-b" })
	expect_error("parent cycle", function()
		tree.prepare(api)
	end)
	expect_error("reserved internal prefix", function()
		widget.add(widget.kind.item, "__easybar_internal__:collision", {})
	end)
end

print("Lua runtime regression checks passed")
