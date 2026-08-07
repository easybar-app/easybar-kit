local root = assert(arg[1], "repository root argument is required")
local widget_path = root .. "/widgets/caffeinate/widget.lua"
local host = assert(loadfile(root .. "/Tests/lua/helpers/widget_host.lua"))()
host.configure(root)

local function load_widget(duration_minutes)
	local storage = {}
	if duration_minutes ~= nil then
		storage["caffeinate:duration_minutes"] = duration_minutes
	end

	local easybar, state = host.new(root, { storage = storage })
	local environment = setmetatable({ easybar = easybar }, { __index = _G })
	local chunk, load_error = loadfile(widget_path, "t", environment)
	assert(chunk, "caffeinate failed to load: " .. tostring(load_error))

	local ok, runtime_error = pcall(chunk)
	assert(ok, "caffeinate failed during startup: " .. tostring(runtime_error))
	assert(state:node("caffeinate") ~= nil, "caffeinate must create its root node")
	assert(state:node("caffeinate_popup_label") ~= nil, "caffeinate must create its popup label")
	return easybar, state
end

local function click_left(easybar, state)
	state:emit("caffeinate", easybar.events.mouse.clicked, {
		button = easybar.events.mouse.left_button,
	})
	assert(#state.commands == 1, "left-click must start exactly one caffeinate command")
	assert(state:command_contains(1, "/usr/bin/caffeinate"), "left-click must invoke /usr/bin/caffeinate")
end

do
	local easybar, state = load_widget(nil)
	click_left(easybar, state)
	assert(state:command_contains(1, "82800"), "missing duration_minutes must use indefinite renewal duration")
end

do
	local easybar, state = load_widget(90)
	click_left(easybar, state)
	assert(state:command_contains(1, "5400"), "90-minute duration must dispatch 5400 seconds")
end

do
	local easybar, state = load_widget(0)
	click_left(easybar, state)
	assert(state:command_contains(1, "82800"), "invalid duration_minutes must fall back to indefinite mode")
end

print("Caffeinate widget regression checks passed")
