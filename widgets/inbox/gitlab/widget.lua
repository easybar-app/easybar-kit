-- Inbox-only assigned GitLab work items. Requires an authenticated `glab` CLI.

local inbox = require("inbox")
local retry = require("retry")
local text = require("text")

local SOURCE = "GitLab"
---@type EasyBarInboxSourcePresentation
local SOURCE_PRESENTATION = {
	name = "GitLab",
	icon = easybar.asset("@/assets/gitlab.svg"),
	color = "#FC6D26",
}
local POLL_INTERVAL_SECONDS = 300
local NETWORK_READY_DELAY_SECONDS = 3
local REFRESH_BACKOFF_SECONDS = { 2, 5 }
local MAX_ITEMS = 500
local MERGE_REQUEST_VIEW_TIMEOUT_SECONDS = 20
local MERGE_REQUEST_MERGE_TIMEOUT_SECONDS = 5 * 60

local STORAGE_WIDGET = "gitlab-inbox"
local STORAGE_MERGE_METHOD_KEY = "merge_method"
local STORAGE_CONFIRM_MERGE_KEY = "confirm_merge"
local DEFAULT_MERGE_METHOD = "merge"
local DEFAULT_CONFIRM_MERGE = false
local MERGE_METHOD_ORDER = { "merge", "squash", "rebase" }
local MERGE_METHOD_FLAGS = {
	merge = false,
	rebase = "--rebase",
	squash = "--squash",
}
local MERGE_METHOD_TITLES = {
	merge = "Project default",
	rebase = "Rebase and merge",
	squash = "Squash and merge",
}
local MERGE_METHOD_STATUS = {
	merge = "merge with the project default",
	rebase = "rebase and merge",
	squash = "squash and merge",
}

local configured_merge_method = easybar.storage.get(STORAGE_WIDGET, STORAGE_MERGE_METHOD_KEY, DEFAULT_MERGE_METHOD)
local merge_method = MERGE_METHOD_FLAGS[configured_merge_method] ~= nil and configured_merge_method
	or DEFAULT_MERGE_METHOD
local configured_confirm_merge = easybar.storage.get(STORAGE_WIDGET, STORAGE_CONFIRM_MERGE_KEY, DEFAULT_CONFIRM_MERGE)
local merge_confirmation_required = type(configured_confirm_merge) == "boolean" and configured_confirm_merge
	or DEFAULT_CONFIRM_MERGE
local issues = {}
local merge_requests = {}
local current_error = nil
local refreshing = false
local refresh_queued = false
local pending_refresh = nil
local source_activity = nil
local busy_item_actions = {}
local merge_confirmations = {}
local log = easybar.log

if merge_method ~= configured_merge_method then
	log(
		easybar.level.warn,
		"unsupported configured merge_method=" .. tostring(configured_merge_method) .. "; using merge"
	)
end
if merge_confirmation_required ~= configured_confirm_merge then
	log(
		easybar.level.warn,
		"unsupported configured confirm_merge=" .. tostring(configured_confirm_merge) .. "; using  false"
	)
end

local function merge_method_title(method)
	return MERGE_METHOD_TITLES[method] or tostring(method)
end

local function append_merge_method_actions(actions)
	actions[#actions + 1] = {
		id = "merge_method",
		title = "Merge method",
		enabled = false,
	}
	for _, method in ipairs(MERGE_METHOD_ORDER) do
		actions[#actions + 1] = {
			id = "merge_method:" .. method,
			title = (method == merge_method and "✓ " or "") .. merge_method_title(method),
		}
	end
end

local function append_merge_confirmation_actions(actions)
	actions[#actions + 1] = {
		id = "merge_confirmation",
		title = "Merge confirmation",
		enabled = false,
	}
	actions[#actions + 1] = {
		id = "merge_confirmation:required",
		title = (merge_confirmation_required and "✓ " or "") .. "Require confirmation",
	}
	actions[#actions + 1] = {
		id = "merge_confirmation:immediate",
		title = (not merge_confirmation_required and "✓ " or "") .. "Merge immediately",
	}
end

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
	append_merge_method_actions(actions)
	append_merge_confirmation_actions(actions)
	easybar.inbox.configure(SOURCE, { actions = actions })
end

local function set_source_activity(title)
	source_activity = title
	configure_source_actions()
end

configure_source_actions()

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

