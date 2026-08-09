--- Module contract:
--- Owns recursive widget discovery and the public EasyBar Lua API surface.
--- Returns a registry-like object consumed by the loader, events, and renderer.

--- Public EasyBar API module table.
local M = {}

--- Directory containing this module and its siblings.
local base_dir = debug.getinfo(1, "S").source:match("^@(.*/)")

--- Loads one sibling runtime module.
local function load_module(name)
	local chunk, err = loadfile(base_dir .. name .. ".lua")

	if not chunk then
		error("failed to load easybar module '" .. name .. "': " .. tostring(err))
	end

	return chunk()
end

--- Event token module used by node subscriptions.
local event_tokens = load_module("event_tokens")
--- JSON helper module exposed through the public widget API.
local json_module = load_module("json")
--- Active theme module exposed through the public widget API.
local theme_module = load_module("theme")
--- Registry module used to store widget node state.
local registry_module = load_module("registry")
--- Subscription module used for event and interval callbacks.
local subscriptions_module = load_module("subscriptions")
--- Shared finite numeric validators.
local validation = load_module("validation")

--- Supported widget log levels.
local LOG_LEVELS = {
	trace = "trace",
	debug = "debug",
	info = "info",
	warn = "warn",
	error = "error",
}

--- Supported EasyBar node kinds.
local KINDS = {
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
}

--- Internal environment variable containing the configured logging directory.
local LOG_DIR_ENV = "EASYBAR_INTERNAL_LOGGING_DIRECTORY"

--- Joins log arguments into one message string.
local function join_message(...)
	local parts = {}

	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end

	return table.concat(parts, " ")
end

--- Returns one normalized uppercase host log level.
local function normalize_log_level(level)
	if type(level) ~= "string" then
		return "INFO"
	end

	local normalized = LOG_LEVELS[string.lower(level)]
	if normalized == nil then
		return "INFO"
	end

	return string.upper(normalized)
end

--- Returns the configured log directory exposed to Lua widgets.
local function configured_log_dir()
	local configured = os.getenv(LOG_DIR_ENV)
	if type(configured) == "string" and configured ~= "" then
		return configured
	end
	return (os.getenv("HOME") or "/tmp") .. "/.local/state/easybar"
end

--- Returns a validated, whitespace-trimmed inbox source.
local function normalize_inbox_source(source)
	assert(type(source) == "string", "inbox source must be a non-empty string")
	local normalized = source:match("^%s*(.-)%s*$")
	assert(normalized ~= "", "inbox source must be a non-empty string")
	return normalized
end

local MAX_WIDGET_LOG_SCAN_BYTES = 8 * 1024 * 1024
local WIDGET_LOG_READ_CHUNK_BYTES = 32 * 1024

local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function normalize_widget_root(widget_dir)
	assert(type(widget_dir) == "string" and widget_dir ~= "", "widget directory must be a non-empty string")

	local root = widget_dir
	while #root > 1 and root:sub(-1) == "/" do
		root = root:sub(1, -2)
	end
	return root
end

