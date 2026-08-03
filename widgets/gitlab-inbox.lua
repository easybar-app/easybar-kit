-- Inbox-only assigned GitLab work items. Requires an authenticated `glab` CLI.

local retry = require("retry")
local text = require("text")

local SOURCE = "GitLab"
---@type EasyBarInboxSourcePresentation
local SOURCE_PRESENTATION = {
	name = "GitLab",
	icon = easybar.asset("assets/gitlab.svg"),
	color = "#FC6D26",
}
local POLL_INTERVAL_SECONDS = 300
local NETWORK_READY_DELAY_SECONDS = 3
local REFRESH_BACKOFF_SECONDS = { 2, 5 }
local work_items = {}
local refreshing = false
local pending_refresh = nil
local source_activity = nil
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

local function publish_error(message)
	easybar.inbox.replace(SOURCE, {
		{
			id = "error",
			title = "GitLab work items unavailable",
			body = message,
			severity = "error",
			source = SOURCE_PRESENTATION,
			actions = { { id = "refresh", title = "Refresh" } },
		},
	})
end

local function fetch(endpoint, operation, complete)
	local current_attempt = 0
	retry.run(easybar, {
		delays = REFRESH_BACKOFF_SECONDS,
		attempt = function(done, attempt_number)
			current_attempt = attempt_number
			log(
				easybar.level.trace,
				"inbox command started operation=" .. operation .. " attempt=" .. tostring(attempt_number) .. " executable=glab"
			)

			return easybar.spawn_async({
				"/usr/bin/env",
				"GLAB_NO_PROMPT=1",
				"GLAB_SEND_TELEMETRY=false",
				"glab",
				"api",
				"--paginate",
				endpoint,
			}, {
				timeout_seconds = 30,
				max_output_bytes = 2097152,
				log_operation = operation,
			}, done)
		end,
		should_retry = function(output, code)
			local retryable = retry.is_transient_network_error(output, code)
			if retryable then
				log(
					easybar.level.trace,
					"inbox retry scheduled operation="
						.. operation
						.. " attempt="
						.. tostring(current_attempt)
						.. " next_attempt="
						.. tostring(current_attempt + 1)
						.. " delay_seconds="
						.. tostring(REFRESH_BACKOFF_SECONDS[current_attempt])
				)
			end
			return retryable
		end,
		on_complete = complete,
	})
end

local function publish(issues, merge_requests)
	work_items = {}

	for _, pair in ipairs({
		{ "issue", issues },
		{ "merge_request", merge_requests },
	}) do
		for _, item in ipairs(type(pair[2]) == "table" and pair[2] or {}) do
			item.kind = pair[1]
			work_items[#work_items + 1] = item
		end
	end

	local items = {}
	for _, item in ipairs(work_items) do
		local id = item.kind .. ":" .. tostring(item.id or item.iid)
		items[#items + 1] = {
			id = id,
			title = text.trim(item.title) ~= "" and item.title or "Untitled work item",
			body = type(item.references) == "table" and item.references.full or nil,
			category = item.kind == "merge_request" and "Merge requests" or "Issues",
			severity = "info",
			unread = true,
			source = SOURCE_PRESENTATION,
			actions = {
				{ id = "mark_read", title = "Mark as read" },
				{ id = "open", title = "Open" },
			},
		}
	end

	easybar.inbox.replace(SOURCE, items)
	log(
		easybar.level.debug,
		"inbox snapshot published operation=refresh issues="
			.. tostring(#issues)
			.. " merge_requests="
			.. tostring(#merge_requests)
			.. " items="
			.. tostring(#items)
	)

	return #items
end

local function finish_error(operation, output, fallback, attempts, code)
	refreshing = false
	set_source_activity(nil)
	log(
		easybar.level.warn,
		"inbox refresh failed operation="
			.. operation
			.. " attempts="
			.. tostring(attempts or 1)
			.. " status="
			.. tostring(code or 1)
	)

	publish_error(text.trim(output) ~= "" and text.trim(output) or fallback)
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

	local issues_endpoint =
		"issues?scope=assigned_to_me&state=opened&non_archived=true&order_by=updated_at&sort=desc&per_page=100"
	local merge_requests_endpoint =
		"merge_requests?scope=assigned_to_me&state=opened&non_archived=true&order_by=updated_at&sort=desc&per_page=100"

	fetch(issues_endpoint, "fetch_issues", function(issues_output, issues_code, issues_attempts, issues_metadata)
		if issues_code ~= 0 then
			finish_error(
				"fetch_issues",
				issues_output,
				"Run 'glab auth login' and check app.env PATH",
				issues_attempts,
				issues_code
			)
			return
		end

		local issues_ok, issues = pcall(easybar.json.decode, issues_output)
		if not issues_ok or type(issues) ~= "table" then
			log(easybar.level.warn, "inbox response invalid operation=fetch_issues format=json")
			finish_error(
				"fetch_issues",
				"GitLab returned invalid issues JSON",
				"GitLab returned invalid issues JSON",
				issues_attempts,
				1
			)
			return
		end

		fetch(merge_requests_endpoint, "fetch_merge_requests", function(mrs_output, mrs_code, mrs_attempts, mrs_metadata)
			refreshing = false
			set_source_activity(nil)

			if mrs_code ~= 0 then
				log(
					easybar.level.warn,
					"inbox refresh failed operation=fetch_merge_requests attempts="
						.. tostring(mrs_attempts)
						.. " status="
						.. tostring(mrs_code)
				)
				publish_error(
					text.trim(mrs_output) ~= "" and text.trim(mrs_output) or "Run 'glab auth login' and check app.env PATH"
				)
				return
			end

			local mrs_ok, merge_requests = pcall(easybar.json.decode, mrs_output)
			if not mrs_ok or type(merge_requests) ~= "table" then
				log(easybar.level.warn, "inbox response invalid operation=fetch_merge_requests format=json")
				publish_error("GitLab returned invalid merge request JSON")
				return
			end

			local item_count = publish(issues, merge_requests)
			log(
				easybar.level.debug,
				"inbox refresh completed reason="
					.. reason
					.. " issue_attempts="
					.. tostring(issues_attempts)
					.. " merge_request_attempts="
					.. tostring(mrs_attempts)
					.. " items="
					.. tostring(item_count)
					.. " duration_ms="
					.. tostring((issues_metadata.duration_ms or 0) + (mrs_metadata.duration_ms or 0))
			)
		end)
	end)
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

local function open_work_item(item, item_id)
	log(easybar.level.debug, "inbox item open started item_id=" .. item_id)

	easybar.spawn_async({ "open", item.web_url }, { log_operation = "open_work_item" }, function(_, code)
		if code ~= 0 then
			log(easybar.level.warn, "inbox item open failed item_id=" .. item_id .. " status=" .. tostring(code))
		end
	end)
end

easybar.inbox.on_action(SOURCE, function(event)
	local action_id = tostring(event.action_id or "unknown")
	local item_id = tostring(event.target_widget_id or "")

	log(easybar.level.debug, "inbox action received action=" .. action_id .. " item_id=" .. item_id)

	if action_id == "refresh" then
		refresh("manual")
	elseif action_id == "mark_read" then
		log(easybar.level.trace, "inbox item marked read locally item_id=" .. item_id)
	elseif action_id == "open" then
		for _, item in ipairs(work_items) do
			if item.kind .. ":" .. tostring(item.id or item.iid) == item_id then
				open_work_item(item, item_id)
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

local timer = easybar.add(easybar.kind.item, "gitlab_inbox_timer", {
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
