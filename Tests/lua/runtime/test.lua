local root = assert(arg[1], "usage: Tests/lua/runtime/test.lua <repository-root>")
package.path = root .. "/Sources/EasyBarApp/Lua/?.lua;" .. root .. "/Sources/EasyBarApp/Lua/?/init.lua;" .. package.path

local lua_root = root .. "/Sources/EasyBarApp/Lua/easybar/"

---@class RuntimeFixtures
---@field cleanup fun(path: string)
---@field discovery fun(): string
---@field module_resolution fun(): string
---@field rollback fun(): string
---@field existing_state fun(): string

---@type RuntimeFixtures
local fixtures = assert(loadfile(root .. "/Tests/lua/runtime/fixtures.lua"))()

---@type { keys: string[] }
local theme_tokens_module = assert(loadfile(lua_root .. "theme_tokens.lua"))()
local theme_tokens = theme_tokens_module.keys
local json = assert(loadfile(lua_root .. "json.lua"))()
local colors = {}
for _, key in ipairs(theme_tokens) do
	colors[key] = "#000000"
end
local test_theme_json = json.encode({ name = "test", colors = colors })
local real_getenv = os.getenv
rawset(os, "getenv", function(name)
	if name == "EASYBAR_INTERNAL_THEME_JSON" then
		return test_theme_json
	end
	if name == "EASYBAR_INTERNAL_LOGGING_DIRECTORY" then
		return "/tmp"
	end
	return real_getenv(name)
end)

local api_module = require("easybar.api")
local loader = require("easybar.loader")
local tree = require("easybar.render.tree")

---@param value any
---@param expected string
local function assert_contains(value, expected)
	assert(
		tostring(value):find(expected, 1, true),
		"expected '" .. tostring(value) .. "' to contain '" .. expected .. "'"
	)
end

---@param expected string
---@param body fun()
local function expect_error(expected, body)
	local ok, err = pcall(body)
	assert(not ok, "expected error containing: " .. expected)
	assert_contains(err, expected)
end

---@class RuntimeCommandContext
---@field widget string
---@field operation? string

---@class RuntimeCommandOptions
---@field log_operation? string

---@class RuntimeCompletionMetadata
---@field duration_ms? number

---@class RuntimeLogEntry
---@field source string
---@field level string
---@field message string