local function append_action(actions, id, title, enabled, busy)
	actions[#actions + 1] = {
		id = id,
		title = title,
		enabled = enabled,
		busy = busy,
	}
end

local function item_actions(work_item)
	local actions = {}
	local item_id = work_item.id
	local busy_action = busy_item_actions[item_id]
	local confirmation = merge_confirmations[item_id]

	if busy_action == "prepare_merge" then
		append_action(actions, "prepare_merge", "Checking merge…", false, true)
	elseif busy_action == "confirm_merge" then
		append_action(actions, "confirm_merge", "Merging…", false, true)
	elseif confirmation ~= nil then
		append_action(actions, "confirm_merge", "Confirm " .. merge_method_title(merge_method), true, false)
		append_action(actions, "cancel_merge", "Cancel", true, false)
	else
		append_action(actions, "mark_read", "Mark as read", true, false)
		if work_item.kind == "merge_request" then
			append_action(actions, "prepare_merge", "Merge", true, false)
		end
	end

	return actions
end

local function publish()
	local work_items = {}
	for _, pair in ipairs({ { "issue", issues }, { "merge_request", merge_requests } }) do
		for _, item in ipairs(pair[2]) do
			work_items[#work_items + 1] = {
				id = pair[1] .. ":" .. tostring(item.id),
				kind = pair[1],
				item = item,
				timestamp = inbox.timestamp(item.updated_at),
			}
		end
	end
	table.sort(work_items, function(left, right)
		if left.timestamp == right.timestamp then
			return left.id < right.id
		end
		return left.timestamp > right.timestamp
	end)

	local items = {}
	if current_error ~= nil then
		items[#items + 1] = {
			id = "error",
			title = current_error.title or "GitLab work items unavailable",
			body = current_error.message,
			severity = "error",
			unread = true,
			timestamp = current_error.timestamp,
			source = SOURCE_PRESENTATION,
			actions = { { id = "refresh", title = "Refresh" } },
		}
	end
	for _, work_item in ipairs(work_items) do
		if #items < MAX_ITEMS then
			local item = work_item.item
			local body = type(item.references) == "table" and item.references.full or nil
			if merge_confirmations[work_item.id] ~= nil then
				body = text.trim(body)
				body = (body ~= "" and body .. " · " or "") .. "ready to " .. MERGE_METHOD_STATUS[merge_method]
			end
			items[#items + 1] = {
				id = work_item.id,
				title = item.title,
				body = body,
				category = work_item.kind == "merge_request" and "Merge requests" or "Issues",
				severity = "info",
				unread = true,
				timestamp = work_item.timestamp,
				url = item.web_url,
				source = SOURCE_PRESENTATION,
				actions = item_actions(work_item),
			}
		end
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

local function publish_error(output, fallback, title)
	current_error = {
		title = title or "GitLab work items unavailable",
		message = inbox.error_message(output, fallback),
		timestamp = os.time(),
	}
	publish()
end

local function valid_work_item(item, kind)
	if type(item) ~= "table" then
		return false
	end
	local id_type = type(item.id)
	if (id_type ~= "string" and id_type ~= "number") or text.trim(item.id) == "" then
		return false
	end
	if type(item.title) ~= "string" or text.trim(item.title) == "" then
		return false
	end
	if type(item.web_url) ~= "string" or text.trim(item.web_url) == "" then
		return false
	end
	if item.references ~= nil and item.references ~= easybar.json.null then
		if type(item.references) ~= "table" then
			return false
		end
		if item.references.full ~= nil and type(item.references.full) ~= "string" then
			return false
		end
	end
	if kind == "merge_request" then
		local iid_type = type(item.iid)
		local project_id_type = type(item.project_id)
		if (iid_type ~= "string" and iid_type ~= "number") or text.trim(item.iid) == "" then
			return false
		end
		if (project_id_type ~= "string" and project_id_type ~= "number") or text.trim(item.project_id) == "" then
			return false
		end
		if text.trim(item.web_url):match("^(.-)/%-/merge_requests/%d+/?$") == nil then
			return false
		end
	end
	return inbox.timestamp(item.updated_at) ~= nil
end

local function decode_work_items(output, kind)
	local decoded = inbox.decode_array(easybar.json, output)
	if decoded == nil then
		return nil
	end
	for _, item in ipairs(decoded) do
		if not valid_work_item(item, kind) then
			return nil
		end
	end
	return decoded
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

	publish_error(output, fallback)
