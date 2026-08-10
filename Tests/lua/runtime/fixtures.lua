-- Synthetic filesystem fixtures for Lua runtime regression tests.

local M = {}

--- Quotes one value for the shell commands used to build test fixtures.
local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

--- Runs one fixture setup command and raises when it fails.
local function run(command)
	local ok, reason, status = os.execute(command)
	assert(ok, "fixture command failed reason=" .. tostring(reason) .. " status=" .. tostring(status))
end

--- Creates one fixture directory recursively.
local function make_directory(path)
	run("/bin/mkdir -p -- " .. shell_quote(path))
end

--- Writes exact content to one fixture file.
local function write_file(path, content)
	local file = assert(io.open(path, "w"))
	file:write(content)
	file:close()
end

--- Creates and returns one isolated temporary fixture directory.
local function make_temp_directory(suffix)
	local path = os.tmpname() .. suffix
	os.remove(path)
	make_directory(path)
	return path
end

--- Removes one temporary fixture directory recursively.
function M.cleanup(path)
	run("/bin/rm -rf -- " .. shell_quote(path))
end

--- Builds widgets used to test discovery ordering and filtering.
function M.discovery()
	local root = make_temp_directory("-easybar-discovery")
	make_directory(root .. "/assets")
	make_directory(root .. "/.easybar")
	make_directory(root .. "/shared")
	make_directory(root .. "/nested")

	for _, relative_path in ipairs({
		".easybar/custom.lua",
		".hidden.lua",
		"assets/preview.lua",
		"clock.lua",
		"nested/STATUS.LUA",
	}) do
		write_file(root .. "/" .. relative_path, "return nil\n")
	end
	write_file(root .. "/ignored.txt", "not lua\n")
	write_file(root .. "/shared/retry.lua", "return {}\n")
	return root
end

--- Builds a managed package root whose active widget points directly to its entrypoint.
function M.managed_discovery()
	local root = make_temp_directory("-easybar-managed-discovery")
	local active = root .. "/active"
	local stored = root .. "/store/clock/1.0.0"
	make_directory(active)
	make_directory(stored)
	write_file(stored .. "/private.lua", "error('must not load')\n")
	write_file(stored .. "/widget.lua", "return nil\n")
	run("/bin/ln -s " .. shell_quote("../store/clock/1.0.0/widget.lua") .. " " .. shell_quote(active .. "/clock"))
	return root, active
end

--- Builds package and shared-module fixtures for require-path tests.
function M.module_resolution()
	local root = make_temp_directory("-easybar-module-paths")
	make_directory(root .. "/package")
	make_directory(root .. "/shared")

	--- Writes one module below the active resolution fixture root.
	local function write_module(relative_path, value)
		write_file(root .. "/" .. relative_path, "return " .. string.format("%q", value) .. "\n")
	end

	write_module("package/policy.lua", "package")
	write_module("shared/shared_resolution.lua", "shared")
	write_module("precedence_resolution.lua", "package")
	write_module("shared/precedence_resolution.lua", "shared")
	write_file(
		root .. "/source.lua",
		[[
local package_module = require("package.policy")
local shared = require("shared_resolution")
local precedence = require("precedence_resolution")
easybar.add(easybar.kind.item, "module-resolution", {
	label = package_module .. ":" .. shared .. ":" .. precedence,
})
]]
	)
	return root
end

--- Builds widgets that exercise transactional rollback after load failures.
function M.rollback()
	local root = make_temp_directory("-easybar-rollback")
	make_directory(root .. "/shared")
	write_file(root .. "/shared/rollback_probe.lua", "return { loaded = true }\n")
	write_file(
		root .. "/broken.lua",
		[[
local probe = require("rollback_probe")
assert(probe.loaded)
local node = easybar.add(easybar.kind.item, "partial", { label = "partial" })
node:subscribe(easybar.events.forced, function() end)
easybar.inbox.on_action("rollback-test", function() end)
easybar.inbox.replace("rollback-test", {})
easybar.exec_async("true", nil, function() end)
easybar.after(10, function() end)
error("intentional source failure")
]]
	)
	return root
end

--- Builds widgets that verify existing registry state survives failed reloads.
function M.existing_state()
	local root = make_temp_directory("-easybar-existing-state")
	write_file(
		root .. "/broken.lua",
		[[
easybar.add(easybar.kind.item, "temporary", {})
error("rollback existing state")
]]
	)
	return root
end

return M
