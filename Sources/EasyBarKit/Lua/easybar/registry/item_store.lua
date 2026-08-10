--- Module contract:
--- Owns widget item CRUD, property merging, and linear-time subtree removal.
local M = {}
local helpers = require("easybar.helpers")

M.INTERNAL_ID_PREFIX = "__easybar_internal__:"

--- Recursively merges a detached property table into a target table.
local function deep_merge(target, source)
	if type(source) ~= "table" then
		return target
	end

	for key, value in pairs(source) do
		if key == "context_menu" then
			target[key] = helpers.deep_copy(value)
		elseif type(value) == "table" and type(target[key]) == "table" then
			deep_merge(target[key], value)
		else
			target[key] = helpers.deep_copy(value)
		end
	end
	return target
end

--- Splits one dot-delimited property path into validated segments.
local function split_path(path)
	local segments = {}
	for segment in tostring(path):gmatch("[^%.]+") do
		segments[#segments + 1] = segment
	end
	return segments
end

--- Removes one nested property path and prunes empty intermediate tables.
local function unset_path(target, path)
	if type(target) ~= "table" then
		return false
	end

	local segments = split_path(path)
	if #segments == 0 then
		return false
	end

	local stack = {}
	local cursor = target
	for index = 1, #segments - 1 do
		local key = segments[index]
		if type(cursor[key]) ~= "table" then
			return false
		end
		stack[#stack + 1] = { parent = cursor, key = key }
		cursor = cursor[key]
	end

	local leaf = segments[#segments]
	if cursor[leaf] == nil then
		return false
	end
	cursor[leaf] = nil

	for index = #stack, 1, -1 do
		local entry = stack[index]
		if next(entry.parent[entry.key]) ~= nil then
			break
		end
		entry.parent[entry.key] = nil
	end
	return true
end

--- Returns every distinct normal or popup parent id referenced by an item.
local function parent_ids(item)
	local result = {}
	local seen = {}
	local parent = type(item.props.parent) == "string" and item.props.parent or nil
	local position = type(item.props.position) == "string" and item.props.position or nil
	local popup_parent = position and position:match("^popup%.(.+)$") or nil
	for _, value in ipairs({ parent, popup_parent }) do
		if value ~= nil and value ~= "" and not seen[value] then
			seen[value] = true
			result[#result + 1] = value
		end
	end
	return result
end

--- Creates the mutable item store used by the widget registry.
---@param state table Shared registry state.
---@param options table Normalization and mutation callbacks.
---@return table store Item CRUD API.
function M.new(state, options)
	local normalize_props = assert(options.normalize_props)
	local on_mutation = assert(options.on_mutation)
	local current_source = options.current_source or function()
		return nil
	end

	local store = {}

	--- Raises when a node id does not exist in the current registry.
	function store.ensure_item_exists(id)
		local item = state.items[id]
		if item == nil then
			error("easybar item does not exist: " .. tostring(id), 2)
		end
		return item
	end

	--- Merges defaults and explicit props into a normalized detached table.
	function store.merge_props(defaults, props)
		local merged = {}
		deep_merge(merged, normalize_props(defaults or {}))
		deep_merge(merged, normalize_props(props or {}))
		return merged
	end

	--- Adds one new item after validating identity and parent relationships.
	function store.add(kind, id, props, defaults, source)
		assert(type(kind) == "string" and kind ~= "", "easybar.add(kind, id, props) requires kind")
		assert(type(id) == "string" and id ~= "", "easybar.add(kind, id, props) requires id")
		assert(not id:find("%z"), "easybar.add(kind, id, props) rejects NUL bytes")
		assert(
			id:sub(1, #M.INTERNAL_ID_PREFIX) ~= M.INTERNAL_ID_PREFIX,
			"easybar item id uses reserved internal prefix: " .. id
		)

		if state.items[id] ~= nil then
			local owner = state.items[id].source
			local suffix = owner and (" (owner=" .. tostring(owner) .. ")") or ""
			error("easybar item already exists: " .. id .. suffix, 2)
		end

		state.items[id] = {
			id = id,
			kind = kind,
			props = store.merge_props(defaults, props),
			source = source or current_source(),
		}
		state.item_order[#state.item_order + 1] = id
		on_mutation()
	end

	--- Merges normalized properties into one existing item.
	function store.set(id, props)
		local item = store.ensure_item_exists(id)
		deep_merge(item.props, normalize_props(props or {}))
		on_mutation()
	end

	--- Returns a detached copy of one existing item property table.
	function store.get(id)
		return helpers.deep_copy(store.ensure_item_exists(id).props)
	end

	--- Removes one item and all descendants attached through either parent graph.
	function store.remove(id)
		if state.items[id] == nil then
			return false
		end

		local children = {}
		for child_id, item in pairs(state.items) do
			for _, parent_id in ipairs(parent_ids(item)) do
				children[parent_id] = children[parent_id] or {}
				children[parent_id][#children[parent_id] + 1] = child_id
			end
		end

		local removed = {}
		local stack = { id }
		while #stack > 0 do
			local current = table.remove(stack)
			if not removed[current] then
				removed[current] = true
				for _, child_id in ipairs(children[current] or {}) do
					stack[#stack + 1] = child_id
				end
			end
		end

		for removed_id in pairs(removed) do
			state.items[removed_id] = nil
			state.subscriptions[removed_id] = nil
			state.interval_handlers[removed_id] = nil
		end

		local retained = {}
		for _, ordered_id in ipairs(state.item_order) do
			if not removed[ordered_id] then
				retained[#retained + 1] = ordered_id
			end
		end
		state.item_order = retained
		on_mutation()
		return true
	end

	--- Removes one or more nested property paths from an existing item.
	function store.unset(id, paths)
		local item = store.ensure_item_exists(id)
		local changed = false
		if type(paths) == "string" and paths ~= "" then
			changed = unset_path(item.props, paths)
		elseif type(paths) == "table" then
			for _, path in ipairs(paths) do
				if type(path) == "string" and path ~= "" then
					changed = unset_path(item.props, path) or changed
				end
			end
		else
			error("easybar.unset(id, paths) requires one string path or an array of string paths", 2)
		end
		if changed then
			on_mutation()
		end
		return changed
	end

	return store
end

return M
