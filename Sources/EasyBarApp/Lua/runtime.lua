--- Module contract:
--- Owns Lua process startup, host handshake, and socket-backed standard-stream event processing.
--- Returns nothing and runs the EasyBar Lua runtime loop.
--- Returns the directory containing `runtime.lua`.
local function runtime_dir()
	local source = debug.getinfo(1, "S").source
	if source:sub(1, 1) == "@" then
		source = source:sub(2)
	end
	return source:match("^(.*)/[^/]+$") or "."
end

--- Runtime module root directory.
local base_dir = runtime_dir()
local PROTOCOL_VERSION = 1
--- Adds bundled runtime modules to the Lua module path.
package.path = base_dir .. "/?.lua;" .. package.path

--- Loads one bundled runtime module by name.
local function load_module(name)
	local path = base_dir .. "/easybar/" .. name .. ".lua"
	local chunk, err = loadfile(path)

	if not chunk then
		error("failed to load module '" .. name .. "' from " .. path .. ": " .. tostring(err))
	end

	return chunk()
end

--- Runtime logger module.
local log = load_module("log")
--- Runtime JSON codec module.
local json = load_module("json")
--- Public EasyBar API module.
local api = load_module("api")
--- Widget loader module.
local loader = load_module("loader")
--- Event normalization and dispatch module.
local events = load_module("events")
--- Registry renderer module.
local render = load_module("render")

--- Widget directory and command defaults passed by the Swift host.
local widget_dir = arg[1]
local managed_widget_dir = os.getenv("EASYBAR_INTERNAL_WIDGET_PACKAGES_DIRECTORY")
local default_command_timeout_seconds = tonumber(arg[2]) or 5
local default_command_max_output_bytes = tonumber(arg[3]) or 65536

if not widget_dir or widget_dir == "" then
	local home = os.getenv("HOME")
	widget_dir = home .. "/.config/easybar/widgets"
end

--- Runtime registry and widget API instance.
local registry
local render_dirty = false
local last_subscription_payload = nil
local next_command_sequence = 0
local next_timer_sequence = 0
local next_storage_sequence = 0
local pending_storage_responses = {}
local runtime_command_session = tostring({}):gsub("[^%w]", "_")
local default_exec_options = {
	timeout_seconds = default_command_timeout_seconds,
	max_output_bytes = default_command_max_output_bytes,
}

--- Returns whether the pending tree is already synchronized with the host.
local function should_skip_render(force)
	return not force and not render_dirty
end

--- Returns whether the host already has the current subscription payload.
local function subscriptions_are_current(force, payload)
	return not force and payload == last_subscription_payload
end

--- Marks the current runtime state as needing one render flush.
local function mark_render_dirty()
	render_dirty = true
end

--- Emits the current tree snapshot when a Lua turn mutated widget state.
local function flush_pending_render(force)
	if should_skip_render(force) then
		return
	end

	if render.emit_all(registry, log, json) then
		render_dirty = false
	end
end

--- Emits runtime subscription requirements when they changed.
local function emit_subscriptions(force)
	local payload = json.encode({
		protocol_version = PROTOCOL_VERSION,
		type = "subscriptions",
		events = registry.required_events(),
	})

	if subscriptions_are_current(force, payload) then
		return
	end

	last_subscription_payload = payload
	io.stdout:write(payload .. "\n")
	io.stdout:flush()
end

--- Flushes pending runtime outputs after one logical Lua turn.
local function flush_pending_outputs(force_render, force_subscriptions)
	flush_pending_render(force_render)
	emit_subscriptions(force_subscriptions)
end

--- Sends one structured payload to the Swift host.
local function send_payload(payload)
	io.stdout:write(json.encode(payload) .. "\n")
	io.stdout:flush()
end

--- Returns one unique command token.
local function next_command_token()
	next_command_sequence = next_command_sequence + 1
	return runtime_command_session .. ":" .. tostring(next_command_sequence)
end

--- Returns one unique timer token.
local function next_timer_token()
	next_timer_sequence = next_timer_sequence + 1
	return runtime_command_session .. ":timer:" .. tostring(next_timer_sequence)
end

--- Returns one unique widget-storage request token.
local function next_storage_token()
	next_storage_sequence = next_storage_sequence + 1
	return runtime_command_session .. ":storage:" .. tostring(next_storage_sequence)
end

--- Derives the stable host-log request id for one runtime command token.
local function log_request_id(token)
	local sequence = tostring(token or ""):match("([^:]+)$")
	return sequence ~= nil and "lua-" .. sequence or "lua-unknown"
end

--- Returns normalized command log context with options as a fallback.
local function command_log_context(options, context)
	local widget = type(context) == "table" and context.widget or nil
	local operation = type(context) == "table" and context.operation or nil

	if (type(operation) ~= "string" or operation == "") and type(options) == "table" then
		operation = options.log_operation
	end

	return widget, operation
end

