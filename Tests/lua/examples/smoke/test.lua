-- Smoke-loads every executable example widget discovered by the CI runner.

local root = assert(arg[1], "repository root argument is required")
local host = assert(loadfile(root .. "/Tests/lua/helpers/widget_host.lua"))()
host.configure(root)
local shared_ids = {}
local count = 0

for index = 2, #arg do
	local path = arg[index]
	local easybar = host.new(root, { shared_ids = shared_ids })
	local environment = setmetatable({ easybar = easybar }, { __index = _G })
	local chunk, load_error = loadfile(path, "t", environment)
	assert(chunk, path .. " failed to load: " .. tostring(load_error))

	local ok, runtime_error = pcall(chunk)
	assert(ok, path .. " failed during startup: " .. tostring(runtime_error))
	count = count + 1
end

assert(count > 0, "no example widgets were provided")
print("Lua example smoke test passed for " .. tostring(count) .. " examples")
