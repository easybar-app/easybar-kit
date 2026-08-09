--- Module contract:
--- Composes item storage, command/timer brokers, load transactions, and public normalization.
local M = {}
local helpers = require("easybar.helpers")
local validation = require("easybar.validation")
local item_store_module = require("easybar.registry.item_store")
local command_broker_module = require("easybar.registry.command_broker")
local timer_broker_module = require("easybar.registry.timer_broker")
local graph = require("easybar.registry.graph")

--- Returns all arguments unchanged for optional hook defaults.
local function noop(...)
	return ...
end

--- Reports one invalid public value and raises a caller-facing validation error.
local function invalid_public_value(path, value, expected, report)
	report(path, value, expected)
	error(
		"invalid easybar value for " .. tostring(path) .. ": expected " .. tostring(expected) .. ", got " .. tostring(value),
		3
	)
end

--- Normalizes public boolean values, including the supported `on` and `off` aliases.
local function normalize_bool(value, default, path, report)
	if value == nil then
		return default
	end
	if value == true or value == "on" then
		return true
	end
	if value == false or value == "off" then
		return false
	end
	return invalid_public_value(path, value, "true, false, 'on', or 'off'", report)
end

--- Converts scalar text props into the structured renderer representation.
local function normalize_string_prop(value)
	if value == nil then
		return nil
	end
	if type(value) == "table" then
		return value
	end
	return { string = tostring(value) }
end

local MAX_INLINE_SVG_BYTES = 256 * 1024
local MAX_CONTEXT_MENU_DEPTH = 8
local MAX_CONTEXT_MENU_ITEMS = 256
local MAX_CONTEXT_MENU_TEXT_BYTES = 1024

--- Returns whether a context-menu title or action id is valid and bounded.
local function is_valid_context_menu_text(value)
	return type(value) == "string" and value ~= "" and #value <= MAX_CONTEXT_MENU_TEXT_BYTES
end

--- Returns whether an image attempts to use both a file path and inline SVG.
local function has_conflicting_image_sources(image)
	return image.path ~= nil and image.svg ~= nil
end

--- Normalizes a context-menu boolean while reporting invalid values non-fatally.
local function normalize_menu_bool(value, default, path, report)
	if value == nil then
		return default
	elseif value == true or value == "on" then
		return true
	elseif value == false or value == "off" then
		return false
	end
	report(path, value, "true, false, 'on', or 'off'")
	return default
end

