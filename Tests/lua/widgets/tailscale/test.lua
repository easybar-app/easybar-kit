local root = assert(arg[1], "repository root argument is required")
local host = assert(loadfile(root .. "/Tests/lua/helpers/widget_host.lua"))()
host.configure(root)

local easybar, state = host.new(root)
local environment = setmetatable({ easybar = easybar }, { __index = _G })
local path = root .. "/widgets/tailscale/widget.lua"
local chunk, load_error = loadfile(path, "t", environment)
assert(chunk, "tailscale/widget.lua failed to load: " .. tostring(load_error))
local ok, runtime_error = pcall(chunk)
assert(ok, "tailscale/widget.lua failed during startup: " .. tostring(runtime_error))

local node = assert(state:node("tailscale_icon"), "Tailscale widget must create tailscale_icon")
assert(#state.commands == 1, "Tailscale widget must start one initial status read")

for _, subscription in ipairs(node.subscriptions) do
	if type(subscription.events) == "table" then
		subscription.handler({})
		subscription.handler({})
	end
end

assert(#state.commands == 1, "Tailscale widget must coalesce overlapping status reads")
state:complete_command(1, "{}", 0)
assert(#state.commands == 2, "Tailscale widget must run one coalesced follow-up read")

print("Tailscale widget regression checks passed")