end

local refresh

local function run_queued_refresh()
	if refresh_queued then
		refresh_queued = false
		refresh("queued")
	end
end

refresh = function(reason)
	reason = tostring(reason or "unspecified")
	if refreshing then
		refresh_queued = true
		log(easybar.level.trace, "inbox refresh queued reason=" .. reason .. " state=already_refreshing")
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
			run_queued_refresh()
			return
		end

		local refreshed_issues = decode_work_items(issues_output, "issue")
		if refreshed_issues == nil then
			log(easybar.level.warn, "inbox response invalid operation=fetch_issues format=json")
			finish_error("fetch_issues", nil, "GitLab returned an invalid issues response", issues_attempts, 1)
			run_queued_refresh()
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
				publish_error(mrs_output, "Run 'glab auth login' and check app.env PATH")
				run_queued_refresh()
				return
			end

			local refreshed_merge_requests = decode_work_items(mrs_output, "merge_request")
			if refreshed_merge_requests == nil then
				log(easybar.level.warn, "inbox response invalid operation=fetch_merge_requests format=json")
				publish_error(nil, "GitLab returned an invalid merge request response")
				run_queued_refresh()
				return
			end

			issues = refreshed_issues
			merge_requests = refreshed_merge_requests
			merge_confirmations = {}
			current_error = nil
			local item_count = publish()
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
			run_queued_refresh()
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

local function merge_request_for_item_id(item_id)
	local global_id = item_id:match("^merge_request:(.+)$")
	if global_id == nil then
		return nil
	end
	for _, merge_request in ipairs(merge_requests) do
		if tostring(merge_request.id) == global_id then
			return merge_request
		end
	end
	return nil
end

local function merge_request_target(merge_request)
	if merge_request == nil then
		return nil
	end

	local repository = text.trim(merge_request.web_url):match("^(.-)/%-/merge_requests/%d+/?$")
	local project_id = text.trim(merge_request.project_id)
	local iid = text.trim(merge_request.iid)
	if repository == nil or repository == "" or project_id == "" or iid == "" then
		return nil
	end

	return {
		repository = repository,
		project_id = project_id,
		iid = iid,
	}
end

local function decode_merge_request_state(output)
	local ok, payload = pcall(easybar.json.decode, tostring(output or ""))
	if not ok or type(payload) ~= "table" or easybar.json.is_array(payload) then
		return nil, "GitLab returned invalid merge request details"
	end

	local draft = payload.draft
	if draft == nil or draft == easybar.json.null then
		draft = payload.work_in_progress
	end
	if type(payload.state) ~= "string" then
		return nil, "GitLab returned a merge request without a state"
	end
	if type(draft) ~= "boolean" then
		return nil, "GitLab returned an invalid draft state"
	end
	if type(payload.detailed_merge_status) ~= "string" then
		return nil, "GitLab returned an invalid detailed merge status"
	end
	if type(payload.sha) ~= "string" or text.trim(payload.sha) == "" then
		return nil, "GitLab returned a merge request without a head commit"
	end

	return {
		state = payload.state,
		draft = draft,
		detailed_merge_status = payload.detailed_merge_status,
		head_sha = payload.sha,
	},
		nil
end

local MERGE_BLOCK_REASONS = {
	approvals_syncing = "The merge request approvals are still syncing.",
	checking = "GitLab is still checking whether the merge request can be merged.",
	ci_must_pass = "The merge request pipeline must pass before merging.",
	ci_still_running = "The merge request pipeline is still running.",
	commits_status = "The source branch is missing or does not contain mergeable commits.",
	conflict = "The merge request has conflicts.",
	discussions_not_resolved = "All merge request discussions must be resolved before merging.",
	draft_status = "Draft merge requests cannot be merged from the inbox.",
	jira_association_missing = "The merge request does not satisfy the required Jira association.",
	locked_lfs_files = "Locked Git LFS files prevent this merge request from merging.",
	locked_paths = "Locked paths prevent this merge request from merging.",
	merge_request_blocked = "Another merge request blocks this merge request.",
	merge_time = "The configured merge time has not been reached.",
	need_rebase = "The merge request must be rebased before merging.",
	not_approved = "The merge request still requires approval.",
	not_open = "The merge request is no longer open.",
	preparing = "GitLab is still preparing the merge request diff.",
	requested_changes = "A reviewer has requested changes on this merge request.",
	security_policy_pipeline_check = "Security policy pipelines must pass before merging.",
	security_policy_violations = "Security policy violations prevent this merge request from merging.",
	status_checks_must_pass = "All status checks must pass before merging.",
	title_regex = "The merge request title does not satisfy the project rules.",
	unchecked = "GitLab has not checked whether the merge request can be merged yet.",
}

