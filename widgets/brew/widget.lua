-- Homebrew outdated widget for EasyBar.
--
-- Icon-only widget for the bar, with a popup that shows outdated packages and
-- actions for updating Homebrew and upgrading packages.

local brew_policy = require("brew.policy")
local text = require("text")

---@alias BrewPackageKind "formula"|"cask"
---@alias BrewOperationKind "update"|"upgrade"
---@alias BrewPhase "checking"|"updating"|"upgrading"|"cancelling"|"ready"|"error"
---@alias BrewCommandCallback fun(output:string, code:EasyBarCommandExitCode)

---@class BrewPackage
---@field kind BrewPackageKind
---@field name string
---@field installed string
---@field current string
---@field pinned boolean
---@field upgradeable boolean
---@field upgrade_reason? string

---@class BrewDiagnostic
---@field title? string
---@field source string
---@field summary string
---@field raw string

---@class BrewPopupRowOptions
---@field order? integer
---@field color? string
---@field size? number
---@field popup? table

---@class BrewWidgetState
---@field formulae BrewPackage[]
---@field casks BrewPackage[]
---@field error? BrewDiagnostic
---@field warning? BrewDiagnostic
---@field status string
---@field last_attempted_at? integer
---@field last_checked? string
---@field phase BrewPhase

local WIDGET_ID = "brew_outdated"

local ID_TITLE = WIDGET_ID .. "_title"
local ID_SUMMARY = WIDGET_ID .. "_summary"
local ID_TIME = WIDGET_ID .. "_time"
local ID_ACTIONS = WIDGET_ID .. "_actions"
local ID_UPGRADE = WIDGET_ID .. "_upgrade"
local ID_UPDATE = WIDGET_ID .. "_update"

local CHECK_INTERVAL_SECONDS = 30 * 60
local MAX_POPUP_ITEMS = 30
local MAX_WARNING_LINES = 4
local MAX_ERROR_DETAIL_LINES = 80
local BREW_LOG_FILE_NAME = "brew-widget.log"
local BREW_LOG_MAX_LINES = 4000

local EXEC = {
	check = {
		timeout_seconds = 30,
		max_output_bytes = 1024 * 1024,
	},
	update = {
		timeout_seconds = 5 * 60,
		max_output_bytes = 2 * 1024 * 1024,
	},
	upgrade = {
		timeout_seconds = 30 * 60,
		max_output_bytes = 4 * 1024 * 1024,
	},
}

local POPUP_ORDER = {
	title = 10,
	summary = 20,
	time = 30,
	actions = 40,
	dynamic_start = 100,
}

local ICONS = {
	checking = "󰑐",
	updating = "󰚰",
	upgrading = "󰏖",
	up_to_date = "󰄬",
	outdated = "󰚭",
	error = "󰅚",
}

local COLORS = {
	info = easybar.theme.ref.accent_secondary,
	ok = easybar.theme.ref.success,
	warn = easybar.theme.ref.warning,
	orange = easybar.theme.ref.orange,
	error = easybar.theme.ref.error,
	muted = easybar.theme.ref.muted,
	text = easybar.theme.ref.text,
	popup_bg = easybar.theme.ref.background,
	button_bg = easybar.theme.ref.surface,
	button_border = easybar.theme.ref.border_strong,
}

local THRESHOLDS = {
	{ count = 10, color = COLORS.error },
	{ count = 5, color = COLORS.orange },
	{ count = 3, color = COLORS.warn },
}

local running = false
local dynamic_rows = {}
local active_command_token = nil
local active_operation_kind = nil
local cancellation_requested = false
local last_command_output = ""

local brew_widget
local title_item
local summary_item
local time_item
local actions_row
local upgrade_button
local update_button

local render
local add_popup_row
local finish_cancelled_operation
local make_error

---@type BrewWidgetState
local state = {
	formulae = {},
	casks = {},
	error = nil,
	warning = nil,
	status = "Checking outdated packages…",
	last_attempted_at = nil,
	last_checked = nil,
	phase = "checking",
}

local log = easybar.log.with_file(BREW_LOG_FILE_NAME, {
	prefix = "[brew_outdated]",
})

--- Returns the current time as HH:MM.
---@return string
local function now_label()
	return tostring(os.date("%H:%M"))
end

--- Returns a timestamp suitable for log section markers.
---@return string
local function log_timestamp()
	return tostring(os.date("%Y-%m-%dT%H:%M:%S%z"))
end

--- Appends a structured operation marker to the brew widget log.
---@param kind string
---@param status string
local function append_log_marker(kind, status)
	log.append("=== " .. log_timestamp() .. " brew-widget " .. kind .. " " .. status .. " ===")
end

