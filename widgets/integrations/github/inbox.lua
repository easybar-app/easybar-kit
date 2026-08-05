--- Bundled github widget implementation.
---@param easybar EasyBar Widget-scoped EasyBar API from the top-level entrypoint.
return function(easybar)
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
	local PR_VIEW_TIMEOUT_SECONDS = 20
	local PR_MERGE_TIMEOUT_SECONDS = 5 * 60

	local STORAGE_WIDGET = "github-inbox"
	local STORAGE_MERGE_METHOD_KEY = "merge_method"
	local STORAGE_CONFIRM_MERGE_KEY = "confirm_merge"
	local DEFAULT_PR_MERGE_METHOD = "squash"
	local DEFAULT_CONFIRM_MERGE = true
	local PR_MERGE_METHOD_ORDER = { "merge", "squash", "rebase" }
	local PR_MERGE_FLAGS = {
		merge = "--merge",
		rebase = "--rebase",
		squash = "--squash",
	}
	local PR_MERGE_METHOD_TITLES = {
		merge = "Merge commit",
		rebase = "Rebase and merge",
		squash = "Squash and merge",
	}
	local PR_MERGE_METHOD_STATUS = {
		merge = "merge with a merge commit",
		rebase = "rebase and merge",
		squash = "squash and merge",
	}
	local configured_merge_method = easybar.storage.get(STORAGE_WIDGET, STORAGE_MERGE_METHOD_KEY, DEFAULT_PR_MERGE_METHOD)
	local pr_merge_method = PR_MERGE_FLAGS[configured_merge_method] ~= nil and configured_merge_method
		or DEFAULT_PR_MERGE_METHOD
	local configured_confirm_merge = easybar.storage.get(STORAGE_WIDGET, STORAGE_CONFIRM_MERGE_KEY, DEFAULT_CONFIRM_MERGE)
	local merge_confirmation_required = type(configured_confirm_merge) == "boolean" and configured_confirm_merge
		or DEFAULT_CONFIRM_MERGE
	local notifications = {}
	local current_error = nil
	local active_refresh = nil
	local queued_refresh = nil
	local pending_refresh = nil
	local source_activity = nil
	local busy_item_actions = {}
	local merge_confirmations = {}
	local log = easybar.log

	if pr_merge_method ~= configured_merge_method then
		log(
			easybar.level.warn,
			"unsupported configured merge_method=" .. tostring(configured_merge_method) .. "; using squash"
		)
	end
	if merge_confirmation_required ~= configured_confirm_merge then
		log(
			easybar.level.warn,
			"unsupported configured confirm_merge=" .. tostring(configured_confirm_merge) .. "; using true"
		)
	end

	local function merge_method_title(method)
		return PR_MERGE_METHOD_TITLES[method] or tostring(method)
	end

	local function append_merge_method_actions(actions)
		actions[#actions + 1] = {
			id = "merge_method",
			title = "Merge method",
			enabled = false,
		}
		for _, method in ipairs(PR_MERGE_METHOD_ORDER) do
			actions[#actions + 1] = {
				id = "merge_method:" .. method,
				title = (method == pr_merge_method and "✓ " or "") .. merge_method_title(method),
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

	local function notification_url(notification)
		local repository = type(notification.repository.html_url) == "string"
				and text.trim(notification.repository.html_url)
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

	local function append_action(actions, id, title, enabled, busy)
		actions[#actions + 1] = {
			id = id,
			title = title,
			enabled = enabled,
			busy = busy,
		}
	end

	local function item_actions(notification, item_id)
		local actions = {}
		local busy_action = busy_item_actions[item_id]
		local confirmation = merge_confirmations[item_id]

		if busy_action == "mark_read" then
			append_action(actions, "mark_read", "Marking read…", false, true)
		elseif busy_action == "prepare_merge" then
			append_action(actions, "prepare_merge", "Checking merge…", false, true)
		elseif busy_action == "confirm_merge" then
			append_action(actions, "confirm_merge", "Merging…", false, true)
		elseif confirmation ~= nil then
			append_action(actions, "confirm_merge", "Confirm " .. merge_method_title(pr_merge_method), true, false)
			append_action(actions, "cancel_merge", "Cancel", true, false)
		else
			append_action(actions, "mark_read", "Mark as read", true, false)
			if notification.subject.type == "PullRequest" then
				append_action(actions, "prepare_merge", "Merge", true, false)
			end
		end

		return actions
	end

	local function publish_current_notifications()
		local items = {}
		if current_error ~= nil then
			items[#items + 1] = {
				id = "error",
				title = current_error.title or "GitHub notifications unavailable",
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
				local body = repository .. (text.trim(notification.reason) ~= "" and " · " .. notification.reason or "")
				if merge_confirmations[item_id] ~= nil then
					body = body .. " · ready to " .. PR_MERGE_METHOD_STATUS[pr_merge_method]
				end
				items[#items + 1] = {
					id = item_id,
					title = subject.title,
					body = body,
					category = text.trim(subject.type) ~= "" and subject.type or "Notification",
					severity = "info",
					unread = true,
					timestamp = inbox.timestamp(notification.updated_at),
					url = notification_url(notification),
					source = SOURCE_PRESENTATION,
					actions = item_actions(notification, item_id),
				}
			end
		end

		easybar.inbox.replace(SOURCE, items)
		log(easybar.level.debug, "inbox snapshot published operation=refresh items=" .. tostring(#notifications))
		return #notifications
	end

	local function publish_error(output, fallback, title)
		current_error = {
			title = title or "GitHub notifications unavailable",
			message = inbox.error_message(output, fallback),
			timestamp = os.time(),
		}
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
		merge_confirmations = {}
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
					busy_item_actions[item_id] = nil
					merge_confirmations[item_id] = nil
				end
				if code ~= 0 then
					log(
						easybar.level.warn,
						"inbox refresh failed reason="
							.. reason
							.. " attempts="
							.. tostring(attempts)
							.. " status="
							.. tostring(code)
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

		log(
			easybar.level.trace,
			"inbox refresh scheduled reason=" .. reason .. " delay_seconds=" .. tostring(delay_seconds)
		)

		pending_refresh = easybar.after(delay_seconds, function()
			pending_refresh = nil
			refresh(reason)
		end)
	end

	local function notification_for_id(item_id)
		for _, notification in ipairs(notifications) do
			if tostring(notification.id) == item_id then
				return notification
			end
		end
		return nil
	end

	local function pull_request_target(notification)
		if notification == nil or notification.subject.type ~= "PullRequest" then
			return nil, nil
		end

		local repository = text.trim(notification.repository.full_name)
		local api_url = type(notification.subject.url) == "string" and text.trim(notification.subject.url) or ""
		local number = api_url:match("/(%d+)$")
		if repository == "" or number == nil then
			return nil, nil
		end

		return repository, number
	end

	local function decode_pull_request_state(output)
		local ok, payload = pcall(easybar.json.decode, tostring(output or ""))
		if not ok or type(payload) ~= "table" or easybar.json.is_array(payload) then
			return nil, "GitHub returned invalid pull request details"
		end

		local review_decision = payload.reviewDecision
		if review_decision == easybar.json.null then
			review_decision = nil
		end

		if type(payload.state) ~= "string" then
			return nil, "GitHub returned a pull request without a state"
		end
		if type(payload.isDraft) ~= "boolean" then
			return nil, "GitHub returned an invalid draft state"
		end
		if type(payload.mergeable) ~= "string" then
			return nil, "GitHub returned an invalid mergeable state"
		end
		if type(payload.mergeStateStatus) ~= "string" then
			return nil, "GitHub returned an invalid merge status"
		end
		if review_decision ~= nil and type(review_decision) ~= "string" then
			return nil, "GitHub returned an invalid review decision"
		end
		if type(payload.headRefOid) ~= "string" or text.trim(payload.headRefOid) == "" then
			return nil, "GitHub returned a pull request without a head commit"
		end

		return {
			state = payload.state,
			is_draft = payload.isDraft,
			mergeable = payload.mergeable,
			merge_state_status = payload.mergeStateStatus,
			review_decision = review_decision,
			head_oid = payload.headRefOid,
		},
			nil
	end

	local function merge_block_reason(pull_request)
		if pull_request.state ~= "OPEN" then
			return "The pull request is no longer open."
		end
		if pull_request.is_draft then
			return "Draft pull requests cannot be merged from the inbox."
		end
		if pull_request.review_decision == "CHANGES_REQUESTED" then
			return "Changes have been requested on this pull request."
		end
		if pull_request.review_decision == "REVIEW_REQUIRED" then
			return "The pull request still requires a review."
		end
		if pull_request.mergeable == "CONFLICTING" then
			return "The pull request has merge conflicts."
		end
		if pull_request.mergeable ~= "MERGEABLE" then
			return "GitHub has not determined that the pull request is mergeable yet."
		end
		if pull_request.merge_state_status == "BEHIND" then
			return "The pull request branch must be updated before merging."
		elseif pull_request.merge_state_status == "BLOCKED" then
			return "Repository rules currently block this pull request from merging."
		elseif pull_request.merge_state_status == "DIRTY" then
			return "The pull request cannot be merged cleanly."
		elseif pull_request.merge_state_status == "UNSTABLE" then
			return "The pull request checks are not passing."
		elseif pull_request.merge_state_status == "UNKNOWN" then
			return "GitHub has not finished calculating the merge state."
		elseif pull_request.merge_state_status ~= "CLEAN" and pull_request.merge_state_status ~= "HAS_HOOKS" then
			return "The pull request is not currently ready to merge."
		end

		return nil
	end

	local confirm_merge

	local function prepare_merge(item_id)
		if item_id == "" or busy_item_actions[item_id] ~= nil then
			return
		end

		local notification = notification_for_id(item_id)
		local repository, number = pull_request_target(notification)
		if repository == nil then
			publish_error(nil, "The notification does not contain a valid pull request target", "Could not prepare merge")
			return
		end

		busy_item_actions[item_id] = "prepare_merge"
		merge_confirmations[item_id] = nil
		current_error = nil
		publish_current_notifications()
		log(
			easybar.level.info,
			"inbox mutation started operation=prepare_merge item_id="
				.. item_id
				.. " repository="
				.. repository
				.. " number="
				.. number
		)

		easybar.spawn_async({
			"gh",
			"pr",
			"view",
			number,
			"--repo",
			repository,
			"--json",
			"state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefOid",
		}, {
			timeout_seconds = PR_VIEW_TIMEOUT_SECONDS,
			max_output_bytes = 1024 * 1024,
			log_operation = "prepare_merge",
		}, function(output, code)
			busy_item_actions[item_id] = nil
			if code ~= 0 then
				log(
					easybar.level.error,
					"inbox mutation failed operation=prepare_merge item_id=" .. item_id .. " status=" .. tostring(code)
				)
				publish_error(output, "GitHub could not inspect the pull request", "Could not prepare merge")
				return
			end

			local pull_request, decode_error = decode_pull_request_state(output)
			if pull_request == nil then
				publish_error(nil, decode_error, "Could not prepare merge")
				return
			end

			local blocked_reason = merge_block_reason(pull_request)
			if blocked_reason ~= nil then
				publish_error(nil, blocked_reason, "Pull request cannot be merged")
				return
			end

			merge_confirmations[item_id] = {
				repository = repository,
				number = number,
				head_oid = pull_request.head_oid,
			}
			current_error = nil
			log(easybar.level.info, "inbox mutation completed operation=prepare_merge item_id=" .. item_id)
			if merge_confirmation_required then
				publish_current_notifications()
			else
				confirm_merge(item_id)
			end
		end)
	end

	local function refresh_after_merge(item_id)
		easybar.spawn_async({ "gh", "api", "--method", "PATCH", "notifications/threads/" .. item_id }, {
			timeout_seconds = 20,
			log_operation = "mark_read_after_merge",
		}, function(_, code)
			if code ~= 0 then
				log(
					easybar.level.warn,
					"inbox mutation failed operation=mark_read_after_merge item_id=" .. item_id .. " status=" .. tostring(code)
				)
			end
			refresh("post_merge", item_id)
		end)
	end

	confirm_merge = function(item_id)
		local confirmation = merge_confirmations[item_id]
		if confirmation == nil or busy_item_actions[item_id] ~= nil then
			return
		end

		local merge_flag = PR_MERGE_FLAGS[pr_merge_method]
		if merge_flag == nil then
			publish_error(
				nil,
				"Unsupported pull request merge method: " .. tostring(pr_merge_method),
				"Could not merge pull request"
			)
			return
		end

		busy_item_actions[item_id] = "confirm_merge"
		merge_confirmations[item_id] = nil
		current_error = nil
		publish_current_notifications()
		log(
			easybar.level.info,
			"inbox mutation started operation=merge item_id="
				.. item_id
				.. " repository="
				.. confirmation.repository
				.. " number="
				.. confirmation.number
		)

		easybar.spawn_async({
			"/usr/bin/env",
			"GH_PROMPT_DISABLED=1",
			"gh",
			"pr",
			"merge",
			confirmation.number,
			"--repo",
			confirmation.repository,
			merge_flag,
			"--match-head-commit",
			confirmation.head_oid,
		}, {
			timeout_seconds = PR_MERGE_TIMEOUT_SECONDS,
			max_output_bytes = 1024 * 1024,
			log_operation = "merge",
		}, function(output, code)
			if code ~= 0 then
				busy_item_actions[item_id] = nil
				log(
					easybar.level.error,
					"inbox mutation failed operation=merge item_id=" .. item_id .. " status=" .. tostring(code)
				)
				publish_error(output, "GitHub could not merge the pull request", "Pull request merge failed")
				return
			end

			log(easybar.level.info, "inbox mutation completed operation=merge item_id=" .. item_id)
			refresh_after_merge(item_id)
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
		publish_current_notifications()
	end

	local function set_merge_method(method)
		if PR_MERGE_FLAGS[method] == nil then
			log(easybar.level.warn, "unsupported merge method selection=" .. tostring(method))
			return
		end
		if method == pr_merge_method then
			configure_source_actions()
			return
		end

		local ok, err = easybar.storage.set(STORAGE_WIDGET, STORAGE_MERGE_METHOD_KEY, method)
		if not ok then
			log(easybar.level.error, "inbox setting failed key=" .. STORAGE_MERGE_METHOD_KEY .. " error=" .. tostring(err))
			publish_error(err, "EasyBar could not update config.toml", "Could not save merge method")
			return
		end

		local previous_method = pr_merge_method
		pr_merge_method = method
		merge_confirmations = {}
		current_error = nil
		log(
			easybar.level.info,
			"inbox setting updated key=" .. STORAGE_MERGE_METHOD_KEY .. " previous=" .. previous_method .. " value=" .. method
		)
		configure_source_actions()
		publish_current_notifications()
	end

	easybar.inbox.on_action(SOURCE, function(event)
		local action_id = tostring(event.action_id or "unknown")
		local item_id = tostring(event.target_widget_id or "")
		log(easybar.level.debug, "inbox action received action=" .. action_id .. " item_id=" .. item_id)

		if action_id == "refresh" then
			refresh("manual")
		elseif action_id == "mark_read" then
			if item_id ~= "" and busy_item_actions[item_id] == nil then
				busy_item_actions[item_id] = "mark_read"
				merge_confirmations[item_id] = nil
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
						busy_item_actions[item_id] = nil
						log(
							easybar.level.error,
							"inbox mutation failed operation=mark_read item_id=" .. item_id .. " status=" .. tostring(code)
						)
						publish_error(nil, "GitHub could not mark the notification as read")
					end
				end)
			end
		elseif action_id == "prepare_merge" then
			prepare_merge(item_id)
		elseif action_id == "confirm_merge" then
			confirm_merge(item_id)
		elseif action_id == "cancel_merge" then
			merge_confirmations[item_id] = nil
			publish_current_notifications()
		end
	end)

	easybar.inbox.on_context_action(SOURCE, function(event)
		local action_id = tostring(event.action_id or "unknown")
		local merge_method = action_id:match("^merge_method:([%w_%-]+)$")
		local merge_confirmation = action_id:match("^merge_confirmation:([%w_%-]+)$")
		log(easybar.level.debug, "inbox context action received action=" .. action_id)
		if action_id == "refresh" then
			refresh("manual")
		elseif merge_method ~= nil then
			set_merge_method(merge_method)
		elseif merge_confirmation == "required" then
			set_merge_confirmation_required(true)
		elseif merge_confirmation == "immediate" then
			set_merge_confirmation_required(false)
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
end
