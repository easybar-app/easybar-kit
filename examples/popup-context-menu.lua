-- Combined popup and native context-menu example.
-- Hover the widget to show its native-managed popup; right-click it to open
-- the native menu. Popup hover tracking needs no Lua event handlers.

local mode = "all"
local refresh_count = 0

local widget
local popup_status

local COLORS = {
	text = easybar.theme.ref.text,
	muted = easybar.theme.ref.muted,
	accent = easybar.theme.ref.accent,
	surface = easybar.theme.ref.surface,
	border = easybar.theme.ref.border_strong,
	popup = easybar.theme.ref.background,
}

local function context_menu()
	return {
		{ id = "refresh", title = "Refresh" },
		{ separator = true },
		{
			title = "Mode",
			submenu = {
				{ id = "mode_all", title = "All", checked = mode == "all" },
				{ id = "mode_active", title = "Active", checked = mode == "active" },
			},
		},
	}
end

local function render()
	widget:set({
		label = {
			string = mode == "all" and "Overview" or "Active",
			color = COLORS.text,
		},
		context_menu = context_menu(),
	})

	popup_status:set({
		label = {
			string = "Mode: " .. mode .. " · Refreshes: " .. tostring(refresh_count),
			color = COLORS.text,
		},
	})
end

widget = easybar.add(easybar.kind.item, "popup_context_menu_example", {
	position = "right",
	order = 10,
	icon = {
		string = "󰍜",
		color = COLORS.accent,
	},
	label = {
		string = "Overview",
		color = COLORS.text,
	},
	spacing = 5,
	background = {
		color = COLORS.surface,
		border_color = COLORS.border,
		border_width = 1,
		corner_radius = 8,
		padding_left = 8,
		padding_right = 8,
		padding_top = 3,
		padding_bottom = 3,
	},
	popup = {
		-- Keep the content drawable; EasyBar still presents the panel only on hover.
		drawing = true,
		background = {
			color = COLORS.popup,
			border_color = COLORS.border,
			border_width = 1,
			corner_radius = 8,
		},
		padding_x = 10,
		padding_y = 8,
	},
	context_menu = context_menu(),
})

popup_status = easybar.add(easybar.kind.item, "popup_context_menu_status", {
	position = "popup." .. widget.name,
	order = 1,
	label = {
		string = "",
		color = COLORS.text,
	},
})

easybar.add(easybar.kind.item, "popup_context_menu_hint", {
	position = "popup." .. widget.name,
	order = 2,
	label = {
		string = "Right-click the bar item for actions",
		color = COLORS.muted,
	},
})

widget:subscribe(easybar.events.context_menu.clicked, function(event)
	if event.action_id == "refresh" then
		refresh_count = refresh_count + 1
	elseif event.action_id == "mode_all" then
		mode = "all"
	elseif event.action_id == "mode_active" then
		mode = "active"
	end
	render()
end)

render()
