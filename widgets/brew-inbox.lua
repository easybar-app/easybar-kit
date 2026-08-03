-- Inbox-only Homebrew updates. Requires Homebrew in app.env PATH.

local retry = require("retry")
local text = require("text")

local SOURCE = "Homebrew"
---@type EasyBarInboxSourcePresentation
local SOURCE_PRESENTATION = {
	name = "Homebrew",
	icon = easybar.asset("assets/brew.svg"),
	color = "#FBB040",
}
local POLL_INTERVAL_SECONDS = 30 * 60
local NETWORK_READY_DELAY_SECONDS = 3
local MIN_ACTIVITY_COMPLETION_DELAY_SECONDS = 0.2
local REFRESH_BACKOFF_SECONDS = { 2, 5 }

local EXEC = {
	check = { timeout_seconds = 30, max_output_bytes = 1024 * 1024, log_operation = "refresh" },
	update = { timeout_seconds = 5 * 60, max_output_bytes = 2 * 1024 * 1024 },
	upgrade = { timeout_seconds = 30 * 60, max_output_bytes = 4 * 1024 * 1024 },
}

local state = {
	formulae = {},
	casks = {},
	warning = nil,
	error = nil,
	operation = nil,
	active_operation = nil,
	operation_kind = nil,
	operation_id = nil,
	operation_item_id = nil,
	can_cancel = false,
	cancellation_requested = false,
}
local pending_refresh = nil
local refresh
local log = easybar.log

local function split_outdated_output(raw)
	raw = tostring(raw or "")
	local json_start = raw:find("{", 1, true)
	local json_end = nil
	if json_start ~= nil then
		for index = json_start, #raw do
			if raw:sub(index, index) == "}" then
				json_end = index
			end
		end
	end
	if json_start == nil or json_end == nil then
		return nil, nil, "Homebrew output did not contain a JSON object"
	end
	local warning = text.trim(raw:sub(1, json_start - 1) .. "\n" .. raw:sub(json_end + 1))
	return raw:sub(json_start, json_end), warning, nil
end

local function warning_source(raw)
	local owner, tap, token = tostring(raw or ""):match("/Taps/([^/]+)/homebrew%-([^/]+)/Casks/([^/]+)%.rb:%d+")
	if owner == nil then
		owner, tap, token = tostring(raw or ""):match("/Taps/([^/]+)/homebrew%-([^/]+)/Formula/([^/]+)%.rb:%d+")
	end
	if token == nil then
		return "Homebrew"
	end
	return token .. " · " .. owner .. "/" .. tap
end

local function parse_warning(raw)
	raw = text.trim(raw)
	if raw == "" then
		return nil
	end
	return {
		source = warning_source(raw),
		message = text.truncate(raw, 12000, "…"),
	}
end

local function parse_packages(entries, kind)
	local packages = {}
	for _, entry in ipairs(type(entries) == "table" and entries or {}) do
		local name = entry.name or entry.token or entry.full_token
		if type(name) == "string" and name ~= "" then
			local installed_versions = entry.installed_versions or {}
			local installed = #installed_versions > 0 and table.concat(installed_versions, ", ") or entry.installed_version
			packages[#packages + 1] = {
				id = kind .. ":" .. name,
				kind = kind,
				name = name,
				installed = text.trim(installed) ~= "" and tostring(installed) or "?",
				current = text.trim(entry.current_version) ~= "" and tostring(entry.current_version) or "?",
				pinned = entry.pinned == true,
			}
		end
	end
	table.sort(packages, function(left, right)
		return left.name < right.name
	end)
	return packages
end

local function decode_outdated(output)
	local json, warning, split_error = split_outdated_output(output)
	if json == nil then
		return nil, nil, nil, split_error
	end
	local ok, payload = pcall(easybar.json.decode, json)
	if not ok or type(payload) ~= "table" then
		return nil, nil, nil, "Homebrew returned invalid JSON"
	end
	return parse_packages(payload.formulae, "formula"), parse_packages(payload.casks, "cask"), parse_warning(warning), nil
end

