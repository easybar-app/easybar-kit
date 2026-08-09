--- Module contract:
--- Owns high-level rendering orchestration across style, tree, flatten, and emission helpers.
--- Returns one helper that emits the current widget trees for the Swift host.
local M = {}

local style = require("easybar.render.style")
local tree = require("easybar.render.tree")
local emitter = require("easybar.render.emitter")

--- Builds every current root tree and emits only changed or removed snapshots.
---@param registry table Active widget registry.
---@param log table Runtime logger.
---@param json table JSON codec.
---@return boolean emitted Whether host-visible tree state changed.
function M.emit_all(registry, log, json)
	local ok, prepared_or_error = pcall(tree.prepare, registry)
	if not ok then
		if log then
			log.error(tostring(prepared_or_error))
		end
		return false
	end

	local prepared = prepared_or_error
	local trees = {}
	local live_roots = {}
	for _, id in ipairs(tree.root_ids(registry, prepared)) do
		local item = registry._state.items[id]
		if item ~= nil then
			live_roots[id] = true
			local root_position = style.normalize_position(item.props.position)
			local built = tree.build_tree(registry, id, root_position, prepared)
			if built ~= nil then
				trees[#trees + 1] = built
			end
		end
	end

	emitter.emit_all(trees, live_roots, log, json)
	return true
end

return M
