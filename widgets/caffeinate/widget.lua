-- Keeps the Mac awake until disabled or for a selected duration.
--
-- Left-click toggles an indefinite session. Right-click offers timed sessions
-- and a stop action. Indefinite sessions renew before EasyBar's 24-hour
-- command timeout limit.

local UPDATE_INTERVAL_SECONDS = 30
local RENEWAL_DURATION_SECONDS = 23 * 60 * 60
local COMMAND_TIMEOUT_GRACE_SECONDS = 10
local MAX_DURATION_MINUTES = 1439

local PRESETS = {
	{ minutes = 15, title = "15 Minutes" },
	{ minutes = 30, title = "30 Minutes" },
	{ minutes = 60, title = "1 Hour" },
	{ minutes = 120, title = "2 Hours" },
	{ minutes = 240, title = "4 Hours" },
}

local COLORS = {
	text = easybar.theme.ref.text,
	muted = easybar.theme.ref.muted,
	success = easybar.theme.ref.success,
	warning = easybar.theme.ref.warning,
	popup_bg = easybar.theme.ref.background,
	border = easybar.theme.ref.border_strong,
}

local widget
local popup_label
local active_job
local active_mode
local active_duration_minutes
local expires_at
local generation = 0
local stopping = false

local start

local function is_active()
	return active_job ~= nil
end

local function is_selected(mode, duration_minutes)
	if not is_active() or active_mode ~= mode then
		return false
	end
	return mode ~= "timed" or active_duration_minutes == duration_minutes
end

local function remaining_text()
	if expires_at == nil then
		return nil
	end

	local minutes = math.max(1, math.ceil((expires_at - os.time()) / 60))
	local hours = minutes // 60
	local remainder = minutes % 60

	if hours > 0 and remainder > 0 then
		return tostring(hours) .. "h " .. tostring(remainder) .. "m"
	end
	if hours > 0 then
		return tostring(hours) .. "h"
	end
	return tostring(minutes) .. "m"
end

local function status_text()
	if stopping then
		return "Caffeinate · Stopping…"
	end
	if not is_active() then
		return "Caffeinate · Off"
	end

	local remaining = remaining_text()
	return remaining ~= nil and ("Caffeinate · Awake for " .. remaining) or "Caffeinate · Awake until turned off"
end

local function context_menu()
	local active = is_active()
	local durations = {}

	for _, preset in ipairs(PRESETS) do
		table.insert(durations, {
			id = "start:" .. tostring(preset.minutes),
			title = preset.title,
			checked = is_selected("timed", preset.minutes),
			enabled = not active and not stopping,
		})
	end

	local menu = {
		{
			id = "start:indefinite",
			title = "Until Turned Off",
			checked = is_selected("indefinite"),
			enabled = not active and not stopping,
		},
		{
			title = "For a Duration",
			submenu = durations,
		},
	}

	if active or stopping then
		table.insert(menu, { separator = true })
		table.insert(menu, {
			id = "stop",
			title = stopping and "Stopping…" or "Stop Caffeinate",
			enabled = not stopping,
		})
	end

	return menu
end

local function render()
	local color = COLORS.muted
	if stopping then
		color = COLORS.warning
	elseif is_active() then
		color = COLORS.success
	end

	widget:set({
		icon = {
			string = "☕︎",
			color = color,
			font = {
				size = 20,
			},
			padding_right = 0,
			offset_y = -1,
		},
		label = {
			string = "",
		},
		context_menu = context_menu(),
	})

	popup_label:set({
		label = {
			string = status_text(),
			color = stopping and COLORS.warning or (is_active() and COLORS.text or COLORS.muted),
		},
	})
end

local function clear_session()
	active_job = nil
	active_mode = nil
	active_duration_minutes = nil
	expires_at = nil
	stopping = false
end

