-- Inbox-only GitHub notifications. Requires an authenticated `gh` CLI.

local inbox = require("inbox")
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
local MAX_ITEMS = 500
local notifications = {}
local current_error = nil
local active_refresh = nil
local queued_refresh = nil
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
	local repository = type(notification.repository.html_url) == "string" and text.trim(notification.repository.html_url)
		or ""
	local subject = type(notification.subject) == "table" and notification.subject or {}
	local api_url = type(subject.url) == "string" and text.trim(subject.url) or ""
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

local function publish_current_notifications()
	local items = {}
	if current_error ~= nil then
		items[#items + 1] = {
			id = "error",
			title = "GitHub notifications unavailable",
			body = current_error.message,
			severity = "error",
			unread = true,
			timestamp = current_error.timestamp,
			source = SOURCE_PRESENTATION,
			actions = { { id = "refresh", title = "Refresh" } },
		}
	end
	for _, notification in ipairs(notifications) do
		if #items < MAX_ITEMS then
			local repository = notification.repository.full_name
			local subject = notification.subject
			local item_id = tostring(notification.id)
			local marking_read = busy_item_ids[item_id] == true
			items[#items + 1] = {
				id = item_id,
				title = subject.title,
				body = repository .. (text.trim(notification.reason) ~= "" and " · " .. notification.reason or ""),
				category = text.trim(subject.type) ~= "" and subject.type or "Notification",
				severity = "info",
				unread = true,
				timestamp = inbox.timestamp(notification.updated_at),
				url = notification_url(notification),
				source = SOURCE_PRESENTATION,
				actions = {
					{
						id = "mark_read",
						title = marking_read and "Marking read…" or "Mark as read",
						enabled = not marking_read,
						busy = marking_read,
					},
				},
			}
		end
	end

	easybar.inbox.replace(SOURCE, items)
	log(easybar.level.debug, "inbox snapshot published operation=refresh items=" .. tostring(#notifications))
	return #notifications
end

local function publish_error(output, fallback)
	current_error = { message = inbox.error_message(output, fallback), timestamp = os.time() }
	publish_current_notifications()
end

local function valid_notification(notification)
	if type(notification) ~= "table" then
		return false
	end
	local id_type = type(notification.id)
	if (id_type ~= "string" and id_type ~= "number") or text.trim(notification.id) == "" then
		return false
	end
	if
		type(notification.repository) ~= "table"
		or type(notification.repository.full_name) ~= "string"
		or text.trim(notification.repository.full_name) == ""
	then
		return false
	end
	if
		type(notification.subject) ~= "table"
		or type(notification.subject.title) ~= "string"
		or text.trim(notification.subject.title) == ""
	then
		return false
	end
	if
		notification.repository.html_url ~= nil
		and notification.repository.html_url ~= easybar.json.null
		and type(notification.repository.html_url) ~= "string"
	then
		return false
	end
	if notification.reason ~= nil and type(notification.reason) ~= "string" then
		return false
	end
	if notification.subject.type ~= nil and type(notification.subject.type) ~= "string" then
		return false
	end
	if
		notification.subject.url ~= nil
		and notification.subject.url ~= easybar.json.null
		and type(notification.subject.url) ~= "string"
	then
		return false
	end
	return inbox.timestamp(notification.updated_at) ~= nil
end

local function decode_notifications(output)
	local pages = inbox.decode_array(easybar.json, output)
	if pages == nil then
		return nil
	end

	local decoded = {}
	for _, page in ipairs(pages) do
		if not easybar.json.is_array(page) then
			return nil
		end
		for _, notification in ipairs(page) do
			if not valid_notification(notification) then
				return nil
			end
			if #decoded < MAX_ITEMS then
				decoded[#decoded + 1] = notification
			end
		end
	end
	return decoded
end

local function publish_notifications(output)
	local decoded = decode_notifications(output)
	if decoded == nil then
		log(easybar.level.warn, "inbox response invalid operation=refresh format=json")
		publish_error(nil, "GitHub returned an invalid notification response")
		return nil
	end

	notifications = decoded
	current_error = nil
	return publish_current_notifications()
end

local refresh

local function merge_refresh_request(request, reason, activity_item_id)
	request = request or { reasons = {}, activity_item_ids = {}, show_source_activity = false }
	request.reasons[#request.reasons + 1] = tostring(reason or "unspecified")
	if activity_item_id == nil then
		request.show_source_activity = true
	else
		request.activity_item_ids[activity_item_id] = true
	end
	return request
end

local function start_refresh(request)
	if pending_refresh ~= nil then
		pending_refresh:cancel()
		pending_refresh = nil
	end

	active_refresh = request
	if request.show_source_activity then
		set_source_activity("Refreshing…")
	end
	local reason = table.concat(request.reasons, "+")
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
			active_refresh = nil
			if request.show_source_activity then
				set_source_activity(nil)
			end
			for item_id in pairs(request.activity_item_ids) do
				busy_item_ids[item_id] = nil
			end
			if code ~= 0 then
				log(
					easybar.level.warn,
					"inbox refresh failed reason=" .. reason .. " attempts=" .. tostring(attempts) .. " status=" .. tostring(code)
				)
				publish_error(output, "Run 'gh auth login' and check app.env PATH")
			else
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
			end

			local next_request = queued_refresh
			queued_refresh = nil
			if next_request ~= nil then
				log(easybar.level.trace, "inbox queued refresh starting reasons=" .. table.concat(next_request.reasons, "+"))
				start_refresh(next_request)
			end
		end,
	})
end

refresh = function(reason, activity_item_id)
	reason = tostring(reason or "unspecified")
	if active_refresh ~= nil then
		queued_refresh = merge_refresh_request(queued_refresh, reason, activity_item_id)
		log(easybar.level.trace, "inbox refresh queued reason=" .. reason .. " state=already_refreshing")
		return
	end
	start_refresh(merge_refresh_request(nil, reason, activity_item_id))
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
				if code == 0 then
					log(easybar.level.info, "inbox mutation completed operation=mark_read item_id=" .. item_id)
					refresh("post_mutation", item_id)
				else
					busy_item_ids[item_id] = nil
					log(
						easybar.level.error,
						"inbox mutation failed operation=mark_read item_id=" .. item_id .. " status=" .. tostring(code)
					)
					publish_error(nil, "GitHub could not mark the notification as read")
				end
			end)
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
