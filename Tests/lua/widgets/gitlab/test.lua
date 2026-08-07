local root = assert(arg[1], "repository root argument is required")
local host = assert(loadfile(root .. "/Tests/lua/helpers/widget_host.lua"))()
host.configure(root)

local easybar, state = host.new(root)
local environment = setmetatable({ easybar = easybar }, { __index = _G })
local path = root .. "/widgets/gitlab/widget.lua"
local chunk, load_error = loadfile(path, "t", environment)
assert(chunk, "gitlab/widget.lua failed to load: " .. tostring(load_error))
local ok, runtime_error = pcall(chunk)
assert(ok, "gitlab/widget.lua failed during startup: " .. tostring(runtime_error))

assert(state:has_command("glab"), "GitLab widget must invoke glab")
assert(not state:has_command("gh"), "GitLab widget must not invoke gh")

local expected = {
	gitlab_work_items = true,
	gitlab_work_items_header = true,
	gitlab_work_items_footer = true,
}
for index = 1, 8 do
	expected["gitlab_work_item_" .. tostring(index)] = true
end

local count = 0
for id in pairs(state.nodes) do
	count = count + 1
	assert(expected[id], "GitLab widget created unexpected node " .. id)
	expected[id] = nil
end
for id in pairs(expected) do
	error("GitLab widget did not create node " .. id)
end
assert(count == 11, "GitLab widget created an unexpected number of nodes")

print("GitLab widget regression checks passed")