local function finish(session_generation, output, code)
	if session_generation ~= generation then
		return
	end

	local mode = active_mode
	local was_stopping = stopping
	clear_session()

	if mode == "indefinite" and not was_stopping and (code == 0 or code == 124) then
		render()
		easybar.after(0.1, function()
			if not is_active() then
				start("indefinite")
			end
		end)
		return
	end

	if code ~= 0 and code ~= 130 and not was_stopping then
		easybar.log(
			easybar.level.warn,
			"caffeinate exited unexpectedly",
			"code=" .. tostring(code),
			output ~= "" and output or "<empty>"
		)
	end

	render()
end

start = function(mode, duration_minutes)
	if is_active() or stopping then
		return
	end

	local duration_seconds
	if mode == "timed" then
		duration_minutes = tonumber(duration_minutes)
		if duration_minutes == nil then
			return
		end

		duration_minutes = math.floor(duration_minutes)
		if duration_minutes < 1 or duration_minutes > 1439 then
			return
		end
		duration_seconds = duration_minutes * 60
	elseif mode == "indefinite" then
		duration_minutes = nil
		duration_seconds = RENEWAL_DURATION_SECONDS
	else
		return
	end

	generation = generation + 1
	local session_generation = generation
	active_mode = mode
	active_duration_minutes = duration_minutes
	expires_at = mode == "timed" and (os.time() + duration_seconds) or nil

	active_job = easybar.spawn_async({
		"/usr/bin/caffeinate",
		"-di",
		"-t",
		tostring(duration_seconds),
	}, {
		timeout_seconds = duration_seconds + COMMAND_TIMEOUT_GRACE_SECONDS,
		max_output_bytes = 1024,
		log_operation = "caffeinate",
	}, function(output, code)
		finish(session_generation, output or "", code or 0)
	end)

	easybar.log(
		easybar.level.info,
		"caffeinate started",
		mode == "timed" and ("duration_minutes=" .. tostring(duration_minutes)) or "duration=until_stopped"
	)

	render()
end

local function stop()
	if not is_active() or stopping then
		return
	end

	stopping = true
	if not easybar.cancel_async(active_job) then
		generation = generation + 1
		clear_session()
	end
	render()
end

local function toggle()
	if is_active() then
		stop()
	else
		local configured = easybar.storage.get("caffeinate", "duration_minutes")
		if configured == nil then
			start("indefinite")
			return
		end

		if
			type(configured) ~= "number"
			or configured ~= configured
			or configured % 1 ~= 0
			or configured < 1
			or configured > MAX_DURATION_MINUTES
		then
			easybar.log(
				easybar.level.warn,
				"invalid caffeinate duration_minutes; using indefinite mode",
				"value=" .. tostring(configured)
			)
			start("indefinite")
			return
		end

		start("timed", configured)
	end
end

widget = easybar.add(easybar.kind.item, "caffeinate", {
	position = "right",
	order = 70,
	interval = UPDATE_INTERVAL_SECONDS,
	on_interval = render,
	icon = {
		string = "☕︎",
		color = COLORS.muted,
		font = {
			size = 20,
		},
		offset_y = -1,
	},
	label = {
		string = "",
		color = COLORS.text,
		font = {
			size = 11,
		},
	},
	popup = {
		drawing = "on",
		background = {
			color = COLORS.popup_bg,
			border_color = COLORS.border,
			border_width = 1,
			corner_radius = 8,
		},
		padding_x = 10,
		padding_y = 8,
	},
	context_menu = context_menu(),
})

popup_label = easybar.add(easybar.kind.item, "caffeinate_popup_label", {
	position = "popup." .. widget.name,
	label = {
		string = "Caffeinate · Off",
		color = COLORS.muted,
	},
})

widget:subscribe(easybar.events.mouse.clicked, function(event)
	if event.button == nil or event.button == easybar.events.mouse.left_button then
		toggle()
	end
end)

widget:subscribe(easybar.events.context_menu.clicked, function(event)
	if event.action_id == "stop" then
		stop()
	elseif event.action_id == "start:indefinite" then
		start("indefinite")
	else
		local minutes = type(event.action_id) == "string" and event.action_id:match("^start:(%d+)$") or nil
		if minutes ~= nil then
			start("timed", minutes)
		end
	end
end)

widget:subscribe(easybar.events.forced, render)

render()