local function merge_block_reason(merge_request)
	if merge_request.state ~= "opened" then
		return "The merge request is no longer open."
	end
	if merge_request.draft then
		return "Draft merge requests cannot be merged from the inbox."
	end
	if merge_request.detailed_merge_status == "mergeable" then
		return nil
	end
	return MERGE_BLOCK_REASONS[merge_request.detailed_merge_status]
		or "The merge request is not currently ready to merge."
end

local confirm_merge

local function prepare_merge(item_id)
	if item_id == "" or busy_item_actions[item_id] ~= nil then
		return
	end

	local merge_request = merge_request_for_item_id(item_id)
	local target = merge_request_target(merge_request)
	if target == nil then
		publish_error(nil, "The work item does not contain a valid merge request target", "Could not prepare merge")
		return
	end

	busy_item_actions[item_id] = "prepare_merge"
	merge_confirmations[item_id] = nil
	current_error = nil
	publish()
	log(
		easybar.level.info,
		"inbox mutation started operation=prepare_merge item_id="
			.. item_id
			.. " project_id="
			.. target.project_id
			.. " iid="
			.. target.iid
	)

	easybar.spawn_async({
		"/usr/bin/env",
		"GLAB_NO_PROMPT=1",
		"GLAB_SEND_TELEMETRY=false",
		"glab",
		"api",
		"projects/" .. target.project_id .. "/merge_requests/" .. target.iid .. "?with_merge_status_recheck=true",
	}, {
		timeout_seconds = MERGE_REQUEST_VIEW_TIMEOUT_SECONDS,
		max_output_bytes = 1024 * 1024,
		log_operation = "prepare_merge",
	}, function(output, code)
		busy_item_actions[item_id] = nil
		if code ~= 0 then
			log(
				easybar.level.error,
				"inbox mutation failed operation=prepare_merge item_id=" .. item_id .. " status=" .. tostring(code)
			)
			publish_error(output, "GitLab could not inspect the merge request", "Could not prepare merge")
			return
		end

		local state, decode_error = decode_merge_request_state(output)
		if state == nil then
			publish_error(nil, decode_error, "Could not prepare merge")
			return
		end

		local blocked_reason = merge_block_reason(state)
		if blocked_reason ~= nil then
			publish_error(nil, blocked_reason, "Merge request cannot be merged")
			return
		end

		merge_confirmations[item_id] = {
			repository = target.repository,
			project_id = target.project_id,
			iid = target.iid,
			head_sha = state.head_sha,
		}
		current_error = nil
		log(easybar.level.info, "inbox mutation completed operation=prepare_merge item_id=" .. item_id)
		if merge_confirmation_required then
			publish()
		else
			confirm_merge(item_id)
		end
	end)
end

local function remove_merge_request(item_id)
	local global_id = item_id:match("^merge_request:(.+)$")
	if global_id == nil then
		return
	end
	for index = #merge_requests, 1, -1 do
		if tostring(merge_requests[index].id) == global_id then
			table.remove(merge_requests, index)
			break
		end
	end
end

