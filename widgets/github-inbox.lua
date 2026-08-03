-- Inbox-only GitHub notifications. Requires an authenticated `gh` CLI.

local retry = require("retry")
local text = require("text")

local SOURCE = "GitHub"
---@type EasyBarInboxSourcePresentation
local SOURCE_PRESENTATION = {
	name = "GitHub",
	icon = easybar.asset("assets/github.svg"),
	color = "#A371F7",
}
local POLL_INTERVAL_SECONDS = 300
local NETWORK_READY_DELAY_SECONDS = 3
local REFRESH_BACKOFF_SECONDS = { 2, 5 }
local notifications = {}
local refreshing = false
local pending_refresh = nil
local source_activity = nil
local busy_item_ids = {}
local log = easybar.log

local function configure_source_actions()
	local actions
	if source_activity ~= nil then
		actions = {
			{
				id = "refresh",
				title = source_activity,
				enabled = false,
				busy = true,
				include_in_refresh_all = true,
			},
		}
	else
		actions = { { id = "refresh", title = "Refresh", include_in_refresh_all = true } }
	end
	easybar.inbox.configure(SOURCE, { actions = actions })
end

local function set_source_activity(title)
	source_activity = title
	configure_source_actions()
end

configure_source_actions()

local function notification_url(notification)
	local repository = type(notification.repository) == "table" and text.trim(notification.repository.html_url) or ""
	local subject = type(notification.subject) == "table" and notification.subject or {}
	local api_url = text.trim(subject.url)
	local number = api_url:match("/(%d+)$")
	if repository ~= "" and number ~= nil then
		if subject.type == "PullRequest" then
			return repository .. "/pull/" .. number
		elseif subject.type == "Issue" then
			return repository .. "/issues/" .. number
		elseif subject.type == "Discussion" then
			return repository .. "/discussions/" .. number
		end
	end
	return "https://github.com/notifications"
end

local function publish_error(message)
	easybar.inbox.replace(SOURCE, {
		{
			id = "error",
			title = "GitHub notifications unavailable",
			body = message,
			severity = "error",
			source = SOURCE_PRESENTATION,
			actions = { { id = "refresh", title = "Refresh" } },
		},
	})
end

