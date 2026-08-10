--- Module contract:
--- Owns host-event normalization and runtime dispatch into the registry.
--- Returns helpers that validate payloads and trigger re-renders.
--- Event dispatch module table.
local M = {}
--- Shared table-copy helpers.
local helpers = require("easybar.helpers")

--- Returns a validated canonical Lua event table.
function M.normalize_event(payload)
	assert(type(payload) == "table", "event payload must be a table")
	assert(type(payload.name) == "string" and payload.name ~= "", "event payload missing name")

	local event = helpers.deep_copy(payload)

	if event.widget_id ~= nil then
		event.widget_id = tostring(event.widget_id)
	end

	if event.target_widget_id ~= nil then
		event.target_widget_id = tostring(event.target_widget_id)
	end

	if event.app_name ~= nil then
		event.app_name = tostring(event.app_name)
	end

	if event.button ~= nil then
		event.button = tostring(event.button)
	end

	if event.direction ~= nil then
		event.direction = tostring(event.direction)
	end

	if event.action_id ~= nil then
		event.action_id = tostring(event.action_id)
	end

	if event.delta_x ~= nil then
		event.delta_x = tonumber(event.delta_x)
	end

	if event.delta_y ~= nil then
		event.delta_y = tonumber(event.delta_y)
	end

	if event.network ~= nil and type(event.network) ~= "table" then
		error("event.network must be a table when present")
	end

	if event.power ~= nil and type(event.power) ~= "table" then
		error("event.power must be a table when present")
	end

	if event.audio ~= nil and type(event.audio) ~= "table" then
		error("event.audio must be a table when present")
	end

	if event.capture ~= nil and type(event.capture) ~= "table" then
		error("event.capture must be a table when present")
	end

	return event
end

--- Dispatches one normalized event and flushes pending renders for that event turn.
function M.dispatch_event(registry, event, flush_pending_render, log)
	log.trace("runtime dispatch event=" .. tostring(event.name))
	registry.handle_event(event)
	flush_pending_render()
end

return M
