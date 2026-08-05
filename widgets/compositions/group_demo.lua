-- Group example showing shared styling, child items, group-level mouse events,
-- and popup content attached through `popup.<group name>`.

local hovered = false
local enabled = false

local group
local icon
local label

local COLORS = {
	surface = easybar.theme.ref.surface,
	hover = easybar.theme.ref.surface_hover,
	accent = easybar.theme.ref.accent_secondary,
	muted = easybar.theme.ref.muted,
	text = easybar.theme.ref.text,
	border = easybar.theme.ref.border_strong,
	popup_bg = easybar.theme.ref.background,
}

local function render()
	group:set({
		background = {
			color = hovered and COLORS.hover or COLORS.surface,
			border_color = enabled and COLORS.accent or COLORS.border,
			border_width = 1,
			corner_radius = 8,
			padding_left = 8,
			padding_right = 8,
			padding_top = 4,
			padding_bottom = 4,
		},
	})

	icon:set({
		icon = {
			string = enabled and "󰄬" or "󰄱",
			color = enabled and COLORS.accent or COLORS.muted,
		},
	})

	label:set({
		label = {
			string = hovered and "Group Hover" or "Group",
			color = COLORS.text,
		},
	})
end

group = easybar.add(easybar.kind.group, "group_demo", {
	position = "right",
	order = 5,
	spacing = 6,
	popup = {
		drawing = false,
		background = {
			color = COLORS.popup_bg,
			border_color = COLORS.border,
			border_width = 1,
			corner_radius = 8,
		},
		padding_x = 10,
		padding_y = 8,
	},
})

icon = easybar.add(easybar.kind.item, "group_demo_icon", {
	parent = group.name,
	icon = {
		string = "󰄱",
		color = COLORS.muted,
	},
})

label = easybar.add(easybar.kind.item, "group_demo_label", {
	parent = group.name,
	label = {
		string = "Group",
		color = COLORS.text,
	},
})

easybar.add(easybar.kind.item, "group_demo_popup", {
	position = "popup." .. group.name,
	label = {
		string = "Group popup",
		color = COLORS.text,
	},
})

group:subscribe(easybar.events.mouse.entered, function()
	hovered = true
	group:set({
		popup = { drawing = true },
	})
	render()
end)

group:subscribe(easybar.events.mouse.exited, function()
	hovered = false
	group:set({
		popup = { drawing = false },
	})
	render()
end)

group:subscribe(easybar.events.mouse.clicked, function()
	enabled = not enabled
	render()
end)

render()
