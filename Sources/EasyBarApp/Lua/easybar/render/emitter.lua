--- Module contract:
--- Owns change-aware tree encoding and explicit root-clear emission.
--- Returns one helper that emits the current tree set.
local M = {}

local flatten = require("easybar.render.flatten")

local PROTOCOL_VERSION = 1
local last_emitted = {}

--- Serializes and writes one complete root tree update to the host.
local function emit_tree(tree, log, json)
	local root_id = tree.id or "unknown"
	local nodes = {}

	flatten.flatten_node(tree, root_id, nil, tree.position, nodes)

	local payload = {
		protocol_version = PROTOCOL_VERSION,
		type = "tree",
		root = root_id,
		nodes = nodes,
	}

	local encoded = json.encode(payload)

	if last_emitted[root_id] == encoded then
		return
	end

	last_emitted[root_id] = encoded

	io.stdout:write(encoded .. "\n")
	io.stdout:flush()

	if log then
		log.debug("render emit tree root=" .. root_id .. " nodes=" .. tostring(#nodes))
	end
end

--- Writes one root-removal update to the host.
local function emit_root_clear(root_id, log, json)
	local payload = {
		protocol_version = PROTOCOL_VERSION,
		type = "clear_root",
		root = root_id,
	}

	last_emitted[root_id] = nil

	io.stdout:write(json.encode(payload) .. "\n")
	io.stdout:flush()

	if log then
		log.debug("render clear root=" .. root_id)
	end
end

--- Emits changed trees, clears removed roots, and updates the live-root cache.
function M.emit_all(trees, live_roots, log, json)
	for _, tree in ipairs(trees) do
		emit_tree(tree, log, json)
	end

	for root_id in pairs(last_emitted) do
		if not live_roots[root_id] then
			emit_root_clear(root_id, log, json)
		end
	end
end

return M
