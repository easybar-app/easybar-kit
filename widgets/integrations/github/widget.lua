--- Bundled github widget implementation.
---@param easybar EasyBar Widget-scoped EasyBar API from the top-level entrypoint.
return function(easybar)
	-- GitHub notifications widget. Requires an authenticated `gh` CLI.

	local text = require("text")

	---@class GitHubNotification
	---@field id? string
	---@field reason? string
	---@field repository? { full_name?: string, html_url?: string }
	---@field subject? { title?: string, type?: string, url?: string }

	---@class GitHubWidgetState
	---@field notifications GitHubNotification[]
	---@field error? string
	---@field loading boolean
	---@field popup_open boolean
	---@field trigger_hovered boolean
	---@field popup_hovered boolean
	---@field hover_revision integer
	---@field hover_close_timer? EasyBarTimerHandle

	local POLL_INTERVAL_SECONDS = 300
	local MAX_POPUP_ITEMS = 8
	local HOVER_CLOSE_DELAY_SECONDS = 0.20
	local GITHUB_NOTIFICATIONS_URL = "https://github.com/notifications"

	local COLORS = {
		text = easybar.theme.ref.text,
		muted = easybar.theme.ref.muted,
		accent = easybar.theme.ref.accent,
		danger = easybar.theme.ref.danger,
		background = easybar.theme.ref.background,
		border = easybar.theme.ref.border_strong,
		surface = easybar.theme.ref.surface,
		surface_hover = easybar.theme.ref.surface_hover,
	}

	---@type GitHubWidgetState
	local state = {
		notifications = {},
		error = nil,
		loading = false,
		popup_open = false,
		trigger_hovered = false,
		popup_hovered = false,
		hover_revision = 0,
		hover_close_timer = nil,
	}

	local github
	local popup_header
	local popup_rows = {}
	local popup_footer

	--- Opens a URL using the default macOS browser.
	---@param url string
	local function open_url(url)
		url = text.trim(url)
		if url == "" then
			return
		end

		easybar.spawn_async({ "open", url }, {
			timeout_seconds = 5,
			max_output_bytes = 4096,
		}, function(_, code)
			if code ~= 0 then
				easybar.log(easybar.level.warn, "failed to open GitHub URL", url)
			end
		end)
	end

	--- Returns the browser URL for one GitHub notification.
	---@param notification GitHubNotification
	---@return string
	local function notification_url(notification)
		local repository = type(notification.repository) == "table" and notification.repository or {}
		local repository_url = text.trim(repository.html_url)
		local subject = type(notification.subject) == "table" and notification.subject or {}
		local api_url = text.trim(subject.url)
		local number = api_url:match("/(%d+)$")

		if repository_url ~= "" and number ~= nil then
			if subject.type == "PullRequest" then
				return repository_url .. "/pull/" .. number
			elseif subject.type == "Issue" then
				return repository_url .. "/issues/" .. number
			elseif subject.type == "Discussion" then
				return repository_url .. "/discussions/" .. number
			end
		end

		return GITHUB_NOTIFICATIONS_URL
	end

	--- Returns the popup text for one GitHub notification.
	---@param notification GitHubNotification
	---@return string
	local function notification_text(notification)
		local repository = type(notification.repository) == "table" and notification.repository or {}
		local repository_name = text.trim(repository.full_name)
		if repository_name == "" then
			repository_name = "GitHub"
		end

		local subject = type(notification.subject) == "table" and notification.subject or {}
		local title = text.trim(subject.title)
		if title == "" then
			title = "Untitled notification"
		end

		return text.truncate(repository_name .. "  ·  " .. title, 100)
	end

	--- Flattens paginated `gh api --slurp` output into notifications.
	---@param pages GitHubNotification[][]
	---@return GitHubNotification[]? notifications
	---@return string? error_message
	local function flatten_notifications(pages)
		if type(pages) ~= "table" then
			return nil, "GitHub returned an unexpected response"
		end

		local notifications = {}
		for _, page in ipairs(pages) do
			if type(page) ~= "table" then
				return nil, "GitHub returned an unexpected response"
			end

			for _, notification in ipairs(page) do
				if type(notification) == "table" then
					notifications[#notifications + 1] = notification
				end
			end
		end

		return notifications, nil
	end

	--- Returns popup presentation properties.
	---@param drawing boolean
	---@return table
	local function popup_props(drawing)
		return {
			drawing = drawing,
			padding_x = 10,
			padding_y = 8,
			margin_y = 8,
			spacing = 5,
			background = {
				color = COLORS.background,
				border_color = COLORS.border,
				border_width = 1,
				corner_radius = 10,
			},
		}
	end

	--- Renders the GitHub popup.
	local function render_popup()
		local count = #state.notifications

		if state.error ~= nil then
			popup_header:set({
				drawing = true,
				label = {
					string = "GitHub notifications unavailable",
					color = COLORS.danger,
				},
			})
			popup_rows[1]:set({
				drawing = true,
				label = {
					string = text.truncate(state.error, 100),
					color = COLORS.text,
				},
			})

			for index = 2, MAX_POPUP_ITEMS do
				popup_rows[index]:set({ drawing = false })
			end
		else
			popup_header:set({
				drawing = true,
				label = {
					string = count == 1 and "1 unread GitHub notification" or tostring(count) .. " unread GitHub notifications",
					color = count == 0 and COLORS.muted or COLORS.accent,
				},
			})

			for index, row in ipairs(popup_rows) do
				local notification = state.notifications[index]
				if notification == nil then
					row:set({ drawing = false })
				else
					row:set({
						drawing = true,
						label = {
							string = notification_text(notification),
							color = COLORS.text,
						},
					})
				end
			end
		end

		popup_footer:set({
			drawing = true,
			label = {
				string = state.loading and "Refreshing..." or "Click a notification to open it · Right-click to refresh",
				color = COLORS.muted,
			},
		})
	end

	--- Renders the bar item and popup.
	local function render()
		local color = state.error ~= nil and COLORS.danger or (#state.notifications > 0 and COLORS.accent or COLORS.muted)

		github:set({
			icon = {
				string = "",
				color = color,
				image = {
					path = easybar.asset("assets/github.svg"),
					size = 16,
				},
			},
			label = {
				string = state.error ~= nil and "!" or tostring(#state.notifications),
				color = color,
			},
			background = {
				color = (state.trigger_hovered or state.popup_hovered) and COLORS.surface_hover
					or easybar.theme.ref.transparent,
				border_color = easybar.theme.ref.transparent,
				border_width = 0,
				corner_radius = 8,
			},
			popup = popup_props(state.popup_open),
		})

		render_popup()
	end

	--- Fetches unread GitHub notifications.
	local function refresh()
		if state.loading then
			return
		end

		state.loading = true
		render()

		easybar.spawn_async({
			"/usr/bin/env",
			"GH_PROMPT_DISABLED=1",
			"gh",
			"api",
			"--paginate",
			"--slurp",
			"-H",
			"Accept: application/vnd.github+json",
			"notifications?all=false&per_page=100",
		}, {
			timeout_seconds = 30,
			max_output_bytes = 2097152,
		}, function(output, code)
			state.loading = false

			if code ~= 0 then
				local message = text.trim(output)
				state.error = message ~= "" and message or "Run 'gh auth login' and verify app.env PATH"
				state.notifications = {}
				render()
				return
			end

			local decoded, pages = pcall(easybar.json.decode, output)
			if not decoded or type(pages) ~= "table" then
				state.error = "GitHub returned invalid notifications JSON"
				state.notifications = {}
				render()
				return
			end

			local notifications, parse_error = flatten_notifications(pages)
			if notifications == nil then
				state.error = parse_error
				state.notifications = {}
			else
				state.error = nil
				state.notifications = notifications
			end

			render()
		end)
	end

	github = easybar.add(easybar.kind.item, "github_notifications", {
		position = "right",
		order = 0,
		interval = POLL_INTERVAL_SECONDS,
		on_interval = refresh,
		icon = {
			string = "",
			color = COLORS.muted,
			image = {
				path = easybar.asset("assets/github.svg"),
				size = 16,
			},
		},
		label = {
			string = "0",
			color = COLORS.muted,
		},
		background = {
			color = easybar.theme.ref.transparent,
			border_color = easybar.theme.ref.transparent,
			border_width = 0,
			corner_radius = 8,
		},
		padding_x = 7,
		padding_y = 3,
		popup = popup_props(false),
		context_menu = {
			{ id = "refresh", title = "Refresh" },
			{ id = "open", title = "Open GitHub Notifications" },
		},
	})

	popup_header = easybar.add(easybar.kind.item, "github_notifications_header", {
		position = "popup." .. github.name,
		order = 0,
		drawing = true,
		label = {
			string = "GitHub notifications",
			color = COLORS.accent,
		},
		padding_x = 8,
		padding_y = 5,
	})

	for index = 1, MAX_POPUP_ITEMS do
		popup_rows[index] = easybar.add(easybar.kind.item, "github_notification_" .. tostring(index), {
			position = "popup." .. github.name,
			order = index,
			drawing = false,
			label = {
				string = "",
				color = COLORS.text,
			},
			background = {
				color = COLORS.surface,
				border_color = easybar.theme.ref.transparent,
				border_width = 0,
				corner_radius = 6,
			},
			padding_x = 8,
			padding_y = 5,
		})
	end

	popup_footer = easybar.add(easybar.kind.item, "github_notifications_footer", {
		position = "popup." .. github.name,
		order = MAX_POPUP_ITEMS + 1,
		drawing = true,
		label = {
			string = "Click a notification to open it · Right-click to refresh",
			color = COLORS.muted,
		},
		padding_x = 8,
		padding_y = 5,
	})

	--- Cancels a pending delayed popup close.
	local function cancel_hover_close()
		if state.hover_close_timer ~= nil then
			state.hover_close_timer:cancel()
			state.hover_close_timer = nil
		end
	end

	--- Opens the popup and records the hovered surface.
	---@param source "trigger"|"popup"
	local function open_popup(source)
		cancel_hover_close()
		state.hover_revision = state.hover_revision + 1

		if source == "trigger" then
			state.trigger_hovered = true
		else
			state.popup_hovered = true
		end

		state.popup_open = true
		render()
	end

	--- Schedules the popup to close after the hover grace period.
	---@param source "trigger"|"popup"
	local function schedule_popup_close(source)
		state.hover_revision = state.hover_revision + 1

		if source == "trigger" then
			state.trigger_hovered = false
		else
			state.popup_hovered = false
		end

		cancel_hover_close()

		local revision = state.hover_revision
		local timer
		timer = easybar.after(HOVER_CLOSE_DELAY_SECONDS, function()
			if state.hover_close_timer == timer then
				state.hover_close_timer = nil
			end

			if revision == state.hover_revision and not state.trigger_hovered and not state.popup_hovered then
				state.popup_open = false
				render()
			end
		end)
		state.hover_close_timer = timer
	end

	--- Adds popup hover handling to a node.
	---@param node EasyBarNodeHandle
	local function attach_popup_hover(node)
		node:subscribe(easybar.events.mouse.entered, function()
			open_popup("popup")
		end)
		node:subscribe(easybar.events.mouse.exited, function()
			schedule_popup_close("popup")
		end)
	end

	github:subscribe(easybar.events.mouse.entered, function()
		open_popup("trigger")
	end)
	github:subscribe(easybar.events.mouse.exited, function()
		schedule_popup_close("trigger")
	end)

	attach_popup_hover(popup_header)
	attach_popup_hover(popup_footer)
	for index, row in ipairs(popup_rows) do
		local row_index = index
		attach_popup_hover(row)
		row:subscribe(easybar.events.mouse.clicked, function(event)
			if event.button ~= nil and event.button ~= easybar.events.mouse.left_button then
				return
			end

			local notification = state.notifications[row_index]
			if notification ~= nil then
				open_url(notification_url(notification))
			end
		end)
	end

	github:subscribe(easybar.events.mouse.clicked, function(event)
		if event.button == nil or event.button == easybar.events.mouse.left_button then
			open_url(GITHUB_NOTIFICATIONS_URL)
		end
	end)

	github:subscribe(easybar.events.context_menu.clicked, function(event)
		if event.action_id == "refresh" then
			refresh()
		elseif event.action_id == "open" then
			open_url(GITHUB_NOTIFICATIONS_URL)
		end
	end)

	github:subscribe({ easybar.events.forced, easybar.events.system_woke }, function()
		refresh()
	end)

	render()
	refresh()
end
