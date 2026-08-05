-- Executes every bundled top-level widget against a minimal host API.
-- The smoke test catches startup errors, duplicate node ids, and service mix-ups.

local root = assert(arg[1], "repository root argument is required")
local widget_files = {}
for index = 2, #arg do
	widget_files[#widget_files + 1] = arg[index]
end

assert(#widget_files > 0, "at least one bundled widget file is required")

package.path = table.concat({
	root .. "/Sources/EasyBarApp/Lua/?.lua",
	root .. "/widgets/integrations/?.lua",
	root .. "/widgets/integrations/?/init.lua",
	root .. "/widgets/shared/?.lua",
	root .. "/widgets/shared/?/init.lua",
	root .. "/widgets/lib/?.lua",
	root .. "/widgets/lib/?/init.lua",
	root .. "/Sources/EasyBarApp/Lua/?/init.lua",
	package.path,
}, ";")

local all_ids = {}
local ids_by_widget = {}
local nodes_by_widget = {}
local commands_by_widget = {}
local command_callbacks_by_widget = {}

local function basename(path)
	return tostring(path):match("([^/]+)$") or tostring(path)
end

local function callable_noop(extra)
	return setmetatable(extra or {}, {
		__call = function() end,
	})
end

local function make_file_logger()
	return callable_noop({
		append = function()
			return true, nil
		end,
		line = function()
			return true, nil
		end,
		tail = function()
			return ""
		end,
		trim = function()
			return true, nil
		end,
	})
end

local function make_log_api()
	return callable_noop({
		with_prefix = function()
			return callable_noop()
		end,
		with_file = function()
			return make_file_logger()
		end,
	})
end

local function make_node(id, props)
	local node = {
		id = id,
		name = id,
		props = props or {},
		subscriptions = {},
	}

	function node:set(next_props)
		self.props = next_props or {}
	end

	function node:get()
		return self.props
	end

	function node:subscribe(events, handler)
		self.subscriptions[#self.subscriptions + 1] = {
			events = events,
			handler = handler,
		}
	end

	function node:remove()
		self.removed = true
	end

	function node:disable()
		self.disabled = true
	end

	function node:unset() end

	return node
end

local function make_easybar(widget_name)
	ids_by_widget[widget_name] = {}
	nodes_by_widget[widget_name] = {}
	commands_by_widget[widget_name] = {}
	command_callbacks_by_widget[widget_name] = {}

	local theme_refs = setmetatable({}, {
		__index = function(_, key)
			return "theme." .. tostring(key)
		end,
	})

	local easybar = {
		kind = {
			item = "item",
			row = "row",
			column = "column",
			group = "group",
			popup = "popup",
			slider = "slider",
			progress = "progress",
			progress_slider = "progress_slider",
			sparkline = "sparkline",
			spaces = "spaces",
		},
		level = {
			trace = "trace",
			debug = "debug",
			info = "info",
			warn = "warn",
			error = "error",
		},
		theme = {
			ref = theme_refs,
			colors = theme_refs,
		},
		events = {
			forced = "forced",
			system_woke = "system_woke",
			session_active = "session_active",
			network_change = "network_change",
			wifi_change = "wifi_change",
			mouse = {
				entered = "mouse.entered",
				exited = "mouse.exited",
				clicked = "mouse.clicked",
				left_button = "left",
			},
			context_menu = {
				clicked = "context_menu.clicked",
			},
		},
		json = {
			decode = function(value)
				if value == "[]" then
					return {}
				end
				return {}
			end,
		},
		log = make_log_api(),
		inbox = {
			configure = function() end,
			replace = function() end,
			clear = function() end,
			on_action = function() end,
			on_context_action = function() end,
		},
		storage = {
			get = function(_, _, default)
				return default
			end,
			set = function()
				return true, nil
			end,
		},
	}

	function easybar.add(_, id, props)
		assert(type(id) == "string" and id ~= "", widget_name .. " added an invalid node id")
		assert(
			all_ids[id] == nil,
			widget_name .. " duplicated node id '" .. id .. "' first owned by " .. tostring(all_ids[id])
		)
		all_ids[id] = widget_name
		ids_by_widget[widget_name][id] = (ids_by_widget[widget_name][id] or 0) + 1
		local node = make_node(id, props)
		nodes_by_widget[widget_name][id] = node
		return node
	end

	function easybar.default() end

	function easybar.asset(path)
		return root .. "/widgets/" .. tostring(path)
	end

	function easybar.after()
		return {
			cancel = function() end,
		}
	end

	function easybar.cancel_async() end

	function easybar.spawn_async(command, _, callback)
		commands_by_widget[widget_name][#commands_by_widget[widget_name] + 1] = command
		local operation = {
			cancel = function() end,
		}
		if type(callback) == "function" then
			if widget_name == "tailscale.lua" then
				command_callbacks_by_widget[widget_name][#command_callbacks_by_widget[widget_name] + 1] = callback
			else
				callback("smoke-test command disabled", 1)
			end
		end
		return operation
	end

	easybar.exec_async = easybar.spawn_async

	return easybar
end

local function command_contains(command, token)
	if type(command) == "string" then
		return command == token or command:find(token, 1, true) ~= nil
	end
	if type(command) ~= "table" then
		return false
	end
	for _, value in ipairs(command) do
		if tostring(value) == token then
			return true
		end
	end
	return false
end

local function assert_service_identity(widget_name, required_command, forbidden_command)
	local commands = commands_by_widget[widget_name] or {}
	local found_required = false

	for _, command in ipairs(commands) do
		found_required = found_required or command_contains(command, required_command)
		assert(
			not command_contains(command, forbidden_command),
			widget_name .. " unexpectedly invokes " .. forbidden_command
		)
	end

	assert(found_required, widget_name .. " did not invoke " .. required_command .. " during startup")
end

local function assert_expected_ids(widget_name, expected)
	local actual = ids_by_widget[widget_name] or {}
	for _, id in ipairs(expected) do
		assert(actual[id] == 1, widget_name .. " must create node '" .. id .. "' exactly once")
	end

	local actual_count = 0
	for _ in pairs(actual) do
		actual_count = actual_count + 1
	end
	assert(actual_count == #expected, widget_name .. " created an unexpected number of nodes")
end

local function expected_rows(root_id, header_id, row_prefix, footer_id)
	local expected = { root_id, header_id, footer_id }
	for index = 1, 8 do
		expected[#expected + 1] = row_prefix .. tostring(index)
	end
	return expected
end

local function assert_registry_rejects_duplicate_ids()
	local registry_module = assert(loadfile(root .. "/Sources/EasyBarApp/Lua/easybar/registry.lua"))()
	local registry = registry_module.new()
	registry.add("item", "duplicate_smoke_id", {})

	local ok, duplicate_error = pcall(function()
		registry.add("item", "duplicate_smoke_id", {})
	end)
	assert(not ok, "Lua registry accepted a duplicate node id")
	assert(
		tostring(duplicate_error):find("easybar item already exists: duplicate_smoke_id", 1, true) ~= nil,
		"Lua registry returned an unexpected duplicate-id error: " .. tostring(duplicate_error)
	)
end

for _, widget_path in ipairs(widget_files) do
	local widget_name = basename(widget_path)
	local environment = setmetatable({
		easybar = make_easybar(widget_name),
	}, {
		__index = _G,
	})

	local chunk, load_error = loadfile(widget_path, "t", environment)
	assert(chunk, widget_name .. " failed to load: " .. tostring(load_error))

	local ok, runtime_error = pcall(chunk)
	assert(ok, widget_name .. " failed during startup: " .. tostring(runtime_error))
end

assert_service_identity("github.lua", "gh", "glab")
assert_service_identity("gitlab.lua", "glab", "gh")
assert_expected_ids(
	"github.lua",
	expected_rows(
		"github_notifications",
		"github_notifications_header",
		"github_notification_",
		"github_notifications_footer"
	)
)
assert_expected_ids(
	"gitlab.lua",
	expected_rows("gitlab_work_items", "gitlab_work_items_header", "gitlab_work_item_", "gitlab_work_items_footer")
)

-- Bursts of replayed state events should not launch redundant concurrent status reads.
do
	local widget_name = "tailscale.lua"
	local node = assert(nodes_by_widget[widget_name].tailscale_icon)
	assert(#commands_by_widget[widget_name] == 1, "tailscale must start one initial status read")
	for _, subscription in ipairs(node.subscriptions) do
		if type(subscription.events) == "table" then
			subscription.handler()
			subscription.handler()
		end
	end
	assert(#commands_by_widget[widget_name] == 1, "tailscale started overlapping status reads")
	command_callbacks_by_widget[widget_name][1]("{}", 0)
	assert(#commands_by_widget[widget_name] == 2, "tailscale did not run one coalesced follow-up read")
end

assert_registry_rejects_duplicate_ids()

print("Bundled Lua widget smoke test passed for " .. tostring(#widget_files) .. " files")
