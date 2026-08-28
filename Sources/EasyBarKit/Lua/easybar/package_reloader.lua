--- Module contract:
--- Consumes package-update reload plans and reloads only affected managed widgets.
local M = {}

local RELOAD_PLAN_FILE = ".reload-plan.json"

--- Returns the package-store root that owns the managed `active/` directory.
---@param active_dir string
---@return string?
local function packages_root(active_dir)
	return tostring(active_dir or ""):match("^(.*)/[^/]+$")
end

--- Returns the pending package reload-plan path for one managed activation root.
---@param active_dir string
---@return string?
local function reload_plan_path(active_dir)
	local root = packages_root(active_dir)
	if root == nil or root == "" then
		return nil
	end
	return root .. "/" .. RELOAD_PLAN_FILE
end

--- Returns whether a value is a dense array of non-empty strings.
---@param values unknown
---@return boolean
local function is_string_array(values)
	if type(values) ~= "table" then
		return false
	end
	local count = 0
	for key, value in pairs(values) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or type(value) ~= "string" or value == "" then
			return false
		end
		count = count + 1
	end
	return count == #values
end

--- Returns whether one package reload plan is waiting to be consumed.
---@param active_dir string
---@return boolean
function M.has_pending(active_dir)
	local path = reload_plan_path(active_dir)
	if path == nil then
		return false
	end
	local file = io.open(path, "rb")
	if file == nil then
		return false
	end
	file:close()
	return true
end

--- Deletes a stale reload plan without applying it.
---@param active_dir string
function M.discard_pending(active_dir)
	local path = reload_plan_path(active_dir)
	if path ~= nil then
		os.remove(path)
	end
end

--- Reads and removes one atomically written reload plan.
---@param active_dir string
---@param json table
---@return table? plan
---@return string? error_message
function M.consume_pending(active_dir, json)
	local path = reload_plan_path(active_dir)
	if path == nil then
		return nil, "managed widget directory has no package root"
	end

	local file = io.open(path, "rb")
	if file == nil then
		return nil, nil
	end
	local raw = file:read("*a") or ""
	file:close()
	os.remove(path)

	local ok, plan = pcall(json.decode, raw)
	if not ok or type(plan) ~= "table" then
		return nil, "package reload plan is not valid JSON"
	end
	if not is_string_array(plan.packages) or not is_string_array(plan.modules) or not is_string_array(plan.widgets) then
		return nil, "package reload plan requires packages, modules, and widgets string arrays"
	end
	return plan, nil
end

--- Returns a Lua function's physical source path when available.
---@param callback unknown
---@return string?
local function function_source(callback)
	if type(callback) ~= "function" then
		return nil
	end
	local info = debug.getinfo(callback, "S")
	local source = info and info.source or nil
	if type(source) ~= "string" or source:sub(1, 1) ~= "@" then
		return nil
	end
	return source:sub(2)
end

--- Returns whether a physical callback path belongs to an affected managed widget package.
---@param source string?
---@param store_prefixes string[]
---@return boolean
local function source_is_affected(source, store_prefixes)
	if source == nil then
		return false
	end
	for _, prefix in ipairs(store_prefixes) do
		if source:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

