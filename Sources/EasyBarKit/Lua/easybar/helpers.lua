--- Module contract:
--- Owns shared Lua table helpers reused across runtime modules.
--- Shared helper module table.
local M = {}

--- Deep-copies one Lua value tree.
function M.deep_copy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}

	for key, item in pairs(value) do
		copy[key] = M.deep_copy(item)
	end

	return copy
end

return M