local function relative_widget_path(root, path)
	if root == "/" then
		if path:sub(1, 1) ~= "/" then
			return nil
		end
		return path:sub(2)
	end

	local prefix = root .. "/"
	if path:sub(1, #prefix) ~= prefix then
		return nil
	end
	return path:sub(#prefix + 1)
end

--- Recursively returns every regular Lua file below the configured widget directory.
--- Paths are relative to the widget directory and sorted for deterministic startup.
function M.discover_widget_files(widget_dir)
	local root = normalize_widget_root(widget_dir)
	local quoted_root = shell_quote(root)
	local command = "if [ -d "
		.. quoted_root
		.. " ]; then /usr/bin/find "
		.. quoted_root
		.. " \\( -path "
		.. shell_quote(root .. "/.easybar")
		.. " -o -path "
		.. shell_quote(root .. "/shared")
		.. " -o -path "
		.. shell_quote(root .. "/lib")
		.. " \\) -prune -o"
		.. " -type f -iname "
		.. shell_quote("*.lua")
		.. " -print0; fi"
	local pipe, open_error = io.popen(command, "r")
	if pipe == nil then
		return nil, "could not start widget discovery: " .. tostring(open_error)
	end

	local output = pipe:read("*a") or ""
	local close_ok, close_reason, close_code = pipe:close()
	if close_ok ~= true and close_ok ~= 0 then
		return nil, "widget discovery failed reason=" .. tostring(close_reason) .. " status=" .. tostring(close_code)
	end

	local files = {}
	for path in output:gmatch("([^%z]+)%z") do
		local relative = relative_widget_path(root, path)
		if relative ~= nil and relative ~= "" and relative:sub(-4):lower() == ".lua" then
			files[#files + 1] = relative
		end
	end

	table.sort(files)
	return files, nil
end

--- Discovers and transactionally loads every Lua file below the widget directory.
function M.load_widgets(widget_dir, loader, registry, log)
	local files, discovery_error = M.discover_widget_files(widget_dir)
	if files == nil then
		log.error("runtime widget discovery failed error=" .. tostring(discovery_error))
		return 0, 1
	end

	log.debug("runtime widget_files=" .. tostring(#files))
	return loader.load_widgets(widget_dir, files, registry, log)
end

local ensured_log_directories = {}

local function ensure_log_directory(log_dir)
	log_dir = tostring(log_dir or configured_log_dir())
	if ensured_log_directories[log_dir] then
		return true, nil
	end
	local ok, reason, status = os.execute("mkdir -p -- " .. shell_quote(log_dir))
	if ok == true or ok == 0 then
		ensured_log_directories[log_dir] = true
		return true, nil
	end
	return false, "mkdir failed reason=" .. tostring(reason) .. " status=" .. tostring(status)
end

--- Returns a safe widget log file name, or nil plus an error message.
local function validate_log_file_name(file_name)
	file_name = tostring(file_name or "")
	if file_name == "" then
		return nil, "log file name is required"
	end
	if file_name == "." or file_name == ".." then
		return nil, "log file name must be a plain file name"
	end
	if file_name:find("/", 1, true) or file_name:find("\\", 1, true) then
		return nil, "log file name must not contain path separators"
	end
	if file_name:find("%z") or file_name:find("[\r\n]") then
		return nil, "log file name must not contain control characters"
	end
	return file_name, nil
end

local function widget_log_path(log_dir, file_name)
	return tostring(log_dir or configured_log_dir()) .. "/" .. file_name
end

local function append_widget_log(log_dir, file_name, text)
	local validated, validation_error = validate_log_file_name(file_name)
	if validated == nil then
		return false, validation_error
	end
	local directory_ok, directory_error = ensure_log_directory(log_dir)
	if not directory_ok then
		return false, directory_error
	end
	local file, err = io.open(widget_log_path(log_dir, validated), "a")
	if file == nil then
		return false, tostring(err)
	end
	text = tostring(text or "")
	local wrote, write_error = file:write(text)
	if wrote and (text == "" or text:sub(-1) ~= "\n") then
		wrote, write_error = file:write("\n")
	end
	file:close()
	if not wrote then
		return false, tostring(write_error)
	end
	return true, nil
end

local function read_widget_log_tail(log_dir, file_name, limit)
	local validated, validation_error = validate_log_file_name(file_name)
	if validated == nil then
		return nil, validation_error
	end
	local normalized_limit = validation.positive_integer(limit)
	if normalized_limit == nil then
		return {}, nil
	end
	local file = io.open(widget_log_path(log_dir, validated), "rb")
	if file == nil then
		return {}, nil
	end
	local size = file:seek("end") or 0
	local position = size
	local scanned = 0
	local chunks = {}
	local newline_count = 0
	while position > 0 and newline_count <= normalized_limit and scanned < MAX_WIDGET_LOG_SCAN_BYTES do
		local chunk_size = math.min(WIDGET_LOG_READ_CHUNK_BYTES, position, MAX_WIDGET_LOG_SCAN_BYTES - scanned)
		position = position - chunk_size
		file:seek("set", position)
		local chunk = file:read(chunk_size) or ""
		table.insert(chunks, 1, chunk)
		scanned = scanned + #chunk
		local _, count = chunk:gsub("\n", "")
		newline_count = newline_count + count
	end
	file:close()
	local text = table.concat(chunks)
	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	if text:sub(-1) == "\n" and #lines > 0 and lines[#lines] == "" then
		lines[#lines] = nil
	end
	local start = math.max(1, #lines - normalized_limit + 1)
	local tail = {}
	for index = start, #lines do
		tail[#tail + 1] = lines[index]
	end
	return tail, nil
end

local function write_widget_log_lines(log_dir, file_name, lines)
	local validated, validation_error = validate_log_file_name(file_name)
	if validated == nil then
		return false, validation_error
	end
	local directory_ok, directory_error = ensure_log_directory(log_dir)
	if not directory_ok then
		return false, directory_error
	end
	local file, err = io.open(widget_log_path(log_dir, validated), "w")
	if file == nil then
		return false, tostring(err)
	end
	for _, line in ipairs(lines or {}) do
		local wrote, write_error = file:write(tostring(line or ""), "\n")
		if not wrote then
			file:close()
			return false, tostring(write_error)
		end
	end
	file:close()
	return true, nil
end

local function tail_widget_log(log_dir, file_name, limit)
	local lines, err = read_widget_log_tail(log_dir, file_name, limit)
	if lines == nil then
		return "", err
	end
	return table.concat(lines, "\n"), nil
end

local function trim_widget_log(log_dir, file_name, limit)
	local normalized_limit = validation.non_negative_number(limit)
	if normalized_limit == nil or math.floor(normalized_limit) ~= normalized_limit then
		return false, "log trim limit must be a finite non-negative integer"
	end
	if normalized_limit == 0 then
		return write_widget_log_lines(log_dir, file_name, {})
	end
	local lines, err = read_widget_log_tail(log_dir, file_name, normalized_limit)
	if lines == nil then
		return false, err
	end
	return write_widget_log_lines(log_dir, file_name, lines)
end

--- Returns one shallow copy of props without `on_interval`.
local function strip_interval_handler(props)
	if type(props) ~= "table" then
		return props
	end

	local copy = {}

	for key, value in pairs(props) do
		if key ~= "on_interval" then
			copy[key] = value
		end
	end

	return copy
end

--- Returns whether one interval value is valid.
local function valid_interval(value)
	return validation.interval_seconds(value) ~= nil
end

local function widget_log_source(source, widget_root)
	local path = tostring(source or ""):gsub("\\", "/")
	local root = tostring(widget_root or ""):gsub("\\", "/"):gsub("/+$", "")

	if root ~= "" and path:sub(1, #root + 1) == root .. "/" then
		path = path:sub(#root + 2)
	else
		path = path:match("([^/]+)$") or path
	end

	path = path:gsub("^%./", "")
	if path:sub(-4):lower() == ".lua" then
		path = path:sub(1, -5)
	end
	if path == "" then
		return "lua"
	end
	return path
end

--- Returns one validated widget-storage path segment.
local function normalize_storage_segment(value, description)
	assert(type(value) == "string", description .. " must be a string")
	assert(value ~= "", description .. " must not be empty")
	assert(#value <= 128, description .. " must be at most 128 bytes")
	assert(value:match("^[%w_-]+$") ~= nil, description .. " may contain only letters, numbers, underscores, and hyphens")
	return value
end

--- Validates a value supported by the host TOML storage bridge.
local function validate_storage_value(value)
	local value_type = type(value)
	if value_type == "string" or value_type == "boolean" then
		return
	end
	if value_type == "number" then
		assert(value == value and value ~= math.huge and value ~= -math.huge, "storage number must be finite")
		return
	end
	if value_type == "table" and json_module.is_array(value) then
		for _, item in ipairs(value) do
			assert(type(item) == "string", "storage arrays may contain only strings")
		end
		return
	end
	error("storage value must be a string, boolean, finite number, or string array")
end

--- Builds one widget-scoped EasyBar API instance.
function M.new(log, hooks)
	local registry = registry_module.new(hooks)
	local subscriptions = subscriptions_module.new(registry._state, registry.ensure_item_exists, log, event_tokens)
	local default_exec_options = type(hooks.default_exec_options) == "table" and hooks.default_exec_options or {}
	local log_dir = configured_log_dir()

	local function readonly_copy(values, name)
		local copy = {}

		for key, value in pairs(values) do
			copy[key] = value
		end

		local proxy = {}

		return setmetatable(proxy, {
			__index = copy,
			__newindex = function()
				error(tostring(name) .. " is read-only")
			end,
			__pairs = function()
				return pairs(copy)
			end,
			__metatable = false,
		})
	end

	local function log_widget(source, level, ...)
		if not log or type(log.widget) ~= "function" then
			return
		end

		log.widget(source or "widget", normalize_log_level(level), join_message(...))
	end

	local function log_file_warning(source, message, err)
		log_widget(source, "warn", "widget log file", message, tostring(err or "unknown error"))
	end

	local function file_log_line(level, prefix, ...)
		local normalized_level = string.lower(normalize_log_level(level))
		local message
		if type(prefix) == "string" and prefix ~= "" then
			message = join_message(prefix, ...)
		else
			message = join_message(...)
		end

		return os.date("%Y-%m-%dT%H:%M:%S%z") .. " [" .. normalized_level .. "] " .. message
	end

	local function log_widget_with_prefix(source, level, prefix, ...)
		if type(prefix) == "string" and prefix ~= "" then
			log_widget(source, level, prefix, ...)
		else
			log_widget(source, level, ...)
		end
	end

	local function make_prefixed_logger(source, prefix)
		if type(prefix) ~= "string" then
			error("log prefix must be a string")
		end

		return setmetatable({}, {
			__call = function(_, level, ...)
				log_widget_with_prefix(source, level, prefix, ...)
			end,
		})
	end

	local function make_file_logger(source, file_name, options)
		local validated, validation_error = validate_log_file_name(file_name)
		if validated == nil then
			error(validation_error)
		end

		options = type(options) == "table" and options or {}
		local prefix = type(options.prefix) == "string" and options.prefix or nil
		local logger = {}

		function logger.append(text)
			return append_widget_log(log_dir, validated, text)
		end

		function logger.line(text)
			return append_widget_log(log_dir, validated, tostring(text or ""))
		end

		function logger.tail(limit)
			local tail, err = tail_widget_log(log_dir, validated, limit)
			if err ~= nil then
				log_file_warning(source, "tail failed", err)
			end
			return tail
		end

		function logger.trim(limit)
			return trim_widget_log(log_dir, validated, limit)
		end

		return setmetatable(logger, {
			__call = function(_, level, ...)
				log_widget_with_prefix(source, level, prefix, ...)

				local ok, err = append_widget_log(log_dir, validated, file_log_line(level, prefix, ...))
				if not ok then
					log_file_warning(source, "append failed", err)
				end

				return ok, err
			end,
		})
	end

	local function make_log_api(source)
		local logger = {}

		function logger.with_prefix(prefix)
			return make_prefixed_logger(source, prefix)
		end

		function logger.with_file(file_name, options)
			return make_file_logger(source, file_name, options)
		end

		return setmetatable(logger, {
			__call = function(_, level, ...)
				log_widget(source, level, ...)
			end,
		})
	end

	local function required_events()
		local merged = {}

		for _, event_name in ipairs(subscriptions.required_events()) do
			merged[event_name] = true
		end

		for _, event_name in ipairs(registry.required_driver_events()) do
			merged[event_name] = true
		end

		local result = {}

		for event_name in pairs(merged) do
			result[#result + 1] = event_name
		end

		table.sort(result)
		return result
	end

	local function handler_snapshot(handlers)
		local copy = {}
		for index, handler in ipairs(handlers or {}) do
			copy[index] = handler
		end
		return copy
	end

	local function handle_event(event)
		if event.name == "inbox.action" then
			local handlers = registry._state.inbox_action_handlers[tostring(event.source or "")]
			for _, entry in ipairs(handler_snapshot(handlers)) do
				local handler = type(entry) == "table" and entry.active and entry.handler or entry
				local ok, err = true, nil
				if type(handler) == "function" then
					ok, err = pcall(handler, event)
				end
				if not ok then
					log.error("inbox action handler failed source=" .. tostring(event.source) .. " error=" .. tostring(err))
				end
			end
		end
		if event.name == "inbox.context_action" then
			local handlers = registry._state.inbox_context_action_handlers[tostring(event.source or "")]
			for _, entry in ipairs(handler_snapshot(handlers)) do
				local handler = type(entry) == "table" and entry.active and entry.handler or entry
				local ok, err = true, nil
				if type(handler) == "function" then
					ok, err = pcall(handler, event)
				end
				if not ok then
					log.error(
						"inbox context action handler failed source=" .. tostring(event.source) .. " error=" .. tostring(err)
					)
				end
			end
		end
		subscriptions.handle_event(event)
	end

	local api = {
		_state = registry._state,
		add = registry.add,
		begin_widget_load = registry.begin_widget_load,
		commit_widget_load = registry.commit_widget_load,
		rollback_widget_load = registry.rollback_widget_load,
		DEFAULT_EXEC_OPTIONS = readonly_copy(default_exec_options, "easybar.DEFAULT_EXEC_OPTIONS"),
		set = registry.set,
		unset = registry.unset,
		get = registry.get,
		remove = registry.remove,
		exec = registry.exec,
		exec_async = registry.exec_async,
		spawn_async = registry.spawn_async,
		cancel_async = registry.cancel_async,
		after = registry.after,
		handle_command_response = registry.handle_command_response,
		expect_sync_command_response = registry.expect_sync_response,
		abandon_sync_command_response = registry.abandon_sync_response,
		handle_timer_fired = registry.handle_timer_fired,
		handle_timer_rejected = registry.handle_timer_rejected,
		take_pending_command_response = registry.take_pending_command_response,
		subscribe = subscriptions.subscribe,
		handle_event = handle_event,
		required_events = required_events,
		log_dir = log_dir,
		theme = theme_module.current(),
	}

	--- Returns one widget-scoped EasyBar API.
	--- Defaults are isolated to this widget instance.
	function api.make_widget_api(widget_source, widget_root)
		local widget_api = {}
		local widget_defaults = {}
		local source_directory = tostring(widget_source):match("^(.*)/[^/]+$") or "."
		widget_root = tostring(widget_root or source_directory)
		local widget_name = widget_log_source(widget_source, widget_root)

		--- Resolves one safe path relative to this widget's source directory.
		function widget_api.asset(path)
			if type(path) ~= "string" or path == "" then
				error("easybar.asset(path) requires a non-empty relative path")
			end

			if path:sub(1, 1) == "/" then
				error("easybar.asset(path) rejects absolute paths")
			end

			local base_directory = source_directory
			local relative_path = path
			if path:sub(1, 2) == "@/" then
				base_directory = widget_root
				relative_path = path:sub(3)
			end

			local segments = {}
			for segment in relative_path:gmatch("[^/]+") do
				if segment == ".." then
					if #segments == 0 then
						error("easybar.asset(path) cannot escape its asset root")
					end
					segments[#segments] = nil
				elseif segment ~= "." then
					segments[#segments + 1] = segment
				end
			end

			if #segments == 0 then
				error("easybar.asset(path) requires a non-empty relative path")
			end

			return base_directory .. "/" .. table.concat(segments, "/")
		end

		--- Merges properties into one item and optionally updates its interval callback.
		local function set_node(id, props)
			local interval_handler = type(props) == "table" and props.on_interval or nil
			local item_props = strip_interval_handler(props)
			local merged = registry.merge_props(api.get(id), item_props or {})

			if interval_handler ~= nil then
				assert(valid_interval(merged.interval), "on_interval requires interval > 0")
			end

			api.set(id, item_props)

			if type(props) == "table" and props.interval ~= nil then
				subscriptions.reset_interval_schedule(id)
			end

			if interval_handler ~= nil then
				subscriptions.set_interval_handler(id, interval_handler)
			end
		end

		--- Builds one node handle for the public object-style API.
		local function make_node_handle(id)
			local handle = {
				id = id,
				name = id,
			}

			--- Merges properties into this node.
			function handle:set(props)
				return set_node(self.id, props)
			end

			--- Returns a copy of this node's current properties.
			function handle:get()
				return api.get(self.id)
			end

			--- Removes this node and all descendants.
			function handle:remove()
				return api.remove(self.id)
			end

			--- Removes one or more nested properties from this node.
			function handle:unset(paths)
				return api.unset(self.id, paths)
			end

			--- Subscribes this node to one or more events.
			function handle:subscribe(events, handler)
				return subscriptions.subscribe(self.id, events, handler)
			end

			return handle
		end

		--- Sets defaults for future add(...) calls in this widget only.
		function widget_api.default(props)
			widget_defaults = registry.merge_props(widget_defaults, props or {})
		end

		--- Clears defaults for this widget only.
		function widget_api.clear_defaults()
			widget_defaults = {}
		end

		--- Merges properties into one existing node by id.
		function widget_api.set(id, props)
			return set_node(id, props)
		end

		--- Returns a copy of one existing node's current properties.
		function widget_api.get(id)
			return api.get(id)
		end

		--- Removes one or more nested properties from one existing node.
		function widget_api.unset(id, paths)
			return api.unset(id, paths)
		end

		--- Removes one existing node and all descendants.
		function widget_api.remove(id)
			return api.remove(id)
		end

		--- Subscribes one existing node to one or more events.
		function widget_api.subscribe(id, events, handler)
			return subscriptions.subscribe(id, events, handler)
		end

		--- Adds one item using this widget's scoped defaults.
		function widget_api.add(kind, id, props)
			local interval_handler = type(props) == "table" and props.on_interval or nil
			local item_props = strip_interval_handler(props)
			local merged = registry.merge_props(widget_defaults, item_props or {})

			if interval_handler ~= nil then
				assert(valid_interval(merged.interval), "on_interval requires interval > 0")
			elseif type(props) == "table" and props.interval ~= nil then
				error("interval requires on_interval")
			end

			registry.add(kind, id, item_props, widget_defaults, widget_source)

			if interval_handler ~= nil then
				subscriptions.set_interval_handler(id, interval_handler)
			end

			return make_node_handle(id)
		end

		function widget_api.exec(command, options, ...)
			assert(select("#", ...) == 0, "easybar.exec(command, options) does not accept a callback")
			return registry.exec_for_widget(widget_name, command, options)
		end

		function widget_api.exec_async(command, options, callback, ...)
			assert(select("#", ...) == 0, "easybar.exec_async(command, options, callback) does not accept extra arguments")
			return registry.exec_async_for_widget(widget_name, command, options, callback)
		end

		function widget_api.spawn_async(arguments, options, callback, ...)
			assert(select("#", ...) == 0, "easybar.spawn_async(arguments, options, callback) does not accept extra arguments")
			return registry.spawn_async_for_widget(widget_name, arguments, options, callback)
		end

		widget_api.cancel_async = api.cancel_async
		widget_api.after = api.after
		widget_api.DEFAULT_EXEC_OPTIONS = api.DEFAULT_EXEC_OPTIONS
		widget_api.events = event_tokens.tokens
		widget_api.json = json_module
		widget_api.kind = KINDS
		widget_api.level = LOG_LEVELS
		widget_api.log_dir = api.log_dir
		widget_api.theme = theme_module.current()
		widget_api.inbox = {}
		widget_api.storage = {}

		function widget_api.storage.get(widget, key, default)
			widget = normalize_storage_segment(widget, "storage widget")
			key = normalize_storage_segment(key, "storage key")
			local response = hooks.storage_get(widget, key)
			if type(response) ~= "table" or response.ok ~= true then
				error(
					"easybar.storage.get failed: "
						.. tostring(type(response) == "table" and response.error or "invalid host response")
				)
			end
			if response.found == true then
				return response.value
			end
			return default
		end

		function widget_api.storage.set(widget, key, value)
			widget = normalize_storage_segment(widget, "storage widget")
			key = normalize_storage_segment(key, "storage key")
			validate_storage_value(value)
			local response = hooks.storage_set(widget, key, value)
			if type(response) ~= "table" or response.ok ~= true then
				return false, tostring(type(response) == "table" and response.error or "invalid host response")
			end
			return true, nil
		end

		function widget_api.inbox.replace(source, items)
			source = normalize_inbox_source(source)
			assert(json_module.is_array(items), "inbox items must be a dense array")
			registry.defer_side_effect(function()
				hooks.publish_inbox(source, items)
			end)
		end

		function widget_api.inbox.clear(source)
			source = normalize_inbox_source(source)
			registry.defer_side_effect(function()
				hooks.clear_inbox(source)
			end)
		end

		function widget_api.inbox.configure(source, configuration)
			source = normalize_inbox_source(source)
			assert(type(configuration) == "table", "inbox configuration must be a table")
			local actions = configuration.actions or {}
			local action_count = 0
			local function validate_actions(values, depth)
				assert(json_module.is_array(values), "inbox configuration actions must be dense arrays")
				assert(depth <= 3, "inbox configuration actions support at most three levels")
				for _, action in ipairs(values) do
					assert(type(action) == "table", "inbox configuration actions must be tables")
					action_count = action_count + 1
					assert(action_count <= 32, "inbox configuration supports at most 32 actions")
					if action.children ~= nil then
						assert(#action.children > 0, "inbox action children must not be empty")
						validate_actions(action.children, depth + 1)
					end
				end
			end
			validate_actions(actions, 1)
			local order = configuration.order
			local presentation = configuration.presentation
			assert(
				order == nil
					or (type(order) == "number" and order == math.floor(order) and order >= -2147483648 and order <= 2147483647),
				"inbox configuration order must be a 32-bit integer"
			)
			assert(presentation == nil or type(presentation) == "table", "inbox configuration presentation must be a table")
			registry.defer_side_effect(function()
				hooks.configure_inbox(source, actions, order, presentation)
			end)
		end

		local function register_inbox_handler(storage, source, handler, description)
			source = normalize_inbox_source(source)
			assert(type(handler) == "function", description .. " must be a function")
			storage[source] = storage[source] or {}
			local entry = { handler = handler, active = true }
			table.insert(storage[source], entry)
			local handle = {}
			function handle:unsubscribe()
				if not entry.active then
					return false
				end
				entry.active = false
				local handlers = storage[source] or {}
				for index = #handlers, 1, -1 do
					if handlers[index] == entry then
						table.remove(handlers, index)
					end
				end
				if #handlers == 0 then
					storage[source] = nil
				end
				return true
			end
			handle.dispose = handle.unsubscribe
			return handle
		end

		function widget_api.inbox.on_action(source, handler)
			return register_inbox_handler(registry._state.inbox_action_handlers, source, handler, "inbox action handler")
		end

		function widget_api.inbox.on_context_action(source, handler)
			return register_inbox_handler(
				registry._state.inbox_context_action_handlers,
				source,
				handler,
				"inbox context action handler"
			)
		end

		widget_api.log = make_log_api(widget_name)

		return widget_api
	end

	return api
end

return M
