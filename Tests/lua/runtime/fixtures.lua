-- Synthetic filesystem fixtures for Lua runtime regression tests.

local M = {}

local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run(command)
	local ok, reason, status = os.execute(command)
	assert(ok, "fixture command failed reason=" .. tostring(reason) .. " status=" .. tostring(status))
end

local function make_directory(path)
	run("/bin/mkdir -p -- " .. shell_quote(path))
end

local function write_file(path, content)
	local file = assert(io.open(path, "w"))
	file:write(content)
	file:close()
end

local function make_temp_directory(suffix)
	local path = os.tmpname() .. suffix
	os.remove(path)
	make_directory(path)
	return path
end

function M.cleanup(path)
	run("/bin/rm -rf -- " .. shell_quote(path))
end

function M.discovery()
	local root = make_temp_directory("-easybar-discovery")
	make_directory(root .. "/assets")
	make_directory(root .. "/.easybar/packages/example")
	make_directory(root .. "/shared")
	make_directory(root .. "/lib")
	make_directory(root .. "/nested")

	for _, relative_path in ipairs({
		".hidden.lua",
		"assets/preview.lua",
		"clock.lua",
		"nested/STATUS.LUA",
	}) do
		write_file(root .. "/" .. relative_path, "return nil\n")
	end
	write_file(root .. "/ignored.txt", "not lua\n")
	write_file(root .. "/.easybar/packages/example/widget.lua", "error('must not load')\n")
	write_file(root .. "/shared/retry.lua", "return {}\n")
	write_file(root .. "/lib/legacy.lua", "return {}\n")
	return root
end

function M.module_resolution()
	local root = make_temp_directory("-easybar-module-paths")
	make_directory(root .. "/package")
	make_directory(root .. "/shared")
	make_directory(root .. "/lib")

	local function write_module(relative_path, value)
		write_file(root .. "/" .. relative_path, "return " .. string.format("%q", value) .. "\n")
	end

	write_module("package/policy.lua", "package")
	write_module("shared/shared_resolution.lua", "shared")
	write_module("lib/legacy_resolution.lua", "legacy")
	write_module("precedence_resolution.lua", "package")
	write_module("shared/precedence_resolution.lua", "shared")
	write_module("lib/precedence_resolution.lua", "legacy")
	write_file(
		root .. "/source.lua",
		[[
local package_module = require("package.policy")
local shared = require("shared_resolution")
local legacy = require("legacy_resolution")
local precedence = require("precedence_resolution")
easybar.add(easybar.kind.item, "module-resolution", {
	label = package_module .. ":" .. shared .. ":" .. legacy .. ":" .. precedence,
})
]]
	)
	return root
end

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