--- Appends command output to the brew widget log when there is output.
---@param output unknown
local function append_log_output(output)
	output = tostring(output or "")
	if output ~= "" then
		log.append(output)
	end
end

--- Keeps the brew widget log bounded to the newest lines.
local function prune_brew_log()
	local ok, err = log.trim(BREW_LOG_MAX_LINES)
	if not ok then
		log(easybar.level.warn, "failed to trim brew log", tostring(err))
	end
end

--- Returns whether EasyBar may upgrade one package automatically.
---@param package BrewPackage
---@return boolean
local function package_is_upgradeable(package)
	return not package.pinned and package.upgradeable ~= false
end

--- Returns the currently upgradeable package names for one kind.
---@param kind BrewPackageKind
---@return string[]
local function upgradeable_package_names(kind)
	local source = kind == "formula" and state.formulae or state.casks
	local names = {}

	for _, package in ipairs(source) do
		if package_is_upgradeable(package) then
			names[#names + 1] = package.name
		else
			log.append(
				"skip non-upgradeable "
					.. kind
					.. ": "
					.. package.name
					.. (package.upgrade_reason ~= nil and " (" .. package.upgrade_reason .. ")" or "")
			)
		end
	end

	table.sort(names)
	return names
end

--- Builds a direct argument vector for explicit package upgrades.
---@param kind BrewPackageKind
---@param names string[]
---@return string[]
local function package_upgrade_arguments(kind, names)
	local arguments = {
		"/usr/bin/env",
		"HOMEBREW_NO_AUTO_UPDATE=1",
		"HOMEBREW_NO_ASK=1",
		"brew",
		"upgrade",
		"--" .. kind,
		"--yes",
	}

	for _, name in ipairs(names) do
		arguments[#arguments + 1] = name
	end

	return arguments
end

--- Returns a readable command label for widget logs.
---@param arguments string[]
---@return string
local function command_label(arguments)
	local values = {}
	for index, argument in ipairs(arguments) do
		values[index] = tostring(argument)
	end
	return table.concat(values, " ")
end

--- Fails the current brew operation while keeping diagnostics out of the main popup.
---@param kind BrewOperationKind
---@param message string|BrewDiagnostic
local function fail_brew_operation(kind, message)
	if type(message) == "table" then
		state.error = message
	else
		local title = kind == "upgrade" and "Homebrew upgrade failed" or "Homebrew update failed"
		state.error = make_error(title, message, last_command_output)
	end

	state.phase = "error"
	running = false
	active_operation_kind = nil

	append_log_marker(kind, "failed")
	prune_brew_log()
	render()
end

--- Runs one direct command, logs its output and exit code, then invokes the callback.
---@param arguments string[]
---@param options EasyBarCommandOptions
---@param exit_label string
---@param callback BrewCommandCallback
local function run_logged_command(arguments, options, exit_label, callback)
	log.append("$ " .. command_label(arguments))

	local token
	token = easybar.spawn_async(arguments, options, function(output, code)
		if active_command_token == token then
			active_command_token = nil
		end

		output = tostring(output or "")
		code = code or 0
		last_command_output = output

		append_log_output(output)
		log.append(exit_label .. " exit " .. tostring(code))

		if cancellation_requested then
			finish_cancelled_operation()
			return
		end

		callback(output, code)
	end)

	active_command_token = token
end

--- Runs `brew update`.
---@param callback BrewCommandCallback
local function run_brew_update(callback)
	run_logged_command({ "brew", "update" }, EXEC.update, "brew update", callback)
end

--- Runs `brew outdated --json=v2`.
---@param callback BrewCommandCallback
local function run_outdated_json(callback)
	run_logged_command({
		"/usr/bin/env",
		"HOMEBREW_NO_AUTO_UPDATE=1",
		"brew",
		"outdated",
		"--json=v2",
	}, EXEC.check, "brew outdated", callback)
end

--- Runs explicit upgrades for one package kind, or skips when none qualify.
---@param kind BrewPackageKind
---@param callback BrewCommandCallback
local function run_package_upgrade(kind, callback)
	local names = upgradeable_package_names(kind)
	if #names == 0 then
		log.append("no upgradeable " .. kind .. " packages")
		callback("", 0)
		return
	end

	run_logged_command(package_upgrade_arguments(kind, names), EXEC.upgrade, "brew upgrade --" .. kind, callback)
end

--- Returns whether the widget should run another Homebrew update now.
---@return boolean
local function check_due()
	if state.last_attempted_at == nil then
		return true
	end

	return (os.time() - state.last_attempted_at) >= CHECK_INTERVAL_SECONDS
end

--- Returns the next scheduled check time as HH:MM or `now` when overdue.
---@return string
local function next_check_label()
	if check_due() then
		return "now"
	end

	return tostring(os.date("%H:%M", state.last_attempted_at + CHECK_INTERVAL_SECONDS))
end

--- Returns the threshold color for the outdated package count.
---@param count unknown
---@return string
local function threshold_color(count)
	count = tonumber(count) or 0

	for _, threshold in ipairs(THRESHOLDS) do
		if count >= threshold.count then
			return threshold.color
		end
	end

	return COLORS.ok
end

--- Parses Homebrew JSON package entries into normalized rows.
---@param entries table[]?
---@param kind BrewPackageKind
---@return BrewPackage[]
local function parse_package_list(entries, kind)
	local packages = {}

	for _, entry in ipairs(entries or {}) do
		local installed_versions = entry.installed_versions or {}
		local installed = "?"

		if #installed_versions > 0 then
			installed = table.concat(installed_versions, ", ")
		elseif type(entry.installed_version) == "string" and entry.installed_version ~= "" then
			installed = entry.installed_version
		end

		local name = entry.name or entry.token or entry.full_token or "unknown"
		local upgradeable = brew_policy.is_upgradeable(kind, name)

		packages[#packages + 1] = {
			kind = kind,
			name = name,
			installed = installed,
			current = entry.current_version or "?",
			pinned = entry.pinned == true,
			upgradeable = upgradeable,
			upgrade_reason = upgradeable and nil or brew_policy.reason(kind, name),
		}
	end

	return packages
end

--- Separates Homebrew's JSON payload from warnings written around it.
---@param raw unknown
---@return string json
---@return string warning
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
		error("brew output did not contain a JSON object")
	end

	local json = raw:sub(json_start, json_end)
	local warning = text.trim(raw:sub(1, json_start - 1) .. "\n" .. raw:sub(json_end + 1))

	return json, warning
end

--- Returns a readable package and tap label from a Homebrew warning source path.
---@param raw unknown
---@return string
local function warning_source(raw)
	local owner, tap, token = tostring(raw or ""):match("/Taps/([^/]+)/homebrew%-([^/]+)/Casks/([^/]+)%.rb:%d+")

	if owner == nil then
		owner, tap, token = tostring(raw or ""):match("/Taps/([^/]+)/homebrew%-([^/]+)/Formula/([^/]+)%.rb:%d+")
	end

	if token == nil then
		return "Homebrew"
	end

	local package_name = token == "easybar" and "EasyBar" or token
	return package_name .. " · " .. owner .. "/" .. tap
end

--- Builds a concise error plus diagnostic details shown only on hover.
---@param title string
---@param summary unknown
---@param raw unknown
---@return BrewDiagnostic
make_error = function(title, summary, raw)
	raw = text.trim(raw)
	return {
		title = title,
		source = warning_source(raw),
		summary = text.trim(summary),
		raw = raw ~= "" and raw or text.trim(summary),
	}
end

--- Builds warning details while retaining both readable and complete forms.
---@param raw unknown
---@return BrewDiagnostic?
local function parse_warning(raw)
	local lines = {}
	raw = text.trim(raw)

	for line in raw:gmatch("[^\r\n]+") do
		local value = text.trim(line)
		local is_report_instruction = value:match("^Please report this issue") ~= nil
		local is_source_path = value:match("^/.+/Casks/.+:%d+$") ~= nil

		if value ~= "" and not is_report_instruction and not is_source_path then
			lines[#lines + 1] = value
		end
	end

	if #lines == 0 then
		return nil
	end

	return {
		source = warning_source(raw),
		summary = table.concat(lines, "\n"),
		raw = raw,
	}
end

--- Stores parsed Homebrew outdated JSON in widget state.
---@param raw string
local function apply_outdated_json(raw)
	local json, warning = split_outdated_output(raw)
	local parsed = easybar.json.decode(json)
	if type(parsed) ~= "table" then
		error("decoded brew output is not a table")
	end

	state.formulae = parse_package_list(parsed.formulae, "formula")
	state.casks = parse_package_list(parsed.casks, "cask")
	state.error = nil
	state.warning = parse_warning(warning)
	state.last_checked = now_label()
	state.phase = "ready"

	log(
		easybar.level.debug,
		"apply_outdated_json",
		"formulae=" .. tostring(#state.formulae),
		"casks=" .. tostring(#state.casks)
	)
end

--- Renders a compact warning section and returns the next popup order.
---@param order integer
---@return integer
local function render_warning(order)
	if state.warning == nil then
		return order
	end

	local warning_row = add_popup_row(WIDGET_ID .. "_warning", "⚠ " .. state.warning.source, {
		order = order,
		color = COLORS.warn,
		popup = {
			drawing = false,
			background = {
				color = COLORS.popup_bg,
				border_color = COLORS.button_border,
				border_width = 1,
				corner_radius = 8,
			},
			padding_x = 10,
			padding_y = 8,
			spacing = 4,
		},
	})
	order = order + 1
	local warning_triggers = { warning_row }

	local rendered = 0
	for line in state.warning.summary:gmatch("[^\r\n]+") do
		if rendered >= MAX_WARNING_LINES then
			local more_row =
				add_popup_row(WIDGET_ID .. "_warning_more", "  … See " .. BREW_LOG_FILE_NAME .. " for details", {
					order = order,
					color = COLORS.muted,
				})
			warning_triggers[#warning_triggers + 1] = more_row
			order = order + 1
			break
		end

		local summary_row =
			add_popup_row(WIDGET_ID .. "_warning_summary_" .. tostring(rendered), "  " .. text.truncate(line, 110, "…"), {
				order = order,
				color = COLORS.warn,
				size = 11,
			})
		warning_triggers[#warning_triggers + 1] = summary_row
		order = order + 1
		rendered = rendered + 1
	end

	local detail_index = 0
	for line in state.warning.raw:gmatch("[^\r\n]+") do
		local detail = easybar.add(easybar.kind.item, WIDGET_ID .. "_warning_detail_" .. tostring(detail_index), {
			position = "popup." .. warning_row.name,
			order = detail_index,
			label = {
				string = line,
				color = COLORS.text,
				font = {
					size = 11,
				},
			},
		})
		dynamic_rows[#dynamic_rows + 1] = detail
		detail_index = detail_index + 1
	end

	for _, trigger in ipairs(warning_triggers) do
		trigger:subscribe(easybar.events.mouse.entered, function()
			warning_row:set({ popup = { drawing = true } })
		end)

		trigger:subscribe(easybar.events.mouse.exited, function()
			warning_row:set({ popup = { drawing = false } })
		end)
	end

	return order
end

--- Applies Homebrew JSON output to state and returns whether parsing succeeded.
---@param output string
---@return boolean
local function apply_outdated_result(output)
	local ok, err = pcall(apply_outdated_json, output)
	if not ok then
		local reason = tostring(err):gsub("^.-:%d+:%s*", "")
		state.error = make_error(
			"Could not process Homebrew response",
			"The outdated package response was not valid: " .. reason,
			output
		)
		state.phase = "error"
		return false
	end

	return true
end

--- Renders a concise error with complete command details in a hover popup.
---@param order integer
---@return integer
local function render_error(order)
	if state.error == nil then
		return order
	end

	local error_row = add_popup_row(WIDGET_ID .. "_error", "✕ " .. state.error.source, {
		order = order,
		color = COLORS.error,
		popup = {
			drawing = false,
			background = {
				color = COLORS.popup_bg,
				border_color = COLORS.button_border,
				border_width = 1,
				corner_radius = 8,
			},
			padding_x = 10,
			padding_y = 8,
			spacing = 4,
		},
	})
	order = order + 1

	local summary_row =
		add_popup_row(WIDGET_ID .. "_error_summary", "  " .. text.truncate(state.error.summary, 110, "…"), {
			order = order,
			color = COLORS.error,
			size = 11,
		})
	order = order + 1

	local detail_index = 0
	for line in state.error.raw:gmatch("[^\r\n]+") do
		if detail_index >= MAX_ERROR_DETAIL_LINES then
			local detail = easybar.add(easybar.kind.item, WIDGET_ID .. "_error_detail_more", {
				position = "popup." .. error_row.name,
				order = detail_index,
				label = {
					string = "… See " .. BREW_LOG_FILE_NAME .. " for complete output",
					color = COLORS.muted,
					font = { size = 11 },
				},
			})
			dynamic_rows[#dynamic_rows + 1] = detail
			break
		end

		local detail = easybar.add(easybar.kind.item, WIDGET_ID .. "_error_detail_" .. tostring(detail_index), {
			position = "popup." .. error_row.name,
			order = detail_index,
			label = {
				string = line,
				color = COLORS.text,
				font = { size = 11 },
			},
		})
		dynamic_rows[#dynamic_rows + 1] = detail
		detail_index = detail_index + 1
	end

	for _, trigger in ipairs({ error_row, summary_row }) do
		trigger:subscribe(easybar.events.mouse.entered, function()
			error_row:set({ popup = { drawing = true } })
		end)
		trigger:subscribe(easybar.events.mouse.exited, function()
			error_row:set({ popup = { drawing = false } })
		end)
	end

	return order
end

--- Returns all currently outdated packages.
---@return BrewPackage[]
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

--- Returns the number of outdated packages.
---@return integer
local function count_packages()
	return #state.formulae + #state.casks
end

--- Returns the number of packages EasyBar may upgrade.
---@return integer
local function count_upgradeable_packages()
	local count = 0
	for _, package in ipairs(all_packages()) do
		if package_is_upgradeable(package) then
			count = count + 1
		end
	end
	return count
end

--- Returns the number of packages that require a manual update.
---@return integer
local function count_manual_packages()
	local count = 0
	for _, package in ipairs(all_packages()) do
		if not package.pinned and package.upgradeable == false then
			count = count + 1
		end
	end
	return count
end

--- Returns the number of pinned packages.
---@return integer
local function count_pinned_packages()
	local count = 0
	for _, package in ipairs(all_packages()) do
		if package.pinned then
			count = count + 1
		end
	end
	return count
end

--- Removes all dynamically created popup rows.
local function remove_dynamic_rows()
	for _, row in ipairs(dynamic_rows) do
		if row ~= nil then
			row:remove()
		end
	end

	dynamic_rows = {}
end

--- Adds a popup text row and tracks it for later cleanup.
---@param id string
---@param row_text string
---@param opts? BrewPopupRowOptions
---@return EasyBarNodeHandle
add_popup_row = function(id, row_text, opts)
	opts = opts or {}

	local props = {
		position = "popup." .. WIDGET_ID,
		order = opts.order,
		label = {
			string = row_text,
			color = opts.color or COLORS.text,
			font = {
				size = opts.size or 12,
			},
		},
	}

	if opts.popup ~= nil then
		props.popup = opts.popup
	end

	local row = easybar.add(easybar.kind.item, id, props)
	dynamic_rows[#dynamic_rows + 1] = row

	return row
end

--- Renders a package section in the popup.
---@param title string
---@param packages BrewPackage[]
---@param row_prefix string
---@param order integer
---@param remaining_rows integer
---@return integer next_order
---@return integer rendered_count
local function render_list_section(title, packages, row_prefix, order, remaining_rows)
	if #packages == 0 or remaining_rows <= 0 then
		return order, 0
	end

	add_popup_row(row_prefix .. "_heading", title, {
		order = order,
		size = 12,
		color = COLORS.muted,
	})

	order = order + 1

	local rendered_count = 0

	for _, package in ipairs(packages) do
		if rendered_count >= remaining_rows then
			return order, rendered_count
		end

		local status = ""
		local row_color = COLORS.text
		if package.pinned then
			status = "  · pinned"
			row_color = COLORS.warn
		elseif package.upgradeable == false then
			status = "  · manual"
			if package.upgrade_reason ~= nil then
				status = status .. " — " .. text.truncate(package.upgrade_reason, 54, "…")
			end
			row_color = COLORS.warn
		end

		local row_text = string.format(
			"  • %s  %s → %s%s",
			text.truncate(package.name, 28, "…"),
			text.truncate(package.installed, 18, "…"),
			text.truncate(package.current, 18, "…"),
			status
		)

		add_popup_row(row_prefix .. "_" .. tostring(order), row_text, {
			order = order,
			color = row_color,
		})

		order = order + 1
		rendered_count = rendered_count + 1
	end

	return order, rendered_count
end

--- Returns the bar icon and color for the current widget state.
---@return string icon
---@return string color
local function current_bar_visual()
	local total = count_packages()

	if running then
		if state.phase == "updating" then
			return ICONS.updating, COLORS.info
		end

		if state.phase == "upgrading" then
			return ICONS.upgrading, COLORS.orange
		end

		return ICONS.checking, COLORS.warn
	end

	if state.error ~= nil or state.phase == "error" then
		return ICONS.error, COLORS.error
	end

	if total == 0 then
		return ICONS.up_to_date, COLORS.ok
	end

	return ICONS.outdated, threshold_color(total)
end

--- Returns labels for action buttons based on the current phase.
---@return string upgrade_label
---@return string update_label
local function action_button_labels()
	if running and (state.phase == "updating" or state.phase == "upgrading" or state.phase == "cancelling") then
		return "", state.phase == "cancelling" and "Cancelling…" or "Cancel"
	end

	if not running then
		local upgradeable = count_upgradeable_packages()
		return upgradeable > 0 and "Upgrade " .. tostring(upgradeable) or "No automatic upgrades", "Update"
	end

	if state.phase == "checking" then
		return "Working…", "Checking…"
	end

	return "Working…", "Working…"
end

--- Renders the popup contents.
local function render_popup()
	local total = count_packages()
	local upgradeable = count_upgradeable_packages()
	local manual = count_manual_packages()
	local pinned = count_pinned_packages()
	local count_color = threshold_color(total)

	title_item:set({
		order = POPUP_ORDER.title,
		label = {
			string = "Homebrew",
			color = COLORS.text,
		},
	})

	if running then
		summary_item:set({
			order = POPUP_ORDER.summary,
			label = {
				string = state.status,
				color = COLORS.warn,
			},
		})
	elseif state.error ~= nil then
		summary_item:set({
			order = POPUP_ORDER.summary,
			label = {
				string = state.error.title,
				color = COLORS.error,
			},
		})
	elseif total == 0 then
		summary_item:set({
			order = POPUP_ORDER.summary,
			label = {
				string = "Everything is up to date" .. (state.warning ~= nil and "  ⚠" or ""),
				color = COLORS.ok,
			},
		})
	else
		local summary = total == 1 and "1 outdated package" or tostring(total) .. " outdated packages"
		local details = {}
		if manual > 0 or pinned > 0 then
			details[#details + 1] = tostring(upgradeable) .. " automatic"
		end
		if manual > 0 then
			details[#details + 1] = tostring(manual) .. " manual"
		end
		if pinned > 0 then
			details[#details + 1] = tostring(pinned) .. " pinned"
		end
		if #details > 0 then
			summary = summary .. "  ·  " .. table.concat(details, "  ·  ")
		end
		if state.warning ~= nil then
			summary = summary .. "  ⚠"
		end

		summary_item:set({
			order = POPUP_ORDER.summary,
			label = {
				string = summary,
				color = count_color,
			},
		})
	end

	local checked = state.last_checked or "never"

	time_item:set({
		order = POPUP_ORDER.time,
		label = {
			string = "Last checked: " .. checked .. "   Next check: " .. next_check_label(),
			color = COLORS.muted,
			font = {
				size = 11,
			},
		},
	})

	actions_row:set({
		order = POPUP_ORDER.actions,
	})

	local upgrade_label, update_label = action_button_labels()

	upgrade_button:set({
		order = 1,
		drawing = not (
				running and (state.phase == "updating" or state.phase == "upgrading" or state.phase == "cancelling")
			),
		label = {
			string = upgrade_label,
			color = not running and upgradeable == 0 and COLORS.muted or COLORS.text,
		},
	})

	update_button:set({
		order = 2,
		label = {
			string = update_label,
			color = COLORS.text,
		},
	})

	remove_dynamic_rows()

	if state.error ~= nil then
		render_error(POPUP_ORDER.dynamic_start)
		return
	end

	if running and total == 0 then
		add_popup_row(WIDGET_ID .. "_running_hint", "Waiting for Homebrew…", {
			order = POPUP_ORDER.dynamic_start,
			color = COLORS.muted,
		})

		return
	end

	if total == 0 then
		render_warning(POPUP_ORDER.dynamic_start)
		return
	end

	local available_rows = MAX_POPUP_ITEMS
	local order = POPUP_ORDER.dynamic_start
	local rendered_packages = 0

	local rendered_formulae
	order, rendered_formulae =
		render_list_section("Formulae", state.formulae, WIDGET_ID .. "_formula", order, available_rows)

	rendered_packages = rendered_packages + rendered_formulae
	available_rows = available_rows - rendered_formulae

	local rendered_casks
	order, rendered_casks = render_list_section("Casks", state.casks, WIDGET_ID .. "_cask", order, available_rows)

	rendered_packages = rendered_packages + rendered_casks

	local hidden = total - rendered_packages
	if hidden > 0 then
		add_popup_row(WIDGET_ID .. "_hidden", "  … " .. tostring(hidden) .. " more", {
			order = order,
			color = COLORS.muted,
		})
		order = order + 1
	end

	render_warning(order)
end

--- Renders the bar widget as a compact icon-only item.
local function render_bar()
	local icon, color = current_bar_visual()

	brew_widget:set({
		icon = {
			string = icon,
			color = color,
		},
		label = {
			string = "",
		},
	})
end

--- Renders both the bar widget and popup.
render = function()
	render_bar()
	render_popup()
end

--- Starts a brew operation and updates shared widget state.
---@param phase BrewPhase
---@param status string
local function start_operation(phase, status)
	running = true
	state.status = status
	state.error = nil
	state.last_attempted_at = os.time()
	state.phase = phase
	cancellation_requested = false

	render()
end

--- Returns to the previous package state after an update or upgrade was cancelled.
finish_cancelled_operation = function()
	local kind = active_operation_kind or "operation"
	cancellation_requested = false
	active_operation_kind = nil
	append_log_marker(kind, "cancelled")
	prune_brew_log()

	running = false
	state.phase = "ready"
	state.status = (kind == "upgrade" and "Upgrade" or "Update") .. " cancelled."
	render()
end

--- Cancels the active update or upgrade command and its process group.
local function cancel_operation()
	if not running or (state.phase ~= "updating" and state.phase ~= "upgrading") then
		return
	end

	cancellation_requested = true
	state.phase = "cancelling"
	state.status = "Cancelling Homebrew operation…"
	append_log_marker(active_operation_kind or "operation", "cancel-requested")
	render()

	if active_command_token == nil or not easybar.cancel_async(active_command_token) then
		finish_cancelled_operation()
	end
end

--- Checks outdated packages without updating Homebrew.
---@param status_label? string
local function check_outdated(status_label)
	if running then
		log(easybar.level.debug, "check_outdated skipped", "status=" .. tostring(status_label))
		return
	end

	start_operation("checking", status_label or "Checking outdated packages…")

	run_outdated_json(function(output, code)
		running = false

		if code ~= 0 then
			state.error = make_error(
				"Could not check outdated packages",
				"brew outdated failed with exit code " .. tostring(code),
				output
			)
			state.phase = "error"
			render()
			return
		end

		apply_outdated_result(output)
		render()
	end)
end

--- Completes a successful brew operation.
---@param kind BrewOperationKind
local function finish_brew_operation(kind)
	running = false
	active_operation_kind = nil
	append_log_marker(kind, "ok")
	prune_brew_log()
	render()
end

--- Handles the final outdated-package check for update or upgrade flows.
---@param kind BrewOperationKind
---@param output string
---@param code EasyBarCommandExitCode
local function finish_with_outdated_result(kind, output, code)
	if code ~= 0 then
		fail_brew_operation(kind, "brew outdated failed with exit code " .. tostring(code))
		return
	end

	if not apply_outdated_result(output) then
		fail_brew_operation(kind, state.error or "brew outdated returned invalid JSON")
		return
	end

	finish_brew_operation(kind)
end

--- Handles the `brew update` result for the update flow.
---@param _ string
---@param update_code EasyBarCommandExitCode
local function handle_update_brew_update(_, update_code)
	if update_code ~= 0 then
		fail_brew_operation("update", "brew update failed with exit code " .. tostring(update_code))
		return
	end

	run_outdated_json(function(output, code)
		finish_with_outdated_result("update", output, code)
	end)
end

--- Updates Homebrew, then checks outdated packages.
local function update_now()
	if running then
		log(easybar.level.debug, "update_now skipped", "running=true")
		return
	end

	append_log_marker("update", "start")
	active_operation_kind = "update"
	start_operation("updating", "Updating Homebrew… writing " .. BREW_LOG_FILE_NAME)

	run_brew_update(handle_update_brew_update)
end

--- Updates Homebrew only when the widget is due.
local function update_if_due()
	if running or not check_due() then
		return
	end

	update_now()
end

local handle_upgrade_formula
local handle_upgrade_casks

--- Handles the refreshed package list before explicit upgrades begin.
---@param output string
---@param code EasyBarCommandExitCode
local function handle_upgrade_outdated(output, code)
	if code ~= 0 then
		fail_brew_operation("upgrade", "brew outdated failed with exit code " .. tostring(code))
		return
	end

	if not apply_outdated_result(output) then
		fail_brew_operation("upgrade", state.error or "brew outdated returned invalid JSON")
		return
	end

	state.phase = "upgrading"
	state.status = "Upgrading formulae…"
	render()
	run_package_upgrade("formula", handle_upgrade_formula)
end

--- Handles the `brew update` result for the upgrade flow.
---@param _ string
---@param update_code EasyBarCommandExitCode
local function handle_upgrade_brew_update(_, update_code)
	if update_code ~= 0 then
		fail_brew_operation("upgrade", "brew update failed with exit code " .. tostring(update_code))
		return
	end

	run_outdated_json(handle_upgrade_outdated)
end

--- Handles the formula upgrade result for the upgrade flow.
---@param _ string
---@param formula_code EasyBarCommandExitCode
handle_upgrade_formula = function(_, formula_code)
	if formula_code ~= 0 then
		fail_brew_operation("upgrade", "brew upgrade --formula failed with exit code " .. tostring(formula_code))
		return
	end

	state.phase = "upgrading"
	state.status = "Upgrading casks…"
	render()
	run_package_upgrade("cask", handle_upgrade_casks)
end

--- Handles the cask upgrade result for the upgrade flow.
---@param _ string
---@param cask_upgrade_code EasyBarCommandExitCode
handle_upgrade_casks = function(_, cask_upgrade_code)
	if cask_upgrade_code ~= 0 then
		fail_brew_operation("upgrade", "brew upgrade --cask failed with exit code " .. tostring(cask_upgrade_code))
		return
	end

	run_outdated_json(function(output, code)
		finish_with_outdated_result("upgrade", output, code)
	end)
end

--- Upgrades packages, then checks outdated packages.
local function upgrade_now()
	if running then
		log(easybar.level.debug, "upgrade_now skipped", "running=true")
		return
	end

	if count_upgradeable_packages() == 0 then
		log(easybar.level.debug, "upgrade_now skipped", "upgradeable=0")
		return
	end

	append_log_marker("upgrade", "start")
	active_operation_kind = "upgrade"
	start_operation("upgrading", "Updating and upgrading… writing " .. BREW_LOG_FILE_NAME)

	run_brew_update(handle_upgrade_brew_update)
end

--- Returns a fresh button background configuration.
---@return table
local function button_background()
	return {
		color = COLORS.button_bg,
		border_color = COLORS.button_border,
		border_width = 1,
		corner_radius = 6,
		padding_left = 8,
		padding_right = 8,
	}
end

easybar.default({
	label = {
		color = COLORS.text,
		font = {
			size = 12,
		},
	},
})

brew_widget = easybar.add(easybar.kind.item, WIDGET_ID, {
	position = "right",
	order = 20,
	interval = CHECK_INTERVAL_SECONDS,
	popup = {
		drawing = true,
		background = {
			color = COLORS.popup_bg,
			border_color = COLORS.button_border,
			border_width = 1,
			corner_radius = 8,
		},
		padding_x = 10,
		padding_y = 8,
		spacing = 6,
	},
	height = 24,
	icon = {
		string = ICONS.checking,
		color = COLORS.warn,
		font = {
			size = 15,
		},
		offset_x = -1,
		offset_y = 0,
	},
	label = {
		string = "",
	},
	on_interval = function()
		if not running then
			check_outdated("Checking outdated packages…")
		end
	end,
})

title_item = easybar.add(easybar.kind.item, ID_TITLE, {
	position = "popup." .. brew_widget.name,
	order = POPUP_ORDER.title,
	label = {
		string = "Homebrew",
		color = COLORS.text,
		font = {
			size = 13,
		},
	},
})

summary_item = easybar.add(easybar.kind.item, ID_SUMMARY, {
	position = "popup." .. brew_widget.name,
	order = POPUP_ORDER.summary,
	label = {
		string = "Checking outdated packages…",
		color = COLORS.text,
	},
})

time_item = easybar.add(easybar.kind.item, ID_TIME, {
	position = "popup." .. brew_widget.name,
	order = POPUP_ORDER.time,
	label = {
		string = "Last checked: never",
		color = COLORS.muted,
		font = {
			size = 11,
		},
	},
})

actions_row = easybar.add(easybar.kind.row, ID_ACTIONS, {
	position = "popup." .. brew_widget.name,
	order = POPUP_ORDER.actions,
	spacing = 8,
})

upgrade_button = easybar.add(easybar.kind.item, ID_UPGRADE, {
	parent = actions_row.name,
	order = 1,
	label = {
		string = "Upgrade now",
		color = COLORS.text,
	},
	background = button_background(),
})

update_button = easybar.add(easybar.kind.item, ID_UPDATE, {
	parent = actions_row.name,
	order = 2,
	label = {
		string = "Update",
		color = COLORS.text,
	},
	background = button_background(),
})

--- Starts the update flow when the update button is left-clicked.
update_button:subscribe(easybar.events.mouse.clicked, function(event)
	if event.button == nil or event.button == easybar.events.mouse.left_button then
		if running and (state.phase == "updating" or state.phase == "upgrading") then
			log(easybar.level.debug, "cancel click", "phase=" .. state.phase)
			cancel_operation()
		elseif not running then
			log(easybar.level.debug, "update click")
			update_now()
		end
	end
end)

--- Starts the upgrade flow when the upgrade button is left-clicked.
upgrade_button:subscribe(easybar.events.mouse.clicked, function(event)
	if
		(event.button == nil or event.button == easybar.events.mouse.left_button)
		and not running
		and count_upgradeable_packages() > 0
	then
		log(easybar.level.debug, "upgrade click")
		upgrade_now()
	end
end)

--- Runs a due update check after relevant system lifecycle events.
brew_widget:subscribe({
	easybar.events.system_woke,
	easybar.events.session_active,
}, function(event)
	log(easybar.level.debug, "lifecycle event", tostring(event and event.name), "due=" .. tostring(check_due()))
	update_if_due()
end)

--- Forces an immediate outdated-package check when EasyBar triggers the widget.
brew_widget:subscribe(easybar.events.forced, function()
	if not running then
		check_outdated("Checking outdated packages…")
	end
end)

check_outdated("Checking outdated packages…")
