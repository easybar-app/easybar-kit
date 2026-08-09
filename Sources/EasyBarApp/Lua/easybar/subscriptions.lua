--- Module contract:
--- Owns event subscriptions, interval scheduling, handler disposal, and stable dispatch snapshots.
local M = {}
local helpers = require("easybar.helpers")
local validation = require("easybar.validation")

local INTERVAL_TICK_PREFIX = "interval_tick:"

--- Creates a detached event payload targeted at one subscribed node.
local function make_handler_event(id, event)
	local handler_event = helpers.deep_copy(event)
	handler_event.widget_id = id
	if handler_event.target_widget_id == nil and event.widget_id ~= nil then
		handler_event.target_widget_id = event.widget_id
	end
	return handler_event
end

--- Copies an array before dispatch so handlers may mutate subscriptions safely.
local function snapshot_array(values)
	local copy = {}
	for index, value in ipairs(values or {}) do
		copy[index] = value
	end
	return copy
end

--- Returns whether a targeted event should be delivered to one item id.
local function should_dispatch_to_target(target, id)
	return target == nil or target == id
end

--- Returns whether the source owner still requires one non-duplicate delivery.
local function should_dispatch_to_owner(owner, target, id, dispatched)
	return owner ~= nil and owner ~= target and owner == id and not dispatched[id]
end

--- Creates subscription, interval, and event-dispatch services for the registry.
---@param state table Shared registry state.
---@param ensure_item_exists fun(id:string) Node identity validator.
---@param log table Runtime logger.
---@param event_tokens table Event token normalization helpers.
---@return table subscriptions Subscription service API.
function M.new(state, ensure_item_exists, log, event_tokens)
	local subscriptions = {}

	--- Invokes a stable snapshot of handlers registered for one item and event.
	local function dispatch_handlers_for(id, event)
		local bucket = state.subscriptions[id]
		if bucket == nil then
			return
		end
		local handlers = bucket[event.name]
		if type(handlers) ~= "table" then
			return
		end
		local handler_event = make_handler_event(id, event)
		for _, entry in ipairs(snapshot_array(handlers)) do
			if entry.active and type(entry.handler) == "function" then
				local ok, err = pcall(entry.handler, handler_event)
				if not ok and log then
					log.error(
						"lua handler failed id=" .. tostring(id) .. " event=" .. tostring(event.name) .. " error=" .. tostring(err)
					)
				end
			end
		end
	end

	--- Routes one event to its explicit target and source owner without duplicates.
	local function dispatch_targeted(event)
		local owner = event.widget_id
		local target = event.target_widget_id or owner
		local dispatched = {}
		for _, id in ipairs(snapshot_array(state.item_order)) do
			if state.items[id] ~= nil then
				if should_dispatch_to_target(target, id) then
					dispatch_handlers_for(id, event)
					dispatched[id] = true
				end
				if should_dispatch_to_owner(owner, target, id, dispatched) then
					dispatch_handlers_for(id, event)
				end
			end
		end
	end

	--- Invokes one node's configured interval callback with error isolation.
	local function dispatch_interval_handler_for(id)
		local handler = state.interval_handlers[id]
		if type(handler) ~= "function" then
			return
		end
		local ok, err = pcall(handler, { name = "interval", widget_id = id })
		if not ok and log then
			log.error("lua interval handler failed id=" .. tostring(id) .. " error=" .. tostring(err))
		end
	end

	--- Replaces the repeating interval callback owned by one node.
	function subscriptions.set_interval_handler(id, handler)
		ensure_item_exists(id)
		assert(type(handler) == "function", "on_interval must be a function")
		state.interval_handlers[id] = handler
	end

	--- Validates a node before its host-managed interval schedule is reset.
	function subscriptions.reset_interval_schedule(id)
		ensure_item_exists(id)
	end

	--- Registers one handler for normalized event tokens and returns a disposable handle.
	function subscriptions.subscribe(id, events, handler)
		ensure_item_exists(id)
		assert(type(handler) == "function", "node:subscribe(events, handler) requires handler")
		if type(events) == "table" and type(events.name) == "string" then
			events = { events }
		end
		assert(type(events) == "table", "node:subscribe(events, handler) requires events")

		local event_names = {}
		local seen = {}
		for _, event in ipairs(events) do
			local event_name = event_tokens.normalize(event)
			if not seen[event_name] then
				seen[event_name] = true
				event_names[#event_names + 1] = event_name
			end
		end
		assert(#event_names > 0, "node:subscribe(events, handler) requires at least one event")

		state.next_subscription_id = (state.next_subscription_id or 0) + 1
		local entry = {
			id = state.next_subscription_id,
			handler = handler,
			active = true,
		}
		local bucket = state.subscriptions[id] or {}
		state.subscriptions[id] = bucket
		for _, event_name in ipairs(event_names) do
			bucket[event_name] = bucket[event_name] or {}
			bucket[event_name][#bucket[event_name] + 1] = entry
		end

		local handle = {}
		--- Removes this handler registration once and reports whether it was active.
		function handle:unsubscribe()
			if not entry.active then
				return false
			end
			entry.active = false
			local current_bucket = state.subscriptions[id]
			if current_bucket ~= nil then
				for _, event_name in ipairs(event_names) do
					local handlers = current_bucket[event_name]
					if handlers ~= nil then
						for index = #handlers, 1, -1 do
							if handlers[index] == entry then
								table.remove(handlers, index)
							end
						end
						if #handlers == 0 then
							current_bucket[event_name] = nil
						end
					end
				end
				if next(current_bucket) == nil then
					state.subscriptions[id] = nil
				end
			end
			return true
		end
		handle.dispose = handle.unsubscribe
		return handle
	end

	--- Dispatches one normalized host event to targeted or broadcast subscribers.
	function subscriptions.handle_event(event)
		if event.name == "interval_tick" then
			local target = event.widget_id or event.target_widget_id
			if target ~= nil then
				dispatch_interval_handler_for(target)
			end
		end
		dispatch_targeted(event)
	end

	--- Returns the sorted host event set currently required by active subscriptions.
	function subscriptions.required_events()
		local events = {}
		for _, id in ipairs(state.item_order) do
			local bucket = state.subscriptions[id]
			if bucket then
				for event_name in pairs(bucket) do
					if event_tokens.driver_events[event_name] then
						events[event_name] = true
					end
				end
			end
		end
		for _, id in ipairs(state.item_order) do
			local item = state.items[id]
			local handler = state.interval_handlers[id]
			if item ~= nil and type(handler) == "function" then
				local interval = validation.interval_seconds(item.props.interval)
				if interval ~= nil then
					events[INTERVAL_TICK_PREFIX .. tostring(id) .. ":" .. tostring(interval)] = true
				end
			end
		end
		local result = {}
		for event_name in pairs(events) do
			result[#result + 1] = event_name
		end
		table.sort(result)
		return result
	end

	return subscriptions
end

return M