--- Sends one command request to the Swift host.
local function send_command_request(request, synchronous, options, context)
	local token = next_command_token()

	local payload = {
		protocol_version = PROTOCOL_VERSION,
		type = "command_request",
		token = token,
		sync = synchronous == true,
	}

	if type(request) == "table" and request.arguments ~= nil then
		payload.arguments = request.arguments
	else
		payload.command = tostring(request)
	end

	if type(options) == "table" then
		if options.timeout_seconds ~= nil then
			payload.timeout_seconds = options.timeout_seconds
		end

		if options.max_output_bytes ~= nil then
			payload.max_output_bytes = options.max_output_bytes
		end
	end

	local widget, operation = command_log_context(options, context)
	if type(widget) == "string" and widget ~= "" then
		payload.widget = widget
	end
	if type(operation) == "string" and operation ~= "" then
		payload.operation = operation
	end

	send_payload(payload)

	return token
end

--- Dispatches one host command response into the registry and flushes any callback mutations.
local function handle_command_response(payload)
	if type(payload.token) ~= "string" or payload.token == "" then
		log.error("runtime ignored command response missing token")
		return
	end

	local output = payload.output
	if output == nil then
		output = ""
	elseif type(output) ~= "string" then
		output = tostring(output)
	end

	local handled = registry.handle_command_response(payload.token, output, tonumber(payload.status) or 1, {
		duration_ms = tonumber(payload.duration_ms),
	})
	if not handled then
		log.warn("runtime dropped unknown command response token=" .. tostring(payload.token))
	end
	flush_pending_outputs(false, false)
end

--- Retains one synchronous widget-storage response for its waiting API call.
local function handle_storage_response(payload)
	if type(payload.token) ~= "string" or payload.token == "" then
		log.error("runtime ignored storage response missing token")
		return
	end
	pending_storage_responses[payload.token] = payload
end

--- Releases one timer callback rejected by the host.
local function handle_timer_rejected(payload)
	if type(payload.token) ~= "string" or payload.token == "" then
		log.error("runtime ignored timer rejection missing token")
		return
	end

	local handled = registry.handle_timer_rejected(payload.token)
	if handled then
		log.warn(
			"runtime timer rejected token="
				.. tostring(payload.token)
				.. " message="
				.. tostring(payload.message or "unknown")
		)
	else
		log.warn("runtime dropped unknown timer rejection token=" .. tostring(payload.token))
	end
	flush_pending_outputs(false, false)
end

--- Dispatches one host timer response into the registry and flushes callback mutations.
local function handle_timer_fired(payload)
	if type(payload.token) ~= "string" or payload.token == "" then
		log.error("runtime ignored timer response missing token")
		return
	end

	registry.handle_timer_fired(payload.token)
	flush_pending_outputs(false, false)
end

