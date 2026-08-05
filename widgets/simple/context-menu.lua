-- Native context-menu example. Right-click the widget to open the menu.
-- A selectable item's `id` is delivered as `event.action_id`; rebuild the
-- menu with `set` after state changes so native checkmarks stay current.

local filter = "all"
local github

local function menu()
	return {
		{ id = "refresh", title = "Refresh" },
		{ id = "open_notifications", title = "Open Notifications" },
		{ separator = true },
		{
			title = "Filter",
			submenu = {
				{ id = "filter_all", title = "All", checked = filter == "all" },
				{ id = "filter_mentions", title = "Mentions", checked = filter == "mentions" },
			},
		},
	}
end

local function render()
	github:set({
		label = "GitHub · " .. filter,
		context_menu = menu(),
	})
end

github = easybar.add(easybar.kind.item, "context_menu_example", {
	position = "right",
	icon = "󰊤",
	spacing = 2,
	label = "GitHub",
	context_menu = menu(),
})

github:subscribe(easybar.events.context_menu.clicked, function(event)
	if event.action_id == "refresh" then
		easybar.log(easybar.level.info, "refresh requested from native context menu")
	elseif event.action_id == "open_notifications" then
		easybar.spawn_async({ "open", "https://github.com/notifications" }, nil, function(_, code)
			if code ~= 0 then
				easybar.log(easybar.level.warn, "failed to open GitHub notifications")
			end
		end)
	elseif event.action_id == "filter_all" then
		filter = "all"
		render()
	elseif event.action_id == "filter_mentions" then
		filter = "mentions"
		render()
	end
end)
