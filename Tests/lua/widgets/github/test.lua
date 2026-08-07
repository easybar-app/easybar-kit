local root = assert(arg[1], "repository root argument is required")
local host = assert(loadfile(root .. "/Tests/lua/helpers/widget_host.lua"))()
host.configure(root)

local easybar, state = host.new(root)
local environment = setmetatable({ easybar = easybar }, { __index = _G })
local path = root .. "/widgets/github/widget.lua"
local chunk, load_error = loadfile(path, "t", environment)
assert(chunk, "github/widget.lua failed to load: " .. tostring(load_error))
local ok, runtime_error = pcall(chunk)
assert(ok, "github/widget.lua failed during startup: " .. tostring(runtime_error))

assert(state:has_command("gh"), "GitHub widget must invoke gh")
assert(not state:has_command("glab"), "GitHub widget must not invoke glab")

local expected = {
	github_notifications = true,
	github_notifications_header = true,
	github_notifications_footer = true,
}
for index = 1, 8 do
	expected["github_notification_" .. tostring(index)] = true
end

local count = 0
for id in pairs(state.nodes) do
	count = count + 1
	assert(expected[id], "GitHub widget created unexpected node " .. id)
	expected[id] = nil
end
for id in pairs(expected) do
	error("GitHub widget did not create node " .. id)
end
assert(count == 11, "GitHub widget created an unexpected number of nodes")

print("GitHub widget regression checks passed")