---@type string[]
local cancelled_commands = {}
---@type string[]
local cancelled_timers = {}
local async_sequence = 0
local timer_sequence = 0
---@type string[]
local warnings = {}
local inbox_publish_count = 0
---@type RuntimeLogEntry[]
local source_logs = {}
---@type RuntimeCommandContext?
local last_command_context = nil
---@type RuntimeCommandOptions?
local last_async_hook_options = nil
---@type RuntimeCommandOptions?
local last_completed_hook_options = nil
---@type table<string, any>
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
		source_logs[#source_logs + 1] = {
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
		storage_get = function(namespace, key)
			local value = storage_values[namespace .. ":" .. key]
			return { ok = true, found = value ~= nil, value = value }
		end,
		storage_set = function(namespace, key, value)
			storage_values[namespace .. ":" .. key] = value
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

-- Storage APIs validate namespace segments and return defaults for missing values.
do
	local api = new_api()
	local source = api.make_widget_api("/fixtures/storage.lua")
	assert(source.storage.get("sample", "mode", "default") == "default")
	assert(source.storage.set("sample", "mode", "alternate") == true)
	assert(source.storage.get("sample", "mode") == "alternate")
	expect_error("storage widget", function()
		source.storage.get("../outside", "mode")
	end)
	expect_error("finite", function()
		source.storage.set("sample", "bad_number", math.huge)
	end)
end

-- Log source names are derived from synthetic source paths relative to their configured root.
do
	local api = new_api()
	local source = api.make_widget_api("/fixtures/storage.lua", "/fixtures")
	source.log(source.level.debug, "refresh started")
	local entry = assert(source_logs[#source_logs])
	assert(entry.source == "storage")
	assert(entry.level == "DEBUG")
	assert(entry.message == "refresh started")

	local packaged = api.make_widget_api("/fixtures/package/status.lua", "/fixtures")
	packaged.log(packaged.level.debug, "package refresh started")
	entry = assert(source_logs[#source_logs])
	assert(entry.source == "package/status")
	assert(entry.message == "package refresh started")

	local nested = api.make_widget_api("/fixtures/nested/main.lua", "/fixtures")
	nested.log(nested.level.debug, "nested refresh started")
	entry = assert(source_logs[#source_logs])
	assert(entry.source == "nested/main")
	assert(entry.message == "nested refresh started")

	local uppercase_extension = api.make_widget_api("/fixtures/tools/STATUS.LUA", "/fixtures")
	uppercase_extension.log(uppercase_extension.level.debug, "uppercase extension")
	entry = assert(source_logs[#source_logs])
	assert(entry.source == "tools/STATUS")
	assert(entry.message == "uppercase extension")
end

-- Duplicate ids identify both source owners and do not overwrite the first node.
do
	local api = new_api()
	local first = api.make_widget_api("/fixtures/first.lua")
	local second = api.make_widget_api("/fixtures/second.lua")
	first.add(first.kind.item, "duplicate", { label = "first" })
	expect_error("owner=/fixtures/first.lua", function()
		second.add(second.kind.item, "duplicate", { label = "second" })
	end)
	assert(api._state.items.duplicate.source == "/fixtures/first.lua")
	assert(api._state.items.duplicate.props.label.string == "first")
end

-- Dispatch snapshots handlers and disposable registrations affect only future turns.
do
	local api = new_api()
	local source = api.make_widget_api("/fixtures/subscriptions.lua")
	local node = source.add(source.kind.item, "subscription-node", {})
	local first_calls = 0
	local late_calls = 0
	local late_handle
	local first_handle = node:subscribe(source.events.forced, function()
		first_calls = first_calls + 1
		if late_handle == nil then
			late_handle = node:subscribe(source.events.forced, function()
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
	assert(assert(late_handle):dispose() == true)
end

-- Numeric command, timer, and interval options reject non-finite and excessive values consistently.
do
	local api = new_api()
	local source = api.make_widget_api("/fixtures/validation.lua")
	expect_error("finite", function()
		source.exec("true", { timeout_seconds = math.huge })
	end)
	expect_error("positive integer", function()
		source.exec("true", { max_output_bytes = 1.5 })
	end)
	expect_error("finite", function()
		source.after(0 / 0, function() end)
	end)
	expect_error("on_interval requires interval > 0", function()
		source.add(source.kind.item, "bad-interval", {
			interval = math.huge,
			on_interval = function() end,
		})
	end)
	local trimmed = source.exec("true")
	local raw = source.exec("true", { raw_output = true })
	assert(trimmed == "trimmed")
	assert(raw == "raw\r\n")
end

-- Commands propagate diagnostic source context and completion metadata.
do
	local api = new_api()
	local source = api.make_widget_api("/fixtures/commands.lua")
	---@type RuntimeCompletionMetadata?
	local completed = nil
	local token = source.spawn_async({ "printf", "ok" }, { log_operation = "refresh" }, function(_, _, metadata)
		completed = metadata
	end)

	local command_context = assert(last_command_context)
	assert(command_context.widget == "commands")
	assert(command_context.operation == "refresh")
	assert(assert(last_async_hook_options).log_operation == "refresh")
	assert(api.handle_command_response(token, "ok", 0, { duration_ms = 42 }) == true)
	assert(assert(last_completed_hook_options).log_operation == "refresh")
	assert(assert(completed).duration_ms == 42)
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

-- Runtime source discovery includes every regular Lua file recursively.
do
	local fixture_root = fixtures.discovery()
	local files, discovery_error = api_module.discover_widget_files(fixture_root)
	assert(discovery_error == nil)
	assert(files ~= nil)
	assert(table.concat(files, "|") == ".hidden.lua|assets/preview.lua|clock.lua|nested/STATUS.LUA")

	local missing, missing_error = api_module.discover_widget_files(fixture_root .. "/missing")
	assert(missing_error == nil)
	assert(missing ~= nil and #missing == 0)
	fixtures.cleanup(fixture_root)
end

-- Runtime module resolution prefers package-local modules, then shared modules, then the legacy lib fallback.
do
	local fixture_root = fixtures.module_resolution()
	local api = new_api()
	local loaded, failed = loader.load_widgets(fixture_root, { "source.lua" }, api, log)
	assert(loaded == 1 and failed == 0)
	local module_node = assert(api._state.items["module-resolution"])
	assert(module_node.props.label.string == "package:shared:legacy:package")

	for _, module_name in ipairs({
		"package.policy",
		"shared_resolution",
		"legacy_resolution",
		"precedence_resolution",
	}) do
		package.loaded[module_name] = nil
	end
	fixtures.cleanup(fixture_root)
end

-- A failed synthetic source load rolls back nodes, subscriptions, jobs, timers, and inbox handlers.
do
	local fixture_root = fixtures.rollback()
	local api = new_api()
	loader.load_widgets(fixture_root, { "broken.lua" }, api, log)
	assert(next(api._state.items) == nil)
	assert(next(api._state.subscriptions) == nil)
	assert(next(api._state.pending_async_commands) == nil)
	assert(next(api._state.pending_timers) == nil)
	assert(next(api._state.inbox_action_handlers) == nil)
	assert(package.loaded.rollback_probe == nil)
	assert(inbox_publish_count == 0)
	assert(#cancelled_commands >= 1)
	assert(#cancelled_timers >= 1)
	fixtures.cleanup(fixture_root)
end

-- A failed transaction preserves the identity and disposability of existing registrations.
do
	local fixture_root = fixtures.existing_state()
	local api = new_api()
	local source = api.make_widget_api("/fixtures/existing.lua")
	local node = source.add(source.kind.item, "existing", {})
	local calls = 0
	local handle = node:subscribe(source.events.forced, function()
		calls = calls + 1
	end)
	loader.load_widgets(fixture_root, { "broken.lua" }, api, log)
	assert(api._state.items.existing ~= nil and api._state.items.temporary == nil)
	api.handle_event({ name = "forced" })
	assert(calls == 1)
	assert(handle:dispose() == true)
	api.handle_event({ name = "forced" })
	assert(calls == 1)
	fixtures.cleanup(fixture_root)
end

-- Render graph validation diagnoses dangling parents, cycles, and reserved ids without recursion.
do
	local api = new_api()
	local source = api.make_widget_api("/fixtures/tree.lua")
	source.add(source.kind.item, "dangling", { parent = "missing" })
	expect_error("dangling parent=missing", function()
		tree.prepare(api)
	end)
	source.remove("dangling")

	source.add(source.kind.row, "cycle-a", {})
	source.add(source.kind.row, "cycle-b", { parent = "cycle-a" })
	source.set("cycle-a", { parent = "cycle-b" })
	expect_error("parent cycle", function()
		tree.prepare(api)
	end)
	expect_error("reserved internal prefix", function()
		source.add(source.kind.item, "__easybar_internal__:collision", {})
	end)
end

print("Lua runtime regression checks passed")