--- Dispatches one JSON-decoded host payload by kind.
local function handle_host_payload(payload, raw_line)
	if type(payload) ~= "table" then
		log.error("runtime ignored non-table host payload bytes=" .. tostring(#raw_line))
		return
	end

	if payload.type == "command_response" then
		handle_command_response(payload)
		return
	end

	if payload.type == "storage_response" then
		handle_storage_response(payload)
		return
	end

	if payload.type == "timer_fired" then
		handle_timer_fired(payload)
		return
	end

	if payload.type == "timer_rejected" then
		handle_timer_rejected(payload)
		return
	end

	if type(payload.name) ~= "string" or payload.name == "" then
		log.error("runtime ignored invalid json payload bytes=" .. tostring(#raw_line))
		return
	end

	local event = events.normalize_event(payload)
	events.dispatch_event(registry, event, function(force_render)
		flush_pending_outputs(force_render, false)
	end, log)
end

--- Reads, decodes, and handles one host payload line.
local function process_next_host_message()
	local line = io.read()

	if not line then
		return false
	end

	local ok, payload = pcall(json.decode, line)

	if not ok then
		log.error("runtime ignored invalid json bytes=" .. tostring(#line))
		return true
	end

	handle_host_payload(payload, line)
	return true
end

--- Runs one host-owned command synchronously and returns raw combined output plus exit code.
local function request_sync_command(command, options, context)
	local token = send_command_request(command, true, options, context)
	registry.expect_sync_command_response(token, options)

	while true do
		local response = registry.take_pending_command_response(token)
		if response ~= nil then
			return response.output, response.code
		end

		if not process_next_host_message() then
			registry.abandon_sync_command_response(token)
			return "", 1
		end
	end
end

--- Performs one synchronous host-owned widget storage request.
local function request_storage(operation, widget, key, value)
	local token = next_storage_token()
	local payload = {
		protocol_version = PROTOCOL_VERSION,
		type = "storage_request",
		token = token,
		operation = operation,
		widget = widget,
		key = key,
	}
	if operation == "set" then
		payload.value = value
	end
	send_payload(payload)

	while true do
		local response = pending_storage_responses[token]
		if response ~= nil then
			pending_storage_responses[token] = nil
			return response
		end
		if not process_next_host_message() then
			return { ok = false, found = false, error = "EasyBar host disconnected" }
		end
	end
end

--- Starts one host-owned asynchronous command and returns its token.
local function request_async_command(command, options, context)
	return send_command_request(command, false, options, context)
end

--- Starts one host-owned asynchronous executable without shell parsing.
local function request_async_process(arguments, options, context)
	return send_command_request({ arguments = arguments }, false, options, context)
end

--- Requests one host-owned one-shot timer.
local function request_timer(delay_seconds)
	local token = next_timer_token()
	send_payload({
		protocol_version = PROTOCOL_VERSION,
		type = "timer_request",
		token = token,
		delay_seconds = delay_seconds,
	})
	return token
end

--- Requests cancellation of one host-owned timer.
local function request_cancel_timer(token)
	send_payload({
		protocol_version = PROTOCOL_VERSION,
		type = "timer_cancel",
		token = token,
	})
end

--- Requests cancellation of one host-owned asynchronous command.
local function request_cancel_async(token)
	send_payload({
		protocol_version = PROTOCOL_VERSION,
		type = "command_cancel",
		token = token,
	})
end

registry = api.new(log, {
	on_mutation = mark_render_dirty,
	before_exec_callback = flush_pending_render,
	before_async_callback = flush_pending_render,
	request_sync_command = request_sync_command,
	request_async_command = request_async_command,
	request_async_process = request_async_process,
	request_cancel_async = request_cancel_async,
	request_timer = request_timer,
	request_cancel_timer = request_cancel_timer,
	--- Reads one setting for the current widget namespace from host storage.
	storage_get = function(widget, key)
		return request_storage("get", widget, key)
	end,
	--- Persists one setting for the current widget namespace through host storage.
	storage_set = function(widget, key, value)
		return request_storage("set", widget, key, value)
	end,
	--- Sends a complete inbox snapshot for one widget-owned source.
	publish_inbox = function(source, items)
		send_payload({
			protocol_version = PROTOCOL_VERSION,
			type = "inbox_replace",
			source = source,
			items = items,
		})
	end,
	--- Clears every inbox item currently published by one widget-owned source.
	clear_inbox = function(source)
		send_payload({
			protocol_version = PROTOCOL_VERSION,
			type = "inbox_clear",
			source = source,
		})
	end,
	--- Publishes source-level inbox actions, ordering, and presentation metadata.
	configure_inbox = function(source, actions, order, presentation)
		send_payload({
			protocol_version = PROTOCOL_VERSION,
			type = "inbox_configure",
			source = source,
			actions = actions,
			order = order,
			presentation = presentation,
		})
	end,
	--- Emits structured diagnostics when one asynchronous command starts.
	on_async_job_started = function(token, command, context, options)
		local suffix = ""
		local widget, operation = command_log_context(options, context)
		if type(widget) == "string" and widget ~= "" then
			suffix = suffix .. " widget=" .. widget
		end
		if type(operation) == "string" and operation ~= "" then
			suffix = suffix .. " operation=" .. operation
		end
		log.trace(
			"async callback registered request_id="
				.. log_request_id(token)
				.. " request_bytes="
				.. tostring(#command)
				.. suffix
		)
	end,
	--- Emits structured completion diagnostics for one asynchronous command.
	on_async_job_completed = function(token, code, context, metadata, options)
		local suffix = ""
		local widget, operation = command_log_context(options, context)
		if type(widget) == "string" and widget ~= "" then
			suffix = suffix .. " widget=" .. widget
		end
		if type(operation) == "string" and operation ~= "" then
			suffix = suffix .. " operation=" .. operation
		end
		if type(metadata) == "table" and tonumber(metadata.duration_ms) ~= nil then
			suffix = suffix .. " duration_ms=" .. tostring(math.floor(tonumber(metadata.duration_ms) + 0.5))
		end
		log.trace("async callback resumed request_id=" .. log_request_id(token) .. " status=" .. tostring(code) .. suffix)
	end,
	--- Reports an exception raised by a widget command callback.
	on_async_callback_error = function(command, err)
		log.error("lua async callback failed request_bytes=" .. tostring(#command) .. " error_type=" .. type(err))
	end,
	--- Reports a command response whose token is no longer pending.
	on_unknown_command_response = function(token)
		log.warn("lua command broker rejected unknown response token=" .. tostring(token))
	end,
	--- Reports invalid values passed through the public widget API.
	on_invalid_public_api = function(path, value, expected)
		log.error(
			"lua rejected invalid public api value path="
				.. tostring(path)
				.. " value_type="
				.. type(value)
				.. " expected="
				.. tostring(expected)
		)
	end,
	default_exec_options = default_exec_options,
})

io.stdout:setvbuf("line")
io.stderr:setvbuf("line")

-- Load package-managed widgets first so their declared modules resolve from the managed store.
if type(managed_widget_dir) == "string" and managed_widget_dir ~= "" then
	api.load_widgets(managed_widget_dir, loader, registry, log)
end

-- Load every manually managed user widget before announcing subscriptions to the host.
api.load_widgets(widget_dir, loader, registry, log)

emit_subscriptions(true)
send_payload({
	protocol_version = PROTOCOL_VERSION,
	type = "ready",
})

-- Emit the full initial widget trees once the runtime handshake is complete.
flush_pending_outputs(true, false)

while process_next_host_message() do
end
