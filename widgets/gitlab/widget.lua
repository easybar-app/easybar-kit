-- GitLab work-items widget. Requires an authenticated `glab` CLI.
-- Set GITLAB_HOST in app.env for a self-managed or dedicated instance.

local text = require("text")

---@alias GitLabWorkItemKind "issue"|"merge_request"

---@class GitLabWorkItem
---@field id? integer
---@field iid? integer
---@field title? string
---@field updated_at? string
---@field web_url? string
---@field references? { full?: string }
---@field kind? GitLabWorkItemKind

---@class GitLabWidgetState
---@field items GitLabWorkItem[]
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

local configured_host = text.trim(os.getenv("GITLAB_HOST"))
if configured_host == "" then
	configured_host = "https://gitlab.com"
elseif not configured_host:match("^https?://") then
	configured_host = "https://" .. configured_host
end
local GITLAB_URL = configured_host:gsub("/+$", "")

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

---@type GitLabWidgetState
local state = {
	items = {},
	error = nil,
	loading = false,
	popup_open = false,
	trigger_hovered = false,
	popup_hovered = false,
	hover_revision = 0,
	hover_close_timer = nil,
}

local gitlab
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
			easybar.log(easybar.level.warn, "failed to open GitLab URL", url)
		end
	end)
end

--- Returns the project-qualified reference for one work item.
---@param item GitLabWorkItem
---@return string
local function item_reference(item)
	if type(item.references) == "table" then
		local reference = text.trim(item.references.full)
		if reference ~= "" then
			return reference
		end
	end

	return item.kind == "merge_request" and "Merge request" or "Issue"
end

--- Returns the compact popup label for one work item.
---@param item GitLabWorkItem
---@return string
local function item_text(item)
	local title = text.trim(item.title)
	if title == "" then
		title = "Untitled"
	end

	return text.truncate(item_reference(item) .. "  ·  " .. title, 100)
end

--- Appends decoded work items while attaching their API kind.
---@param target GitLabWorkItem[]
---@param source unknown
---@param kind GitLabWorkItemKind
---@return boolean valid
local function append_items(target, source, kind)
	if type(source) ~= "table" then
		return false
	end

	for _, item in ipairs(source) do
		if type(item) == "table" then
			item.kind = kind
			table.insert(target, item)
		end
	end

	return true
end

--- Combines and sorts issue and merge-request API responses.
---@param issues unknown
---@param merge_requests unknown
---@return GitLabWorkItem[]? items
---@return string? error_message
local function combine_items(issues, merge_requests)
	local items = {}
	if not append_items(items, issues, "issue") or not append_items(items, merge_requests, "merge_request") then
		return nil, "GitLab returned an unexpected response"
	end

	table.sort(items, function(left, right)
		return text.trim(left.updated_at) > text.trim(right.updated_at)
	end)

	return items, nil
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

--- Renders the GitLab popup from the current state.
local function render_popup()
	local count = #state.items

	if state.error ~= nil then
		popup_header:set({
			drawing = true,
			label = { string = "GitLab work items unavailable", color = COLORS.danger },
		})
		popup_rows[1]:set({
			drawing = true,
			label = { string = text.truncate(state.error, 100), color = COLORS.text },
		})
		for index = 2, MAX_POPUP_ITEMS do
			popup_rows[index]:set({ drawing = false })
		end
	else
		popup_header:set({
			drawing = true,
			label = {
				string = count == 1 and "1 assigned GitLab work item" or tostring(count) .. " assigned GitLab work items",
				color = count == 0 and COLORS.muted or COLORS.accent,
			},
		})

		for index, row in ipairs(popup_rows) do
			local item = state.items[index]
			if item == nil then
				row:set({ drawing = false })
			else
				row:set({
					drawing = true,
					label = { string = item_text(item), color = COLORS.text },
				})
			end
		end
	end

	popup_footer:set({
		drawing = true,
		label = {
			string = state.loading and "Refreshing..." or "Click an item to open it · Right-click to refresh",
			color = COLORS.muted,
		},
	})
end

