--- Module contract:
--- Owns validated registry-to-render-tree conversion and deterministic root ordering.
--- Builds parent adjacency once per render and rejects dangling, ambiguous, or cyclic graphs.
local M = {}

local style = require("easybar.render.style")
local item_store = require("easybar.registry.item_store")

local INTERNAL_ID_PREFIX = item_store.INTERNAL_ID_PREFIX

--- Returns one registry item by id without exposing traversal details.
local function item_by_id(registry, id)
	return registry._state.items[id]
end

--- Returns the registry's stable item order.
local function ordered_ids(registry)
	return registry._state.item_order or {}
end

--- Appends one child id to a prepared parent index.
local function add_child(index, parent_id, child_id)
	index[parent_id] = index[parent_id] or {}
	index[parent_id][#index[parent_id] + 1] = child_id
end

--- Returns one readable item identity for renderer diagnostics.
local function describe_item(item, id)
	return tostring(id) .. " source=" .. tostring(item and item.source or "unknown")
end

--- Builds and validates one render graph index.
--- Validates parent graphs and prepares normal and popup child indexes.
function M.prepare(registry)
	local regular_children = {}
	local popup_children = {}
	local parent_by_id = {}
	local roots = {}
	local issues = {}

	for _, id in ipairs(ordered_ids(registry)) do
		local item = item_by_id(registry, id)
		if item ~= nil then
			if id:sub(1, #INTERNAL_ID_PREFIX) == INTERNAL_ID_PREFIX then
				issues[#issues + 1] = "reserved internal id used by " .. describe_item(item, id)
			end

			local regular_parent = style.regular_parent_id(item)
			local popup_parent = style.popup_parent_id(item)
			if regular_parent ~= nil and popup_parent ~= nil then
				issues[#issues + 1] = "node has both parent and popup position: " .. describe_item(item, id)
			elseif regular_parent ~= nil then
				if item_by_id(registry, regular_parent) == nil then
					issues[#issues + 1] = "dangling parent=" .. tostring(regular_parent) .. " for " .. describe_item(item, id)
				else
					parent_by_id[id] = regular_parent
					add_child(regular_children, regular_parent, id)
				end
			elseif popup_parent ~= nil then
				if item_by_id(registry, popup_parent) == nil then
					issues[#issues + 1] = "dangling popup parent=" .. tostring(popup_parent) .. " for " .. describe_item(item, id)
				else
					parent_by_id[id] = popup_parent
					add_child(popup_children, popup_parent, id)
				end
			else
				roots[#roots + 1] = id
			end
		end
	end

	local marks = {}
	local stack = {}
	--- Visits one item to detect cycles across normal and popup parents.
	local function visit(id)
		if marks[id] == 2 then
			return
		end
		if marks[id] == 1 then
			local cycle = {}
			local found = false
			for _, stack_id in ipairs(stack) do
				if stack_id == id then
					found = true
				end
				if found then
					cycle[#cycle + 1] = stack_id
				end
			end
			cycle[#cycle + 1] = id
			issues[#issues + 1] = "parent cycle: " .. table.concat(cycle, " -> ")
			return
		end

		marks[id] = 1
		stack[#stack + 1] = id
		local parent = parent_by_id[id]
		if parent ~= nil then
			visit(parent)
		end
		stack[#stack] = nil
		marks[id] = 2
	end

	for _, id in ipairs(ordered_ids(registry)) do
		if item_by_id(registry, id) ~= nil then
			visit(id)
		end
	end

	if #issues > 0 then
		error("invalid EasyBar render graph: " .. table.concat(issues, "; "), 2)
	end

	return {
		regular_children = regular_children,
		popup_children = popup_children,
		roots = roots,
	}
end

--- Builds a collision-resistant id for renderer-owned popup nodes.
local function internal_popup_id(id, suffix)
	return INTERNAL_ID_PREFIX .. tostring(id) .. ":" .. tostring(suffix)
end

--- Recursively builds one render tree from a registry item and prepared indexes.
function M.build_tree(registry, id, root_position, prepared, visiting)
	prepared = prepared or M.prepare(registry)
	visiting = visiting or {}
	if visiting[id] then
		error("invalid EasyBar render graph: recursive build cycle at " .. tostring(id), 2)
	end

	local item = item_by_id(registry, id)
	if item == nil then
		return nil
	end

	visiting[id] = true
	local child_nodes = {}
	for _, child_id in ipairs(prepared.regular_children[id] or {}) do
		local child = M.build_tree(registry, child_id, root_position, prepared, visiting)
		if child then
			child_nodes[#child_nodes + 1] = child
		end
	end

	local popup_child_nodes = {}
	for _, child_id in ipairs(prepared.popup_children[id] or {}) do
		local child = M.build_tree(registry, child_id, root_position, prepared, visiting)
		if child then
			popup_child_nodes[#popup_child_nodes + 1] = child
		end
	end
	visiting[id] = nil

	local has_popup = type(item.props.popup) == "table" or #popup_child_nodes > 0
	if not has_popup then
		return style.make_node(registry, id, item, root_position, child_nodes)
	end

	local popup_props = item.props.popup or {}
	local popup_container =
		style.make_popup_container(internal_popup_id(id, "popup_content"), root_position, popup_props, popup_child_nodes)

	if item.kind == "popup" then
		local anchor = style.make_node(registry, internal_popup_id(id, "popup_anchor"), item, root_position, child_nodes)
		anchor.order = 0
		local root = style.make_node(registry, id, item, root_position, nil)
		root.anchorChildren = { anchor }
		root.popupChildren = { popup_container }
		return root
	end

	local root = style.make_node(registry, id, item, root_position, child_nodes)
	root.popupChildren = { popup_container }
	return root
end

--- Returns stable render roots that are not attached to regular parents.
function M.root_ids(registry, prepared)
	prepared = prepared or M.prepare(registry)
	local roots = {}
	for index, id in ipairs(prepared.roots) do
		roots[index] = id
	end
	return roots
end

return M