--- Removes callback entries defined by affected managed widget packages.
---@param storage table
---@param store_prefixes string[]
local function remove_affected_inbox_handlers(storage, store_prefixes)
	for source, handlers in pairs(storage or {}) do
		local retained = {}
		for _, entry in ipairs(handlers or {}) do
			if source_is_affected(function_source(entry.handler), store_prefixes) then
				entry.active = false
			else
				retained[#retained + 1] = entry
			end
		end
		storage[source] = #retained > 0 and retained or nil
	end
end

--- Removes pending callbacks that belong to widgets being replaced.
---@param state table
---@param widget_names table<string, boolean>
---@param store_prefixes string[]
---@param cancel_timer? fun(token:string)
local function remove_pending_callbacks(state, widget_names, store_prefixes, cancel_timer)
	for token, pending in pairs(state.pending_async_commands or {}) do
		local widget = type(pending.context) == "table" and pending.context.widget or nil
		if widget_names[widget] or source_is_affected(function_source(pending.callback), store_prefixes) then
			state.pending_async_commands[token] = nil
		end
	end

	for token, callback in pairs(state.pending_timers or {}) do
		if source_is_affected(function_source(callback), store_prefixes) then
			state.pending_timers[token] = nil
			if type(cancel_timer) == "function" then
				pcall(cancel_timer, token)
			end
		end
	end

	remove_affected_inbox_handlers(state.inbox_action_handlers, store_prefixes)
	remove_affected_inbox_handlers(state.inbox_context_action_handlers, store_prefixes)
end

--- Returns the direct parent node referenced by one item, if any.
---@param item table
---@return string?
local function item_parent(item)
	if type(item) ~= "table" or type(item.props) ~= "table" then
		return nil
	end
	if type(item.props.parent) == "string" and item.props.parent ~= "" then
		return item.props.parent
	end
	if type(item.props.position) == "string" then
		return item.props.position:match("^popup%.(.+)$")
	end
	return nil
end

--- Removes all node roots owned by affected managed widget activations.
---@param registry table
---@param active_dir string
---@param widgets string[]
---@return string[] cleared_roots
local function remove_widget_nodes(registry, active_dir, widgets)
	local state = registry._state
	local owned = {}
	for _, widget in ipairs(widgets) do
		local activation = active_dir .. "/" .. widget
		for id, item in pairs(state.items or {}) do
			if item.source == activation then
				owned[id] = true
			end
		end
	end

	local roots = {}
	for id in pairs(owned) do
		local parent = item_parent(state.items[id])
		if parent == nil or not owned[parent] then
			roots[#roots + 1] = id
		end
	end
	table.sort(roots)

	for _, id in ipairs(roots) do
		registry.remove(id)
	end
	return roots
end

--- Invalidates exported Lua modules so consumers require the updated files.
---@param modules string[]
local function invalidate_modules(modules)
	for loaded_name in pairs(package.loaded) do
		for _, module in ipairs(modules) do
			if loaded_name == module or loaded_name:sub(1, #module + 1) == module .. "." then
				package.loaded[loaded_name] = nil
				break
			end
		end
	end
end

--- Reloads selected managed widget entrypoints in the requested dependency order.
---@param active_dir string
---@param widgets string[]
---@param api table
---@param loader table
---@param registry table
---@param log table
---@return integer loaded
---@return integer failed
local function load_widgets(active_dir, widgets, api, loader, registry, log)
	local discovered, discovery_error = api.discover_managed_widgets(active_dir)
	if discovered == nil then
		log.error("package reload discovery failed error=" .. tostring(discovery_error))
		return 0, #widgets
	end

	local by_name = {}
	for _, descriptor in ipairs(discovered) do
		by_name[descriptor.name] = descriptor
	end

	local selected = {}
	for _, name in ipairs(widgets) do
		local descriptor = by_name[name]
		if descriptor == nil then
			log.error("package reload skipped missing managed widget=" .. tostring(name))
		else
			selected[#selected + 1] = descriptor
		end
	end
	return loader.load_managed_widgets(active_dir, selected, registry, log)
end

--- Applies one dependency-ordered package reload plan.
---@param active_dir string
---@param plan table
---@param api table
---@param loader table
---@param registry table
---@param log table
---@param cancel_timer? fun(token:string)
---@return table result
function M.apply(active_dir, plan, api, loader, registry, log, cancel_timer)
	local root = assert(packages_root(active_dir), "managed widget directory has no package root")
	local widget_names = {}
	local store_prefixes = {}
	for _, package_name in ipairs(plan.packages) do
		store_prefixes[#store_prefixes + 1] = root .. "/store/" .. package_name .. "/"
	end
	for _, widget in ipairs(plan.widgets) do
		widget_names[widget] = true
	end

	remove_pending_callbacks(registry._state, widget_names, store_prefixes, cancel_timer)
	local cleared_roots = remove_widget_nodes(registry, active_dir, plan.widgets)
	invalidate_modules(plan.modules)
	local loaded, failed = load_widgets(active_dir, plan.widgets, api, loader, registry, log)

	return {
		cleared_roots = cleared_roots,
		loaded = loaded,
		failed = failed,
	}
end

return M
