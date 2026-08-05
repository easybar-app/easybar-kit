-- Minimal stateful widget: left-click toggles local state and re-renders it.

local enabled = false
local toggle

local COLORS = {
	on = easybar.theme.ref.success,
	off = easybar.theme.ref.error,
}

local function render()
	local color = enabled and COLORS.on or COLORS.off

	toggle:set({
		icon = {
			string = enabled and "󰄬" or "󰄱",
			color = color,
		},
		label = {
			string = enabled and "ON" or "OFF",
			color = color,
		},
	})
end

toggle = easybar.add(easybar.kind.item, "toggle_test", {
	position = "right",
	order = 1,
})

toggle:subscribe(easybar.events.forced, function()
	render()
end)

toggle:subscribe(easybar.events.mouse.clicked, function()
	enabled = not enabled
	render()
end)

render()
