-- Minimal EasyBar host used by bundled-widget smoke and focused regression tests.

local M = {}

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

local function event_namespace(prefix, initial)
	return setmetatable(initial or {}, {
		__index = function(table_value, key)
			local value = prefix .. tostring(key)
			rawset(table_value, key, value)
			return value
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

function M.new(root, options)
	options = options or {}
	local shared_ids = options.shared_ids or {}
	local storage_values = options.storage or {}
	local state = {
		commands = {},
		nodes = {},
		timers = {},
	}

	local theme_refs = setmetatable({}, {
		__index = function(_, key)
			return "theme." .. tostring(key)
		end,
	})

	local events = event_namespace("", {
		mouse = event_namespace("mouse.", {
			left_button = "left",
			right_button = "right",
		}),
		context_menu = event_namespace("context_menu."),
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
		events = events,
		json = {
			decode = options.json_decode or function()
				return {}
			end,
			is_array = function(value)
				return type(value) == "table"
			end,
			array = function(value)
				return value
			end,
			object = function(value)
				return value
			end,
			null = {},
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
			get = function(namespace, key, default)
				local value = storage_values[namespace .. ":" .. key]
				return value == nil and default or value
			end,
			set = function(namespace, key, value)
				storage_values[namespace .. ":" .. key] = value
				return true, nil
			end,
		},
	}

	function easybar.add(_, id, props)
		assert(type(id) == "string" and id ~= "", "widget added an invalid node id")
		assert(shared_ids[id] == nil, "duplicate bundled widget node id: " .. id)
		shared_ids[id] = true

		local node = make_node(id, props)
		state.nodes[id] = node
		return node
	end

	function easybar.default() end

	function easybar.asset(path)
		path = tostring(path)
		if path:sub(1, 2) == "@/" then
			path = path:sub(3)
		end
		return root .. "/widgets/" .. path
	end

	function easybar.after(delay, callback)
		local timer = {
			delay = delay,
			callback = callback,
			cancelled = false,
		}
		function timer:cancel()
			self.cancelled = true
			return true
		end
		state.timers[#state.timers + 1] = timer
		return timer
	end

	local function record_command(command, options_value, callback, synchronous)
		local record = {
			command = command,
			options = options_value,
			callback = callback,
			synchronous = synchronous,
		}
		state.commands[#state.commands + 1] = record
		return record
	end

	function easybar.spawn_async(command, options_value, callback)
		local record = record_command(command, options_value, callback, false)
		record.token = "command-" .. tostring(#state.commands)
		return record.token
	end

	easybar.exec_async = easybar.spawn_async

	function easybar.exec(command, options_value)
		record_command(command, options_value, nil, true)
		return "", 1
	end

	function easybar.cancel_async()
		return true
	end

	function state:node(id)
		return self.nodes[id]
	end

	function state:emit(node_id, event_name, payload)
		local node = assert(self.nodes[node_id], "missing node: " .. tostring(node_id))
		for _, subscription in ipairs(node.subscriptions) do
			local subscribed = type(subscription.events) == "table" and subscription.events or { subscription.events }
			for _, candidate in ipairs(subscribed) do
				if candidate == event_name then
					subscription.handler(payload or {})
					return
				end
			end
		end
		error("node " .. tostring(node_id) .. " is not subscribed to " .. tostring(event_name))
	end

	function state:command_contains(index, token)
		local record = assert(self.commands[index], "missing command " .. tostring(index))
		return command_contains(record.command, token)
	end

	function state:has_command(token)
		for _, record in ipairs(self.commands) do
			if command_contains(record.command, token) then
				return true
			end
		end
		return false
	end

	function state:complete_command(index, output, code)
		local record = assert(self.commands[index], "missing command " .. tostring(index))
		assert(type(record.callback) == "function", "command has no callback")
		record.callback(output or "", code or 0, { duration_ms = 1 })
	end

	return easybar, state
end

return M