local function publish_current_notifications()
	local items = {}
	for _, notification in ipairs(notifications) do
		local repository = type(notification.repository) == "table" and notification.repository.full_name or "GitHub"
		local subject = type(notification.subject) == "table" and notification.subject or {}
		local item_id = tostring(notification.id or repository .. ":" .. tostring(subject.title))
		local marking_read = busy_item_ids[item_id] == true
		items[#items + 1] = {
			id = item_id,
			title = text.trim(subject.title) ~= "" and subject.title or "Untitled notification",
			body = repository .. (text.trim(notification.reason) ~= "" and " · " .. notification.reason or ""),
			category = text.trim(subject.type) ~= "" and subject.type or "Notification",
			severity = "info",
			unread = true,
			source = SOURCE_PRESENTATION,
			actions = {
				{
					id = "mark_read",
					title = marking_read and "Marking read…" or "Mark as read",
					enabled = not marking_read,
					busy = marking_read,
				},
				{ id = "open", title = "Open" },
			},
		}
	end

	easybar.inbox.replace(SOURCE, items)
	log(easybar.level.debug, "inbox snapshot published operation=refresh items=" .. tostring(#items))
	return #items
end

local function publish_notifications(output)
	local ok, pages = pcall(easybar.json.decode, output)
	if not ok or type(pages) ~= "table" then
		log(easybar.level.warn, "inbox response invalid operation=refresh format=json")
		publish_error("GitHub returned invalid JSON")
		return nil
	end

	notifications = {}
	for _, page in ipairs(pages) do
		for _, notification in ipairs(type(page) == "table" and page or {}) do
			notifications[#notifications + 1] = notification
		end
	end

	return publish_current_notifications()
end

local function refresh(reason)
	reason = tostring(reason or "unspecified")
	if refreshing then
		log(easybar.level.trace, "inbox refresh skipped reason=" .. reason .. " state=already_refreshing")
		return
	end

	if pending_refresh ~= nil then
		pending_refresh:cancel()
		pending_refresh = nil
	end

	refreshing = true
	set_source_activity("Refreshing…")
	log(easybar.level.debug, "inbox refresh started reason=" .. reason)

	local current_attempt = 0
	retry.run(easybar, {
		delays = REFRESH_BACKOFF_SECONDS,
		attempt = function(done, attempt_number)
			current_attempt = attempt_number
			log(
				easybar.level.trace,
				"inbox command started operation=refresh attempt=" .. tostring(attempt_number) .. " executable=gh"
			)
			return easybar.spawn_async({
				"gh",
				"api",
				"--paginate",
				"--slurp",
				"-H",
				"Accept: application/vnd.github+json",
				"notifications?all=false&per_page=100",
			}, { timeout_seconds = 20, max_output_bytes = 1048576, log_operation = "refresh" }, done)
		end,
		should_retry = function(output, code)
			local retryable = retry.is_transient_network_error(output, code)
			if retryable then
				log(
					easybar.level.trace,
					"inbox retry scheduled operation=refresh attempt="
						.. tostring(current_attempt)
						.. " next_attempt="
						.. tostring(current_attempt + 1)
						.. " delay_seconds="
						.. tostring(REFRESH_BACKOFF_SECONDS[current_attempt])
				)
			end
			return retryable
		end,
		on_complete = function(output, code, attempts, metadata)
			refreshing = false
			set_source_activity(nil)
			if code ~= 0 then
				log(
					easybar.level.warn,
					"inbox refresh failed reason=" .. reason .. " attempts=" .. tostring(attempts) .. " status=" .. tostring(code)
				)
				publish_error(text.trim(output) ~= "" and text.trim(output) or "Run 'gh auth login' and check app.env PATH")
				return
			end

			local item_count = publish_notifications(output)
			if item_count ~= nil then
				log(
					easybar.level.debug,
					"inbox refresh completed reason="
						.. reason
						.. " attempts="
						.. tostring(attempts)
						.. " items="
						.. tostring(item_count)
						.. " duration_ms="
						.. tostring(metadata.duration_ms or 0)
				)
			end
		end,
	})
end

local function schedule_refresh(reason, delay_seconds)
	reason = tostring(reason or "unspecified")
	delay_seconds = tonumber(delay_seconds) or 0

	if pending_refresh ~= nil then
		pending_refresh:cancel()
	end

	log(easybar.level.trace, "inbox refresh scheduled reason=" .. reason .. " delay_seconds=" .. tostring(delay_seconds))

	pending_refresh = easybar.after(delay_seconds, function()
		pending_refresh = nil
		refresh(reason)
	end)
end

local function open_notification(notification)
	local item_id = tostring(notification.id)
	log(easybar.level.debug, "inbox item open started item_id=" .. item_id)
	easybar.spawn_async(
		{ "open", notification_url(notification) },
		{ log_operation = "open_notification" },
		function(_, code)
			if code ~= 0 then
				log(easybar.level.warn, "inbox item open failed item_id=" .. item_id .. " status=" .. tostring(code))
			end
		end
	)
end

easybar.inbox.on_action(SOURCE, function(event)
	local action_id = tostring(event.action_id or "unknown")
	local item_id = tostring(event.target_widget_id or "")
	log(easybar.level.debug, "inbox action received action=" .. action_id .. " item_id=" .. item_id)

	if action_id == "refresh" then
		refresh("manual")
	elseif action_id == "mark_read" then
		if item_id ~= "" and not busy_item_ids[item_id] then
			busy_item_ids[item_id] = true
			publish_current_notifications()
			log(easybar.level.info, "inbox mutation started operation=mark_read item_id=" .. item_id)
			easybar.spawn_async({ "gh", "api", "--method", "PATCH", "notifications/threads/" .. item_id }, {
				timeout_seconds = 20,
				log_operation = "mark_read",
			}, function(_, code)
				busy_item_ids[item_id] = nil
				publish_current_notifications()
				if code == 0 then
					log(easybar.level.info, "inbox mutation completed operation=mark_read item_id=" .. item_id)
					refresh("post_mutation")
				else
					log(
						easybar.level.error,
						"inbox mutation failed operation=mark_read item_id=" .. item_id .. " status=" .. tostring(code)
					)
				end
			end)
		end
	elseif action_id == "open" then
		for _, notification in ipairs(notifications) do
			if tostring(notification.id) == item_id then
				open_notification(notification)
				break
			end
		end
	end
end)

easybar.inbox.on_context_action(SOURCE, function(event)
	local action_id = tostring(event.action_id or "unknown")
	log(easybar.level.debug, "inbox context action received action=" .. action_id)
	if action_id == "refresh" then
		refresh("manual")
	end
end)

local timer = easybar.add(easybar.kind.item, "github_inbox_timer", {
	drawing = false,
	interval = POLL_INTERVAL_SECONDS,
	on_interval = function()
		refresh("interval")
	end,
})

timer:subscribe(easybar.events.forced, function()
	refresh("forced")
end)

timer:subscribe(easybar.events.system_woke, function()
	schedule_refresh("wake", NETWORK_READY_DELAY_SECONDS)
end)

schedule_refresh("startup", NETWORK_READY_DELAY_SECONDS)