--- Validates and bounds a nested context menu for host transport.
local function normalize_context_menu(menu, path, report)
	if type(menu) ~= "table" then
		report(path, menu, "array of context menu entries")
		return {}
	end

	local item_count = 0
	local action_ids = {}
	--- Recursively normalizes context-menu entries within depth and item limits.
	local function normalize_entries(entries, entry_path, depth)
		if depth > MAX_CONTEXT_MENU_DEPTH then
			report(entry_path, entries, "context menu nesting at most 8 levels")
			return {}
		end

		local normalized = {}
		for index, entry in ipairs(entries) do
			item_count = item_count + 1
			local current_path = entry_path .. "[" .. tostring(index) .. "]"
			if item_count > MAX_CONTEXT_MENU_ITEMS then
				report(current_path, entry, "at most 256 context menu entries")
				break
			elseif type(entry) ~= "table" then
				report(current_path, entry, "context menu entry table")
			elseif entry.separator == true then
				normalized[#normalized + 1] = { separator = true }
			else
				local title = entry.title
				local submenu = entry.submenu
				local has_submenu = type(submenu) == "table"
				local id = entry.id
				if not is_valid_context_menu_text(title) then
					report(current_path .. ".title", title, "non-empty string at most 1024 UTF-8 bytes")
				elseif has_submenu then
					local children = normalize_entries(submenu, current_path .. ".submenu", depth + 1)
					if id ~= nil then
						report(current_path .. ".id", id, "no id on submenu headings")
					elseif #children == 0 then
						report(current_path .. ".submenu", submenu, "non-empty valid submenu")
					else
						normalized[#normalized + 1] = { title = title, submenu = children }
					end
				elseif not is_valid_context_menu_text(id) then
					report(current_path .. ".id", id, "non-empty string at most 1024 UTF-8 bytes")
				else
					if action_ids[id] then
						report(current_path .. ".id", id, "unique action id within this context menu")
					end
					action_ids[id] = true
					normalized[#normalized + 1] = {
						id = id,
						title = title,
						enabled = normalize_menu_bool(entry.enabled, true, current_path .. ".enabled", report),
						checked = normalize_menu_bool(entry.checked, false, current_path .. ".checked", report),
					}
				end
			end
		end
		return normalized
	end

	return normalize_entries(menu, path, 1)
end

--- Validates one image property and removes unsafe or conflicting sources.
local function normalize_image_prop(image, path, report)
	if type(image) ~= "table" then
		return image
	end
	if has_conflicting_image_sources(image) then
		report(path, image, "path or svg, but not both")
		image.path = nil
		image.svg = nil
		return image
	end
	if image.path ~= nil and type(image.path) ~= "string" then
		report(path .. ".path", image.path, "string")
		image.path = nil
	end
	if image.svg ~= nil then
		if type(image.svg) ~= "string" or image.svg == "" then
			report(path .. ".svg", image.svg, "non-empty SVG string")
			image.svg = nil
		elseif #image.svg > MAX_INLINE_SVG_BYTES then
			report(path .. ".svg", image.svg, "SVG string at most 262144 UTF-8 bytes")
			image.svg = nil
		end
	end
	return image
end

--- Produces a detached, host-safe node property table.
local function normalize_props(props, report)
	local normalized = helpers.deep_copy(props or {})
	if normalized.label ~= nil then
		normalized.label = normalize_string_prop(normalized.label)
	end
	if normalized.icon ~= nil then
		normalized.icon = normalize_string_prop(normalized.icon)
		if type(normalized.icon) == "table" then
			normalized.icon.image = normalize_image_prop(normalized.icon.image, "icon.image", report)
		end
	end
	normalized.image = normalize_image_prop(normalized.image, "image", report)
	if normalized.context_menu ~= nil then
		normalized.context_menu = normalize_context_menu(normalized.context_menu, "context_menu", report)
	end
	if normalized.drawing ~= nil then
		normalized.drawing = normalize_bool(normalized.drawing, true, "drawing", report)
	end
	if type(normalized.popup) == "table" and normalized.popup.drawing ~= nil then
		normalized.popup.drawing = normalize_bool(normalized.popup.drawing, false, "popup.drawing", report)
	end
	return normalized
end

local COMMAND_OPTION_KEYS = {
	timeout_seconds = true,
	max_output_bytes = true,
	raw_output = true,
	log_operation = true,
}

--- Validates command limits and logging metadata for one public API signature.
local function normalize_command_options(options, signature)
	if options == nil then
		return nil
	end
	assert(type(options) == "table", signature .. " requires options table or nil")
	local normalized = {}
	for key in pairs(options) do
		assert(
			COMMAND_OPTION_KEYS[key] == true,
			signature
				.. " received unknown option '"
				.. tostring(key)
				.. "'; expected timeout_seconds, max_output_bytes, raw_output, or log_operation"
		)
	end
	if options.timeout_seconds ~= nil then
		local timeout = validation.positive_number(options.timeout_seconds, validation.MAX_COMMAND_TIMEOUT_SECONDS)
		assert(timeout ~= nil, signature .. " requires finite options.timeout_seconds > 0")
		normalized.timeout_seconds = timeout
	end
	if options.max_output_bytes ~= nil then
		local max_output = validation.positive_integer(options.max_output_bytes, validation.MAX_COMMAND_OUTPUT_BYTES)
		assert(max_output ~= nil, signature .. " requires finite options.max_output_bytes as positive integer")
		normalized.max_output_bytes = max_output
	end
	if options.raw_output ~= nil then
		assert(type(options.raw_output) == "boolean", signature .. " requires options.raw_output as boolean")
		normalized.raw_output = options.raw_output
	end
	if options.log_operation ~= nil then
		assert(type(options.log_operation) == "string", signature .. " requires options.log_operation as string")
		local operation = options.log_operation:match("^%s*(.-)%s*$")
		assert(operation ~= "", signature .. " requires non-empty options.log_operation")
		assert(#operation <= 128, signature .. " limits options.log_operation to 128 bytes")
		assert(not operation:find("%z"), signature .. " rejects NUL bytes in options.log_operation")
		assert(not operation:find("[\r\n\t]"), signature .. " rejects control characters in options.log_operation")
		normalized.log_operation = operation
	end
	return next(normalized) and normalized or nil
end

--- Validates and copies one dense executable argument array.
local function normalize_process_arguments(arguments, signature)
	assert(type(arguments) == "table", signature .. " requires an argument array")
	local normalized = {}
	local length = #arguments
	for key in pairs(arguments) do
		assert(
			type(key) == "number" and key >= 1 and key <= length and math.floor(key) == key,
			signature .. " requires a dense argument array"
		)
	end
	for index, value in ipairs(arguments) do
		assert(type(value) == "string", signature .. " requires string arguments")
		assert(not value:find("%z"), signature .. " rejects NUL bytes")
		normalized[index] = value
	end
	assert(#normalized > 0 and normalized[1] ~= "", signature .. " requires a non-empty executable")
	return normalized
end

--- Returns a shallow copy of one key-value table.
local function copy_map(values)
	local copy = {}
	for key, value in pairs(values or {}) do
		copy[key] = value
	end
	return copy
end

--- Copies event handler buckets while preserving active-state snapshots.
local function copy_handler_buckets(values, active_states)
	local copy = {}
	for owner, bucket in pairs(values or {}) do
		local bucket_copy = {}
		for event_name, handlers in pairs(bucket) do
			local handler_copy = {}
			for index, entry in ipairs(handlers) do
				handler_copy[index] = entry
				if type(entry) == "table" then
					active_states[entry] = entry.active
				end
			end
			bucket_copy[event_name] = handler_copy
		end
		copy[owner] = bucket_copy
	end
	return copy
end

--- Copies flat handler lists while preserving active-state snapshots.
local function copy_handler_lists(values, active_states)
	local copy = {}
	for owner, handlers in pairs(values or {}) do
		local handler_copy = {}
		for index, entry in ipairs(handlers) do
			handler_copy[index] = entry
			if type(entry) == "table" then
				active_states[entry] = entry.active
			end
		end
		copy[owner] = handler_copy
	end
	return copy
end

--- Captures mutable registry state for transactional widget loading.
local function snapshot_state(state)
	local active_states = {}
	return {
		items = helpers.deep_copy(state.items),
		item_order = helpers.deep_copy(state.item_order),
		subscriptions = copy_handler_buckets(state.subscriptions, active_states),
		interval_handlers = copy_map(state.interval_handlers),
		pending_async_commands = copy_map(state.pending_async_commands),
		pending_sync_commands = copy_map(state.pending_sync_commands),
		pending_command_responses = copy_map(state.pending_command_responses),
		pending_timers = copy_map(state.pending_timers),
		inbox_action_handlers = copy_handler_lists(state.inbox_action_handlers, active_states),
		inbox_context_action_handlers = copy_handler_lists(state.inbox_context_action_handlers, active_states),
		next_subscription_id = state.next_subscription_id,
		active_states = active_states,
	}
end

--- Restores all mutable registry state from a transaction snapshot.
local function restore_state(state, snapshot)
	state.items = helpers.deep_copy(snapshot.items)
	state.item_order = helpers.deep_copy(snapshot.item_order)
	state.subscriptions = snapshot.subscriptions
	state.interval_handlers = snapshot.interval_handlers
	state.pending_async_commands = snapshot.pending_async_commands
	state.pending_sync_commands = snapshot.pending_sync_commands
	state.pending_command_responses = snapshot.pending_command_responses
	state.pending_timers = snapshot.pending_timers
	state.inbox_action_handlers = snapshot.inbox_action_handlers
	state.inbox_context_action_handlers = snapshot.inbox_context_action_handlers
	state.next_subscription_id = snapshot.next_subscription_id
	for entry, active in pairs(snapshot.active_states or {}) do
		entry.active = active
	end
end

--- Returns one new registry object.
--- Creates the runtime registry and composes its item, command, timer, and subscription services.
---@param hooks? table Host callbacks used for commands, timers, storage, inbox, and diagnostics.
---@return table registry Runtime registry exposed to the loader and renderer.
function M.new(hooks)
	hooks = hooks or {}
	local on_mutation = type(hooks.on_mutation) == "function" and hooks.on_mutation or noop
	local before_exec_callback = type(hooks.before_exec_callback) == "function" and hooks.before_exec_callback or noop
	local before_async_callback = type(hooks.before_async_callback) == "function" and hooks.before_async_callback or noop
	local on_async_job_started = type(hooks.on_async_job_started) == "function" and hooks.on_async_job_started or noop
	local on_async_job_completed = type(hooks.on_async_job_completed) == "function" and hooks.on_async_job_completed
		or noop
	local on_async_callback_error = type(hooks.on_async_callback_error) == "function" and hooks.on_async_callback_error
		or noop
	local on_invalid_public_api = type(hooks.on_invalid_public_api) == "function" and hooks.on_invalid_public_api or noop
	local on_protocol_warning = type(hooks.on_protocol_warning) == "function" and hooks.on_protocol_warning or noop
	local request_cancel_async = type(hooks.request_cancel_async) == "function" and hooks.request_cancel_async or nil
	local request_cancel_timer = type(hooks.request_cancel_timer) == "function" and hooks.request_cancel_timer or nil

	local state = {
		items = {},
		item_order = {},
		subscriptions = {},
		interval_handlers = {},
		pending_async_commands = {},
		pending_sync_commands = {},
		pending_command_responses = {},
		pending_timers = {},
		inbox_action_handlers = {},
		inbox_context_action_handlers = {},
		next_subscription_id = 0,
	}
	local active_transaction = nil
	local token_counter = 0
	local token_session = tostring({}):gsub("[^%w]", "_")
	local registry = { _state = state }

	--- Returns the widget source currently owning a load transaction.
	local function current_source()
		return active_transaction and active_transaction.source or nil
	end

	--- Creates a deterministic fallback token when a host request hook omits one.
	local function fallback_token(kind)
		token_counter = token_counter + 1
		return token_session .. ":" .. tostring(kind) .. ":" .. tostring(token_counter)
	end

	local item_store = item_store_module.new(state, {
		--- Normalizes item props and reports validation failures through host hooks.
		normalize_props = function(props)
			return normalize_props(props, on_invalid_public_api)
		end,
		on_mutation = on_mutation,
		current_source = current_source,
	})
	local command_broker = command_broker_module.new(state, {
		request_sync_command = type(hooks.request_sync_command) == "function" and hooks.request_sync_command or nil,
		request_async_command = type(hooks.request_async_command) == "function" and hooks.request_async_command or nil,
		request_async_process = type(hooks.request_async_process) == "function" and hooks.request_async_process or nil,
		request_cancel_async = request_cancel_async,
		before_exec_callback = before_exec_callback,
		before_async_callback = before_async_callback,
		on_async_job_started = on_async_job_started,
		on_async_job_completed = on_async_job_completed,
		on_async_callback_error = on_async_callback_error,
		on_protocol_warning = on_protocol_warning,
		normalize_command_options = normalize_command_options,
		normalize_process_arguments = normalize_process_arguments,
		fallback_token = fallback_token,
	})
	local timer_broker = timer_broker_module.new(state, {
		request_timer = type(hooks.request_timer) == "function" and hooks.request_timer or nil,
		request_cancel_timer = request_cancel_timer,
		before_async_callback = before_async_callback,
		on_async_callback_error = on_async_callback_error,
		fallback_token = fallback_token,
	})

	registry.ensure_item_exists = item_store.ensure_item_exists
	registry.merge_props = item_store.merge_props
	--- Adds one normalized node and applies interval behavior atomically.
	function registry.add(kind, id, props, defaults, source)
		return item_store.add(kind, id, props, defaults, source or current_source())
	end
	registry.set = item_store.set
	registry.get = item_store.get
	registry.remove = item_store.remove
	registry.unset = item_store.unset
	registry.required_driver_events = command_broker.required_driver_events
	registry.expect_sync_response = command_broker.expect_sync_response
	registry.handle_command_response = command_broker.handle_command_response
	registry.take_pending_command_response = command_broker.take_pending_command_response
	registry.abandon_sync_response = command_broker.abandon_sync_response
	registry.spawn_async = command_broker.spawn_async
	registry.spawn_async_for_widget = command_broker.spawn_async_for_widget
	registry.exec_async = command_broker.exec_async
	registry.exec_async_for_widget = command_broker.exec_async_for_widget
	registry.cancel_async = command_broker.cancel_async
	registry.exec = command_broker.exec
	registry.exec_for_widget = command_broker.exec_for_widget
	registry.after = timer_broker.after
	registry.handle_timer_fired = timer_broker.handle_timer_fired
	registry.handle_timer_rejected = timer_broker.handle_timer_rejected

	--- Validates the complete node graph and raises on structural errors.
	function registry.validate()
		graph.build(state)
		return true
	end

	--- Begins a widget transaction and snapshots registry state for rollback.
	function registry.begin_widget_load(source)
		assert(active_transaction == nil, "nested easybar widget load transaction")
		local loaded_modules = {}
		for name in pairs(package.loaded) do
			loaded_modules[name] = true
		end
		active_transaction = {
			source = tostring(source or "<unknown>"),
			snapshot = snapshot_state(state),
			loaded_modules = loaded_modules,
			deferred_side_effects = {},
		}
		return active_transaction
	end

	--- Defers a host side effect until the active widget transaction commits.
	function registry.defer_side_effect(effect)
		assert(type(effect) == "function", "deferred side effect must be a function")
		if active_transaction ~= nil then
			active_transaction.deferred_side_effects[#active_transaction.deferred_side_effects + 1] = effect
			return
		end
		effect()
	end

	--- Validates and commits the active widget transaction and its deferred effects.
	function registry.commit_widget_load(transaction)
		assert(transaction ~= nil and transaction == active_transaction, "invalid easybar widget load transaction")
		registry.validate()
		active_transaction = nil
		for _, effect in ipairs(transaction.deferred_side_effects) do
			local ok, err = pcall(effect)
			if not ok then
				on_protocol_warning(
					"widget load side effect failed source=" .. tostring(transaction.source) .. " error=" .. tostring(err)
				)
			end
		end
	end

	--- Restores the snapshot owned by the active widget transaction.
	function registry.rollback_widget_load(transaction)
		assert(transaction ~= nil and transaction == active_transaction, "invalid easybar widget load transaction")
		for token in pairs(state.pending_async_commands) do
			if transaction.snapshot.pending_async_commands[token] == nil and request_cancel_async ~= nil then
				pcall(request_cancel_async, token)
			end
		end
		for token in pairs(state.pending_timers) do
			if transaction.snapshot.pending_timers[token] == nil and request_cancel_timer ~= nil then
				pcall(request_cancel_timer, token)
			end
		end
		restore_state(state, transaction.snapshot)
		for name in pairs(package.loaded) do
			if not transaction.loaded_modules[name] then
				package.loaded[name] = nil
			end
		end
		active_transaction = nil
		on_mutation()
	end

	return registry
end

return M