local function all_packages()
	local packages = {}
	for _, package in ipairs(state.formulae) do
		packages[#packages + 1] = package
	end
	for _, package in ipairs(state.casks) do
		packages[#packages + 1] = package
	end
	return packages
end

local function reset_operation_state()
	state.active_operation = nil
	state.operation = nil
	state.operation_kind = nil
	state.operation_id = nil
	state.operation_item_id = nil
	state.can_cancel = false
	state.cancellation_requested = false
end

local function operation_is_active()
	return state.operation_id ~= nil
end

local function configure_source_actions()
	local actions
	if operation_is_active() then
		local is_refresh = state.operation_kind == "refresh"
		actions = {
			{
				id = is_refresh and "refresh" or "activity",
				title = state.operation or "Working…",
				enabled = false,
				busy = state.operation_item_id == nil,
				include_in_refresh_all = is_refresh or nil,
			},
		}
		if state.can_cancel then
			actions[#actions + 1] = {
				id = "cancel",
				title = state.cancellation_requested and "Cancelling…" or "Cancel",
				enabled = not state.cancellation_requested,
			}
		end
	else
		actions = {
			{ id = "refresh", title = "Refresh", include_in_refresh_all = true },
			{ id = "update", title = "Update" },
			{ id = "upgrade_all", title = "Upgrade all" },
		}
	end
	easybar.inbox.configure(SOURCE, { actions = actions })
end

local function publish()
	local operation_active = operation_is_active()
	local items = {}
	for _, package in ipairs(all_packages()) do
		local actions = {}
		local upgrading_this_package = state.operation_id == "upgrade_package" and state.operation_item_id == package.id
		if upgrading_this_package then
			actions = {
				{
					id = "upgrade",
					title = state.cancellation_requested and "Cancelling…" or "Upgrading…",
					enabled = false,
					busy = true,
				},
			}
		elseif not package.pinned and not operation_active then
			actions = { { id = "upgrade", title = "Upgrade" } }
		end
		items[#items + 1] = {
			id = package.id,
			title = package.name,
			body = package.installed .. " → " .. package.current .. (package.pinned and " · pinned" or ""),
			category = package.kind == "cask" and "Casks" or "Formulae",
			severity = package.pinned and "warning" or "info",
			unread = true,
			source = SOURCE_PRESENTATION,
			actions = actions,
		}
	end

	if state.warning ~= nil then
		items[#items + 1] = {
			id = "warning",
			title = state.warning.source .. " warning",
			body = state.warning.message,
			severity = "warning",
			unread = true,
			source = SOURCE_PRESENTATION,
		}
	end

	if state.error ~= nil then
		items[#items + 1] = {
			id = "error",
			title = state.error.title,
			body = state.error.message,
			severity = "error",
			unread = true,
			source = SOURCE_PRESENTATION,
			actions = { { id = "refresh", title = "Refresh" } },
		}
	end

	configure_source_actions()
	easybar.inbox.replace(SOURCE, items)
end

local function complete_operation(callback)
	state.active_operation = nil
	state.can_cancel = false
	publish()
	easybar.after(MIN_ACTIVITY_COMPLETION_DELAY_SECONDS, function()
		reset_operation_state()
		callback()
	end)
end

local function apply_outdated(output)
	local formulae, casks, warning, decode_error = decode_outdated(output)
	if formulae == nil then
		state.error = { title = "Could not check outdated packages", message = decode_error }
		log(easybar.level.warn, "inbox response invalid operation=refresh format=json")
		return false
	end
	state.formulae = formulae
	state.casks = casks
	state.warning = warning
	state.error = nil
	return true
end

refresh = function(reason)
	reason = tostring(reason or "unspecified")
	if operation_is_active() then
		log(
			easybar.level.trace,
			"inbox refresh skipped reason="
				.. reason
				.. " state=operation_active operation="
				.. tostring(state.operation_id or "unknown")
		)
		return
	end

	if pending_refresh ~= nil then
		pending_refresh:cancel()
		pending_refresh = nil
	end

	state.operation = "Checking outdated packages…"
	state.cancellation_requested = false
	state.can_cancel = true
	state.operation_kind = "refresh"
	state.operation_id = "refresh"
	state.operation_item_id = nil
	log(easybar.level.debug, "inbox refresh started reason=" .. reason)
	publish()

	local current_attempt = 0
	state.active_operation = retry.run(easybar, {
		delays = REFRESH_BACKOFF_SECONDS,
		attempt = function(done, attempt_number)
			current_attempt = attempt_number
			log(
				easybar.level.trace,
				"inbox command started operation=refresh attempt=" .. tostring(attempt_number) .. " executable=brew"
			)
			return easybar.spawn_async({
				"/usr/bin/env",
				"HOMEBREW_NO_AUTO_UPDATE=1",
				"brew",
				"outdated",
				"--json=v2",
			}, EXEC.check, done)
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
			complete_operation(function()
				if code ~= 0 then
					state.error = {
						title = "Could not check outdated packages",
						message = text.trim(output) ~= "" and text.truncate(output, 12000, "…")
							or "brew outdated exited with code " .. tostring(code),
					}
					log(
						easybar.level.warn,
						"inbox refresh failed reason="
							.. reason
							.. " attempts="
							.. tostring(attempts)
							.. " status="
							.. tostring(code)
					)
				else
					local decoded = apply_outdated(output)
					if decoded then
						log(
							easybar.level.debug,
							"inbox refresh completed reason="
								.. reason
								.. " attempts="
								.. tostring(attempts)
								.. " formulae="
								.. tostring(#state.formulae)
								.. " casks="
								.. tostring(#state.casks)
								.. " warning="
								.. tostring(state.warning ~= nil)
								.. " duration_ms="
								.. tostring(metadata.duration_ms or 0)
						)
					end
				end
				publish()
			end)
		end,
	})
end

local function run_operation(operation_id, label, arguments, options, item_id)
	if operation_is_active() then
		log(easybar.level.trace, "inbox mutation skipped operation=" .. operation_id .. " state=operation_active")
		return
	end
	state.operation = label .. "…"
	state.operation_kind = "mutation"
	state.operation_id = operation_id
	state.operation_item_id = item_id
	state.error = nil
	state.can_cancel = true
	state.cancellation_requested = false
	log(easybar.level.info, "inbox mutation started operation=" .. operation_id)

	local token
	local operation = {}
	function operation:cancel()
		return type(token) == "string" and easybar.cancel_async(token) or false
	end
	state.active_operation = operation
	local command_options = {}
	for key, value in pairs(options or {}) do
		command_options[key] = value
	end
	command_options.log_operation = operation_id
	token = easybar.spawn_async(arguments, command_options, function(output, code)
		local cancelled = state.cancellation_requested
		complete_operation(function()
			if cancelled then
				log(easybar.level.info, "inbox mutation cancelled operation=" .. operation_id)
				refresh("post_mutation")
				return
			end
			if code ~= 0 then
				state.error = {
					title = label .. " failed",
					message = text.trim(output) ~= "" and text.truncate(output, 12000, "…")
						or "Command exited with code " .. tostring(code),
				}
				log(easybar.level.error, "inbox mutation failed operation=" .. operation_id .. " status=" .. tostring(code))
				publish()
				return
			end
			log(easybar.level.info, "inbox mutation completed operation=" .. operation_id)
			refresh("post_mutation")
		end)
	end)
	publish()
end

local function package_for_id(id)
	for _, package in ipairs(all_packages()) do
		if package.id == id then
			return package
		end
	end
	return nil
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
	elseif action_id == "upgrade" then
		local package = package_for_id(item_id)
		if package ~= nil and not package.pinned then
			run_operation("upgrade_package", "Upgrade " .. package.name, {
				"/usr/bin/env",
				"HOMEBREW_NO_AUTO_UPDATE=1",
				"HOMEBREW_NO_ASK=1",
				"brew",
				"upgrade",
				"--" .. package.kind,
				"--yes",
				package.name,
			}, EXEC.upgrade, package.id)
		end
	end
end)

easybar.inbox.on_context_action(SOURCE, function(event)
	local action_id = tostring(event.action_id or "unknown")
	log(easybar.level.debug, "inbox context action received action=" .. action_id)

	if action_id == "cancel" then
		if state.active_operation ~= nil and state.can_cancel and not state.cancellation_requested then
			local operation_id = tostring(state.operation_id or "unknown")
			log(easybar.level.info, "inbox cancellation requested operation=" .. operation_id)
			if state.operation_kind == "refresh" then
				if state.active_operation:cancel() then
					state.active_operation = nil
					state.can_cancel = false
					state.cancellation_requested = true
					state.operation = "Cancelling Homebrew refresh…"
					publish()
					easybar.after(MIN_ACTIVITY_COMPLETION_DELAY_SECONDS, function()
						reset_operation_state()
						log(easybar.level.info, "inbox refresh cancelled operation=refresh")
						publish()
					end)
				end
			else
				state.cancellation_requested = true
				state.operation = "Cancelling Homebrew operation…"
				state.active_operation:cancel()
			end
			publish()
		end
	elseif action_id == "refresh" then
		refresh("manual")
	elseif action_id == "update" then
		run_operation("update", "Homebrew update", { "brew", "update" }, EXEC.update)
	elseif action_id == "upgrade_all" then
		run_operation("upgrade_all", "Homebrew upgrade", {
			"/usr/bin/env",
			"HOMEBREW_NO_AUTO_UPDATE=1",
			"HOMEBREW_NO_ASK=1",
			"brew",
			"upgrade",
			"--yes",
		}, EXEC.upgrade)
	end
end)

local timer = easybar.add(easybar.kind.item, "brew_inbox_timer", {
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

timer:subscribe(easybar.events.session_active, function()
	schedule_refresh("session_active", NETWORK_READY_DELAY_SECONDS)
end)

schedule_refresh("startup", NETWORK_READY_DELAY_SECONDS)