confirm_merge = function(item_id)
	local confirmation = merge_confirmations[item_id]
	if confirmation == nil or busy_item_actions[item_id] ~= nil then
		return
	end

	local method_flag = MERGE_METHOD_FLAGS[merge_method]
	if method_flag == nil then
		publish_error(nil, "Unsupported merge request method: " .. tostring(merge_method), "Could not merge merge request")
		return
	end

	busy_item_actions[item_id] = "confirm_merge"
	merge_confirmations[item_id] = nil
	current_error = nil
	publish()
	log(
		easybar.level.info,
		"inbox mutation started operation=merge item_id="
			.. item_id
			.. " project_id="
			.. confirmation.project_id
			.. " iid="
			.. confirmation.iid
	)

	local arguments = {
		"/usr/bin/env",
		"GLAB_NO_PROMPT=1",
		"GLAB_SEND_TELEMETRY=false",
		"glab",
		"mr",
		"merge",
		confirmation.iid,
		"--repo",
		confirmation.repository,
		"--auto-merge=false",
		"--yes",
		"--sha",
		confirmation.head_sha,
	}
	if method_flag ~= false then
		arguments[#arguments + 1] = method_flag
	end

	easybar.spawn_async(arguments, {
		timeout_seconds = MERGE_REQUEST_MERGE_TIMEOUT_SECONDS,
		max_output_bytes = 1024 * 1024,
		log_operation = "merge",
	}, function(output, code)
		busy_item_actions[item_id] = nil
		if code ~= 0 then
			log(
				easybar.level.error,
				"inbox mutation failed operation=merge item_id=" .. item_id .. " status=" .. tostring(code)
			)
			publish_error(output, "GitLab could not merge the merge request", "Merge request merge failed")
			return
		end

		remove_merge_request(item_id)
		current_error = nil
		log(easybar.level.info, "inbox mutation completed operation=merge item_id=" .. item_id)
		publish()
		refresh("post_merge")
	end)
end

local function set_merge_confirmation_required(required)
	if type(required) ~= "boolean" then
		log(easybar.level.warn, "unsupported merge confirmation selection=" .. tostring(required))
		return
	end
	if required == merge_confirmation_required then
		configure_source_actions()
		return
	end

	local ok, err = easybar.storage.set(STORAGE_WIDGET, STORAGE_CONFIRM_MERGE_KEY, required)
	if not ok then
		log(easybar.level.error, "inbox setting failed key=" .. STORAGE_CONFIRM_MERGE_KEY .. " error=" .. tostring(err))
		publish_error(err, "EasyBar could not update config.toml", "Could not save merge confirmation")
		return
	end

	local previous_value = merge_confirmation_required
	merge_confirmation_required = required
	merge_confirmations = {}
	current_error = nil
	log(
		easybar.level.info,
		"inbox setting updated key="
			.. STORAGE_CONFIRM_MERGE_KEY
			.. " previous="
			.. tostring(previous_value)
			.. " value="
			.. tostring(required)
	)
	configure_source_actions()
	publish()
end

local function set_merge_method(method)
	if MERGE_METHOD_FLAGS[method] == nil then
		log(easybar.level.warn, "unsupported merge method selection=" .. tostring(method))
		return
	end
	if method == merge_method then
		configure_source_actions()
		return
	end

	local ok, err = easybar.storage.set(STORAGE_WIDGET, STORAGE_MERGE_METHOD_KEY, method)
	if not ok then
		log(easybar.level.error, "inbox setting failed key=" .. STORAGE_MERGE_METHOD_KEY .. " error=" .. tostring(err))
		publish_error(err, "EasyBar could not update config.toml", "Could not save merge method")
		return
	end

	local previous_method = merge_method
	merge_method = method
	merge_confirmations = {}
	current_error = nil
	log(
		easybar.level.info,
		"inbox setting updated key=" .. STORAGE_MERGE_METHOD_KEY .. " previous=" .. previous_method .. " value=" .. method
	)
	configure_source_actions()
	publish()
end

easybar.inbox.on_action(SOURCE, function(event)
	local action_id = tostring(event.action_id or "unknown")
	local item_id = tostring(event.target_widget_id or "")

	log(easybar.level.debug, "inbox action received action=" .. action_id .. " item_id=" .. item_id)

	if action_id == "refresh" then
		refresh("manual")
	elseif action_id == "prepare_merge" then
		prepare_merge(item_id)
	elseif action_id == "confirm_merge" then
		confirm_merge(item_id)
	elseif action_id == "cancel_merge" then
		merge_confirmations[item_id] = nil
		publish()
	end
end)

easybar.inbox.on_context_action(SOURCE, function(event)
	local action_id = tostring(event.action_id or "unknown")
	local selected_merge_method = action_id:match("^merge_method:([%w_%-]+)$")
	local merge_confirmation = action_id:match("^merge_confirmation:([%w_%-]+)$")
	log(easybar.level.debug, "inbox context action received action=" .. action_id)

	if action_id == "refresh" then
		refresh("manual")
	elseif selected_merge_method ~= nil then
		set_merge_method(selected_merge_method)
	elseif merge_confirmation == "required" then
		set_merge_confirmation_required(true)
	elseif merge_confirmation == "immediate" then
		set_merge_confirmation_required(false)
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
