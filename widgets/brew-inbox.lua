-- Inbox-only Homebrew updates. Requires Homebrew in app.env PATH.

local inbox = require("inbox")
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
local MAX_ITEMS = 500

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
}
local pending_refresh = nil
local refresh
local log = easybar.log

local function json_object_end(raw, start_index)
	local depth = 0
	local in_string = false
	local escaped = false
	for index = start_index, #raw do
		local character = raw:sub(index, index)
		if in_string then
			if escaped then
				escaped = false
			elseif character == "\\" then
				escaped = true
			elseif character == '"' then
				in_string = false
			end
		elseif character == '"' then
			in_string = true
		elseif character == "{" then
			depth = depth + 1
		elseif character == "}" then
			depth = depth - 1
			if depth == 0 then
				return index
			end
		end
	end
	return nil
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
		timestamp = os.time(),
	}
end

local function parse_packages(entries, kind)
	local packages = {}
	for _, entry in ipairs(entries) do
		if type(entry) ~= "table" or easybar.json.is_array(entry) then
			return nil, "Homebrew returned an invalid " .. kind .. " entry"
		end
		local name = entry.name or entry.token or entry.full_token
		if type(name) ~= "string" or text.trim(name) == "" then
			return nil, "Homebrew returned a " .. kind .. " entry without a name"
		end

		local installed_versions = entry.installed_versions
		if installed_versions == easybar.json.null then
			installed_versions = nil
		end
		if installed_versions ~= nil and not easybar.json.is_array(installed_versions) then
			return nil, "Homebrew returned invalid installed versions for " .. name
		end
		local versions = {}
		for _, version in ipairs(installed_versions or {}) do
			if type(version) ~= "string" then
				return nil, "Homebrew returned an invalid installed version for " .. name
			end
			versions[#versions + 1] = version
		end
		local installed_version = entry.installed_version ~= easybar.json.null and entry.installed_version or nil
		local current_version = entry.current_version ~= easybar.json.null and entry.current_version or nil
		local pinned = entry.pinned ~= easybar.json.null and entry.pinned or nil
		if installed_version ~= nil and type(installed_version) ~= "string" then
			return nil, "Homebrew returned an invalid installed version for " .. name
		end
		if current_version ~= nil and type(current_version) ~= "string" then
			return nil, "Homebrew returned an invalid current version for " .. name
		end
		if pinned ~= nil and type(pinned) ~= "boolean" then
			return nil, "Homebrew returned an invalid pinned state for " .. name
		end

		local installed = #versions > 0 and table.concat(versions, ", ") or installed_version
		packages[#packages + 1] = {
			id = kind .. ":" .. name,
			kind = kind,
			name = name,
			installed = text.trim(installed) ~= "" and tostring(installed) or "?",
			current = text.trim(current_version) ~= "" and tostring(current_version) or "?",
			pinned = pinned == true,
		}
	end
	table.sort(packages, function(left, right)
		return left.name < right.name
	end)
	return packages, nil
end

local function decode_outdated(output)
	local raw = tostring(output or "")
	local search_from = 1
	local schema_error = nil
	while true do
		local json_start = raw:find("{", search_from, true)
		if json_start == nil then
			break
		end
		local json_end = json_object_end(raw, json_start)
		if json_end ~= nil then
			local ok, payload = pcall(easybar.json.decode, raw:sub(json_start, json_end))
			if ok and type(payload) == "table" and not easybar.json.is_array(payload) then
				if easybar.json.is_array(payload.formulae) and easybar.json.is_array(payload.casks) then
					local formulae, formula_error = parse_packages(payload.formulae, "formula")
					if formulae == nil then
						return nil, nil, nil, formula_error
					end
					local casks, cask_error = parse_packages(payload.casks, "cask")
					if casks == nil then
						return nil, nil, nil, cask_error
					end
					local warning = text.trim(raw:sub(1, json_start - 1) .. "\n" .. raw:sub(json_end + 1))
					return formulae, casks, parse_warning(warning), nil
				end
				schema_error = "Homebrew JSON did not contain formulae and casks arrays"
			end
		end
		search_from = json_start + 1
	end
	return nil, nil, nil, schema_error or "Homebrew output did not contain a valid JSON object"
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

local function operation_is_active()
	return state.operation ~= nil
end

local function configure_source_actions()
	local operation = state.operation
	local actions
	if operation ~= nil then
		local is_refresh = operation.kind == "refresh"
		actions = {
			{
				id = is_refresh and "refresh" or "activity",
				title = operation.title,
				enabled = false,
				busy = operation.item_id == nil,
				include_in_refresh_all = is_refresh or nil,
			},
		}
		if operation.can_cancel then
			actions[#actions + 1] = {
				id = "cancel",
				title = operation.cancellation_requested and "Cancelling…" or "Cancel",
				enabled = not operation.cancellation_requested,
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
	local operation = state.operation
	local items = {}
	if state.error ~= nil then
		items[#items + 1] = {
			id = "error",
			title = state.error.title,
			body = state.error.message,
			severity = "error",
			unread = true,
			timestamp = state.error.timestamp,
			source = SOURCE_PRESENTATION,
			actions = { { id = "refresh", title = "Refresh" } },
		}
	end
	if state.warning ~= nil then
		items[#items + 1] = {
			id = "warning",
			title = state.warning.source .. " warning",
			body = state.warning.message,
			severity = "warning",
			unread = true,
			timestamp = state.warning.timestamp,
			source = SOURCE_PRESENTATION,
		}
	end
	for _, package in ipairs(all_packages()) do
		if #items < MAX_ITEMS then
			local actions = {}
			local upgrading_this_package = operation ~= nil and operation.item_id == package.id
			if upgrading_this_package then
				actions = {
					{
						id = "upgrade",
						title = operation.cancellation_requested and "Cancelling…" or "Upgrading…",
						enabled = false,
						busy = true,
					},
				}
			elseif not package.pinned and operation == nil then
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
	end

	configure_source_actions()
	easybar.inbox.replace(SOURCE, items)
end

local function complete_operation(operation, callback)
	if state.operation ~= operation then
		return
	end
	operation.handle = nil
	operation.can_cancel = false
	publish()
	easybar.after(MIN_ACTIVITY_COMPLETION_DELAY_SECONDS, function()
		if state.operation == operation then
			state.operation = nil
			callback()
		end
	end)
end

local function apply_outdated(output)
	local formulae, casks, warning, decode_error = decode_outdated(output)
	if formulae == nil then
		state.error = { title = "Could not check outdated packages", message = decode_error, timestamp = os.time() }
		log(easybar.level.warn, "inbox response invalid operation=refresh format=json")
		return false
	end
	state.formulae = formulae
	state.casks = casks
	state.warning = warning
	state.error = nil
	return true
end

refresh = function(reason, activity_item_id)
	reason = tostring(reason or "unspecified")
	if operation_is_active() then
		log(
			easybar.level.trace,
			"inbox refresh skipped reason=" .. reason .. " state=operation_active operation=" .. tostring(state.operation.id)
		)
		return
	end

	if pending_refresh ~= nil then
		pending_refresh:cancel()
		pending_refresh = nil
	end

	local operation = {
		id = "refresh",
		kind = "refresh",
		title = "Checking outdated packages…",
		item_id = activity_item_id,
		can_cancel = true,
		cancellation_requested = false,
		handle = nil,
	}
	state.operation = operation
	log(easybar.level.debug, "inbox refresh started reason=" .. reason)
	publish()

	local current_attempt = 0
	operation.handle = retry.run(easybar, {
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
			complete_operation(operation, function()
				if code ~= 0 then
					state.error = {
						title = "Could not check outdated packages",
						message = inbox.error_message(output, "brew outdated exited with code " .. tostring(code)),
						timestamp = os.time(),
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
	local operation = {
		id = operation_id,
		kind = "mutation",
		title = label .. "…",
		item_id = item_id,
		can_cancel = true,
		cancellation_requested = false,
		handle = nil,
	}
	state.operation = operation
	state.error = nil
	log(easybar.level.info, "inbox mutation started operation=" .. operation_id)

	local token
	local handle = {}
	function handle:cancel()
		return type(token) == "string" and easybar.cancel_async(token) or false
	end
	operation.handle = handle
	local command_options = {}
	for key, value in pairs(options or {}) do
		command_options[key] = value
	end
	command_options.log_operation = operation_id
	token = easybar.spawn_async(arguments, command_options, function(output, code)
		local cancelled = operation.cancellation_requested
		complete_operation(operation, function()
			if cancelled then
				log(easybar.level.info, "inbox mutation cancelled operation=" .. operation_id)
				refresh("post_mutation", item_id)
				return
			end
			if code ~= 0 then
				state.error = {
					title = label .. " failed",
					message = inbox.error_message(output, "Command exited with code " .. tostring(code)),
					timestamp = os.time(),
				}
				log(easybar.level.error, "inbox mutation failed operation=" .. operation_id .. " status=" .. tostring(code))
				publish()
				return
			end
			log(easybar.level.info, "inbox mutation completed operation=" .. operation_id)
			refresh("post_mutation", item_id)
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
		local operation = state.operation
		if
			operation ~= nil
			and operation.handle ~= nil
			and operation.can_cancel
			and not operation.cancellation_requested
		then
			log(easybar.level.info, "inbox cancellation requested operation=" .. operation.id)
			if operation.kind == "refresh" then
				if operation.handle:cancel() then
					operation.handle = nil
					operation.can_cancel = false
					operation.cancellation_requested = true
					operation.title = "Cancelling Homebrew refresh…"
					publish()
					easybar.after(MIN_ACTIVITY_COMPLETION_DELAY_SECONDS, function()
						if state.operation == operation then
							state.operation = nil
							log(easybar.level.info, "inbox refresh cancelled operation=refresh")
							publish()
						end
					end)
				end
			else
				if operation.handle:cancel() then
					operation.cancellation_requested = true
					operation.title = "Cancelling Homebrew operation…"
					publish()
				end
			end
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