--- Renders the bar item and popup.
local function render()
	local color = state.error ~= nil and COLORS.danger or (#state.items > 0 and COLORS.accent or COLORS.muted)

	gitlab:set({
		icon = {
			string = "󰮠",
			color = color,
		},
		label = {
			string = state.error ~= nil and "!" or tostring(#state.items),
			color = color,
		},
		background = {
			color = (state.trigger_hovered or state.popup_hovered) and COLORS.surface_hover or easybar.theme.ref.transparent,
			border_color = easybar.theme.ref.transparent,
			border_width = 0,
			corner_radius = 8,
		},
		popup = popup_props(state.popup_open),
	})

	render_popup()
end

--- Fetches assigned GitLab issues and merge requests.
local function refresh()
	if state.loading then
		return
	end

	state.loading = true
	render()

	local issues_endpoint =
		"issues?scope=assigned_to_me&state=opened&non_archived=true&order_by=updated_at&sort=desc&per_page=100"
	local merge_requests_endpoint =
		"merge_requests?scope=assigned_to_me&state=opened&non_archived=true&order_by=updated_at&sort=desc&per_page=100"
	local options = { timeout_seconds = 30, max_output_bytes = 2097152 }

	--- Stores one request failure and clears results that would otherwise be incomplete.
	---@param output string
	---@param fallback string
	local function fail(output, fallback)
		state.loading = false
		local message = text.trim(output)
		state.error = message ~= "" and message or fallback
		state.items = {}
		render()
	end

	--- Runs one authenticated GitLab API request without shell parsing.
	---@param endpoint string
	---@param callback EasyBarCommandCallback
	local function fetch(endpoint, callback)
		easybar.spawn_async({
			"/usr/bin/env",
			"GLAB_NO_PROMPT=1",
			"glab",
			"api",
			"--paginate",
			endpoint,
		}, options, callback)
	end

	-- Fetch sequentially so the widget never publishes a half-refreshed issue/MR snapshot.
	fetch(issues_endpoint, function(issues_output, issues_code)
		if issues_code ~= 0 then
			fail(issues_output, "Run 'glab auth login' and verify GITLAB_HOST and app.env PATH")
			return
		end

		local issues_ok, issues = pcall(easybar.json.decode, issues_output)
		if not issues_ok or type(issues) ~= "table" then
			fail("", "GitLab returned invalid issues JSON")
			return
		end

		fetch(merge_requests_endpoint, function(merge_requests_output, merge_requests_code)
			state.loading = false
			if merge_requests_code ~= 0 then
				local message = text.trim(merge_requests_output)
				state.error = message ~= "" and message or "Run 'glab auth login' and verify GITLAB_HOST and app.env PATH"
				state.items = {}
				render()
				return
			end

			local merge_requests_ok, merge_requests = pcall(easybar.json.decode, merge_requests_output)
			if not merge_requests_ok or type(merge_requests) ~= "table" then
				state.error = "GitLab returned invalid merge request JSON"
				state.items = {}
				render()
				return
			end

			local items, combine_error = combine_items(issues, merge_requests)
			if items == nil then
				state.error = combine_error
				state.items = {}
			else
				state.error = nil
				state.items = items
			end
			render()
		end)
	end)
end

gitlab = easybar.add(easybar.kind.item, "gitlab_work_items", {
	position = "right",
	order = 0,
	interval = POLL_INTERVAL_SECONDS,
	on_interval = refresh,
	icon = { string = "GL", color = COLORS.muted },
	label = { string = "0", color = COLORS.muted },
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
		{ id = "open", title = "Open GitLab" },
	},
})

popup_header = easybar.add(easybar.kind.item, "gitlab_work_items_header", {
	position = "popup." .. gitlab.name,
	order = 0,
	drawing = true,
	label = { string = "GitLab work items", color = COLORS.accent },
	padding_x = 8,
	padding_y = 5,
})

for index = 1, MAX_POPUP_ITEMS do
	popup_rows[index] = easybar.add(easybar.kind.item, "gitlab_work_item_" .. tostring(index), {
		position = "popup." .. gitlab.name,
		order = index,
		drawing = false,
		label = { string = "", color = COLORS.text },
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

popup_footer = easybar.add(easybar.kind.item, "gitlab_work_items_footer", {
	position = "popup." .. gitlab.name,
	order = MAX_POPUP_ITEMS + 1,
	drawing = true,
	label = { string = "Click an item to open it · Right-click to refresh", color = COLORS.muted },
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
	state.trigger_hovered = source == "trigger" or state.trigger_hovered
	state.popup_hovered = source == "popup" or state.popup_hovered
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

gitlab:subscribe(easybar.events.mouse.entered, function()
	open_popup("trigger")
end)
gitlab:subscribe(easybar.events.mouse.exited, function()
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
		local item = state.items[row_index]
		if item ~= nil then
			open_url(item.web_url)
		end
	end)
end

gitlab:subscribe(easybar.events.mouse.clicked, function(event)
	if event.button == nil or event.button == easybar.events.mouse.left_button then
		open_url(GITLAB_URL .. "/dashboard/issues")
	end
end)

gitlab:subscribe(easybar.events.context_menu.clicked, function(event)
	if event.action_id == "refresh" then
		refresh()
	elseif event.action_id == "open" then
		open_url(GITLAB_URL)
	end
end)

gitlab:subscribe({ easybar.events.forced, easybar.events.system_woke }, function()
	refresh()
end)

render()
refresh()
