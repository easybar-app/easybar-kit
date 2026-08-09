--- Module contract:
--- Validates registry parent references and builds ordered adjacency maps once per render.
local M = {}

--- Returns one stable human-readable identifier for graph diagnostics.
local function describe_item(item)
	local source = item and item.source
	if type(source) == "string" and source ~= "" then
		return tostring(item.id) .. " (source " .. source .. ")"
	end
	return tostring(item and item.id or "<unknown>")
end

--- Appends one child id to a parent adjacency list.
local function append_child(map, parent_id, child_id)
	map[parent_id] = map[parent_id] or {}
	map[parent_id][#map[parent_id] + 1] = child_id
end

--- Builds and validates one graph context in stable item order.
--- Validates parent relationships and returns regular and popup child indexes.
---@param state table Registry state containing ordered items.
---@return table regular_children Children attached to normal node parents.
---@return table popup_children Children attached to popup parents.
function M.build(state)
	local context = {
		roots = {},
		regular_children = {},
		popup_children = {},
		parent_of = {},
	}

	for _, id in ipairs(state.item_order or {}) do
		local item = state.items[id]
		if item ~= nil then
			local regular_parent = type(item.props.parent) == "string" and item.props.parent ~= "" and item.props.parent
				or nil
			local position = type(item.props.position) == "string" and item.props.position or nil
			local popup_parent = position and position:match("^popup%.(.+)$") or nil

			if regular_parent ~= nil and popup_parent ~= nil then
				error(
					"easybar item has both regular and popup parents: "
						.. describe_item(item)
						.. " parent="
						.. tostring(regular_parent)
						.. " popup_parent="
						.. tostring(popup_parent),
					2
				)
			end

			local parent = regular_parent or popup_parent
			if parent ~= nil then
				if state.items[parent] == nil then
					error("easybar item references missing parent: " .. describe_item(item) .. " parent=" .. tostring(parent), 2)
				end
				context.parent_of[id] = parent
				if regular_parent ~= nil then
					append_child(context.regular_children, parent, id)
				else
					append_child(context.popup_children, parent, id)
				end
			else
				context.roots[#context.roots + 1] = id
			end
		end
	end

	local visit_state = {}
	local path = {}
	local path_index = {}

	--- Visits one node to detect cycles in both parent graphs.
	local function visit(id)
		if visit_state[id] == 2 then
			return
		end
		if visit_state[id] == 1 then
			local cycle = {}
			local start = path_index[id] or 1
			for index = start, #path do
				cycle[#cycle + 1] = path[index]
			end
			cycle[#cycle + 1] = id
			error("easybar item parent cycle: " .. table.concat(cycle, " -> "), 2)
		end

		visit_state[id] = 1
		path[#path + 1] = id
		path_index[id] = #path
		local parent = context.parent_of[id]
		if parent ~= nil then
			visit(parent)
		end
		path_index[id] = nil
		path[#path] = nil
		visit_state[id] = 2
	end

	for _, id in ipairs(state.item_order or {}) do
		if state.items[id] ~= nil then
			visit(id)
		end
	end

	return context
end

return M
