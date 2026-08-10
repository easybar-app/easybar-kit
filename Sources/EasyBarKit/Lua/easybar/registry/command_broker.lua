--- Module contract:
--- Owns synchronous and asynchronous command request state and callbacks.
local M = {}

local MAX_PENDING_ASYNC_COMMANDS = 4096
local MAX_PENDING_SYNC_COMMANDS = 16

--- Applies the requested trailing-line normalization to command output.
local function normalize_output(output, options)
	local value = type(output) == "string" and output or tostring(output or "")
	if options and options.raw_output == true then
		return value
	end
	return (value:gsub("[\r\n]+$", ""))
end

--- Counts entries in a token-keyed state table.
local function count_entries(values)
	local count = 0
	for _ in pairs(values) do
		count = count + 1
	end
	return count
end

--- Builds widget and operation metadata attached to one host command.
local function command_context(widget, options)
	local operation = type(options) == "table" and options.log_operation or nil
	if widget == nil and operation == nil then
		return nil
	end
	return {
		widget = widget,
		operation = operation,
	}
end

--- Creates a broker that owns synchronous responses and asynchronous command callbacks.
---@param state table Shared mutable runtime state.
---@param hooks table Host command request and cancellation callbacks.
---@return table broker Command API used by the registry.
function M.new(state, hooks)
	local broker = {}
	local request_sync_command = hooks.request_sync_command
	local request_async_command = hooks.request_async_command
	local request_async_process = hooks.request_async_process
	local request_cancel_async = hooks.request_cancel_async
	local before_exec_callback = hooks.before_exec_callback
	local before_async_callback = hooks.before_async_callback
	local on_async_job_started = hooks.on_async_job_started
	local on_async_job_completed = hooks.on_async_job_completed
	local on_async_callback_error = hooks.on_async_callback_error
	local on_protocol_warning = hooks.on_protocol_warning
	local normalize_command_options = hooks.normalize_command_options
	local normalize_process_arguments = hooks.normalize_process_arguments
	local fallback_token = hooks.fallback_token

	--- Returns internal event names required while commands are pending.
	function broker.required_driver_events()
		return {}
	end

	--- Reserves one token for a synchronous response awaited by the runtime loop.
	function broker.expect_sync_response(token, options)
		assert(type(token) == "string" and token ~= "", "sync command response requires token")
		assert(state.pending_sync_commands[token] == nil, "duplicate synchronous easybar command token: " .. token)
		assert(
			count_entries(state.pending_sync_commands) < MAX_PENDING_SYNC_COMMANDS,
			"too many pending synchronous easybar commands"
		)
		state.pending_sync_commands[token] = { options = options }
	end

	--- Routes one host response to its synchronous waiter or asynchronous callback.
	function broker.handle_command_response(token, output, code, metadata)
		assert(type(token) == "string" and token ~= "", "command response requires token")
		local raw_output = type(output) == "string" and output or tostring(output or "")
		local normalized_code = tonumber(code) or 1
		local normalized_metadata = type(metadata) == "table" and metadata or {}
		local pending = state.pending_async_commands[token]

		if pending ~= nil then
			state.pending_async_commands[token] = nil
			on_async_job_completed(token, normalized_code, pending.context, normalized_metadata, pending.options)
			before_async_callback()
			local ok, err =
				pcall(pending.callback, normalize_output(raw_output, pending.options), normalized_code, normalized_metadata)
			if not ok then
				on_async_callback_error(pending.command, err)
			end
			return true
		end

		local synchronous = state.pending_sync_commands[token]
		if synchronous then
			state.pending_command_responses[token] = {
				output = normalize_output(raw_output, synchronous.options),
				code = normalized_code,
				metadata = normalized_metadata,
			}
			return true
		end

		on_protocol_warning("ignored unknown command response token=" .. tostring(token))
		return false
	end

	--- Removes and returns a completed synchronous response for one token.
	function broker.take_pending_command_response(token)
		local response = state.pending_command_responses[token]
		if response ~= nil then
			state.pending_command_responses[token] = nil
			state.pending_sync_commands[token] = nil
		end
		return response
	end

	--- Releases a synchronous token that can no longer receive a response.
	function broker.abandon_sync_response(token)
		local existed = state.pending_sync_commands[token] ~= nil or state.pending_command_responses[token] ~= nil
		state.pending_sync_commands[token] = nil
		state.pending_command_responses[token] = nil
		return existed
	end

	--- Registers one asynchronous command and its completion callback.
	local function add_async(token, command, callback, options, context)
		assert(
			count_entries(state.pending_async_commands) < MAX_PENDING_ASYNC_COMMANDS,
			"too many pending asynchronous easybar commands"
		)
		assert(state.pending_async_commands[token] == nil, "duplicate easybar async token: " .. tostring(token))
		state.pending_async_commands[token] = {
			command = command,
			callback = callback,
			options = options,
			context = context,
		}
		on_async_job_started(token, command, context, options)
		return token
	end

	--- Starts a direct executable command on behalf of an optional widget source.
	local function spawn_async(widget, arguments, options, callback, signature)
		assert(type(callback) == "function", signature .. " requires callback")
		assert(type(request_async_process) == "function", "easybar.spawn_async unavailable without host runner")
		local normalized_arguments = normalize_process_arguments(arguments, signature)
		local normalized_options = normalize_command_options(options, signature)
		local context = command_context(widget, normalized_options)
		local token = request_async_process(normalized_arguments, normalized_options, context) or fallback_token("command")
		return add_async(token, table.concat(normalized_arguments, " "), callback, normalized_options, context)
	end

	--- Starts a global direct executable command.
	function broker.spawn_async(arguments, options, callback, ...)
		local signature = "easybar.spawn_async(arguments, options, callback)"
		assert(select("#", ...) == 0, signature .. " does not accept extra arguments")
		return spawn_async(nil, arguments, options, callback, signature)
	end

	--- Starts a widget-scoped direct executable command.
	function broker.spawn_async_for_widget(widget, arguments, options, callback)
		return spawn_async(widget, arguments, options, callback, "easybar.spawn_async(arguments, options, callback)")
	end

	--- Starts an asynchronous shell command on behalf of an optional widget source.
	local function exec_async(widget, command, options, callback, signature)
		assert(type(command) == "string" and command ~= "", signature .. " requires command")
		assert(not command:find("%z"), signature .. " rejects NUL bytes")
		assert(type(callback) == "function", signature .. " requires callback")
		assert(type(request_async_command) == "function", "easybar.exec_async unavailable without host runner")
		local normalized_options = normalize_command_options(options, signature)
		local context = command_context(widget, normalized_options)
		local token = request_async_command(command, normalized_options, context) or fallback_token("command")
		return add_async(token, command, callback, normalized_options, context)
	end

	--- Starts a global asynchronous shell command.
	function broker.exec_async(command, options, callback, ...)
		local signature = "easybar.exec_async(command, options, callback)"
		assert(select("#", ...) == 0, signature .. " does not accept extra arguments")
		return exec_async(nil, command, options, callback, signature)
	end

	--- Starts a widget-scoped asynchronous shell command.
	function broker.exec_async_for_widget(widget, command, options, callback)
		return exec_async(widget, command, options, callback, "easybar.exec_async(command, options, callback)")
	end

	--- Requests cancellation of a pending asynchronous command token.
	function broker.cancel_async(token, ...)
		assert(type(token) == "string" and token ~= "", "easybar.cancel_async(token) requires token")
		assert(select("#", ...) == 0, "easybar.cancel_async(token) does not accept extra arguments")
		assert(type(request_cancel_async) == "function", "easybar.cancel_async unavailable without host runner")
		if state.pending_async_commands[token] == nil then
			return false
		end
		request_cancel_async(token)
		return true
	end

	--- Runs one synchronous shell command for an optional widget source.
	local function exec(widget, command, options, signature)
		assert(type(command) == "string" and command ~= "", signature .. " requires command")
		assert(not command:find("%z"), signature .. " rejects NUL bytes")
		assert(type(request_sync_command) == "function", "easybar.exec unavailable without host runner")
		local normalized_options = normalize_command_options(options, signature)
		local context = command_context(widget, normalized_options)
		before_exec_callback()
		local output, code = request_sync_command(command, normalized_options, context)
		return normalize_output(output, normalized_options), tonumber(code) or 1
	end

	--- Runs one global synchronous shell command.
	function broker.exec(command, options, ...)
		local signature = "easybar.exec(command, options)"
		assert(select("#", ...) == 0, signature .. " does not accept a callback")
		return exec(nil, command, options, signature)
	end

	--- Runs one widget-scoped synchronous shell command.
	function broker.exec_for_widget(widget, command, options)
		return exec(widget, command, options, "easybar.exec(command, options)")
	end

	return broker
end

return M
