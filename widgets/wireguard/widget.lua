-- macOS Network Extension VPN example. The service name is read from
-- [widgets.wireguard].vpn_name in config.toml; left-click toggles that service.

local text = require("text")

local STORAGE_WIDGET = "wireguard"
local STORAGE_VPN_NAME_KEY = "vpn_name"
local DEFAULT_VPN_NAME = "WireGuard"
local VPN_ICON = "󰖂"

local configured_vpn_name = easybar.storage.get(STORAGE_WIDGET, STORAGE_VPN_NAME_KEY, DEFAULT_VPN_NAME)
local VPN_NAME = text.trim(configured_vpn_name)
if VPN_NAME == "" then
	VPN_NAME = DEFAULT_VPN_NAME
	easybar.log(easybar.level.warn, "empty widgets.wireguard.vpn_name; using default", DEFAULT_VPN_NAME)
end

local COLORS = {
	text = easybar.theme.ref.text,
	muted = easybar.theme.ref.muted,
	success = easybar.theme.ref.success,
	popup_bg = easybar.theme.ref.background,
	border = easybar.theme.ref.border_strong,
}

local COMMAND_OPTIONS = {
	timeout_seconds = 10,
	max_output_bytes = 65536,
}

local ACTION_COMMAND_OPTIONS = {
	timeout_seconds = 30,
	max_output_bytes = 65536,
}

local wireguard
local wireguard_icon
local wireguard_popup_label

local state = {
	wireguard_connected = false,
}

local toggle_running = false

local function status_label(connected)
	if connected then
		return "Active"
	end

	return "Inactive"
end

local function log_command_result(action, command, output, ok, code)
	output = text.trim(output or "")

	if ok then
		if output ~= "" then
			easybar.log(easybar.level.debug, action .. " ok", command, output)
		else
			easybar.log(easybar.level.debug, action .. " ok", command)
		end
		return
	end

	easybar.log(
		easybar.level.warn,
		action .. " failed",
		command,
		"code=" .. tostring(code),
		output ~= "" and output or "<empty>"
	)
end

local function command_label(arguments)
	local values = {}
	for index, argument in ipairs(arguments) do
		values[index] = tostring(argument)
	end
	return table.concat(values, " ")
end

local function run_command(arguments, options, callback)
	easybar.spawn_async(arguments, options or COMMAND_OPTIONS, function(output, code)
		output = text.trim(output or "")
		code = code or 0
		callback(output, code == 0, code)
	end)
end

local function current_status_async(vpn_name, callback)
	local arguments = { "scutil", "--nc", "status", vpn_name }

	run_command(arguments, COMMAND_OPTIONS, function(output, ok, code)
		if not ok then
			log_command_result("wireguard status", command_label(arguments), output, false, code)
			callback(nil, code)
			return
		end

		callback((output or ""):lower(), nil)
	end)
end

local function apply_network_event(event)
	if event == nil or event.network == nil then
		return
	end

	local value = event.network.primary_interface_is_tunnel
	if value ~= nil then
		local connected = value == true
		if state.wireguard_connected ~= connected then
			state.wireguard_connected = connected
			easybar.log(easybar.level.debug, "wireguard tunnel state changed", connected and "active" or "inactive")
		else
			state.wireguard_connected = connected
		end
	end
end

local function refresh()
	local wireguard_connected = state.wireguard_connected
	local icon_color = wireguard_connected and COLORS.success or COLORS.muted

	wireguard_icon:set({
		icon = {
			string = VPN_ICON,
			color = icon_color,
		},
		label = {
			string = "",
		},
		opacity = wireguard_connected and 1.0 or 0.55,
	})

	wireguard_popup_label:set({
		label = {
			string = VPN_NAME .. " · " .. (toggle_running and "Working…" or status_label(wireguard_connected)),
			color = toggle_running and COLORS.text or icon_color,
		},
	})
end

local function finish_toggle()
	toggle_running = false
	refresh()
end

local function toggle_wireguard()
	if toggle_running then
		easybar.log(easybar.level.debug, "wireguard toggle skipped", "already running")
		return
	end

	toggle_running = true
	refresh()

	current_status_async(VPN_NAME, function(status, err)
		if err ~= nil or status == nil then
			easybar.log(easybar.level.warn, "failed to read wireguard status", VPN_NAME)
			finish_toggle()
			return
		end

		easybar.log(easybar.level.debug, "wireguard status", VPN_NAME, status)

		local arguments
		local action

		if status:match("^connected") or status:match("^connecting") or status:match("^on demand") then
			arguments = { "scutil", "--nc", "stop", VPN_NAME }
			action = "wireguard stop"
		else
			arguments = { "scutil", "--nc", "start", VPN_NAME }
			action = "wireguard start"
		end

		easybar.log(easybar.level.info, action, VPN_NAME)

		run_command(arguments, ACTION_COMMAND_OPTIONS, function(output, ok, code)
			log_command_result(action, command_label(arguments), output, ok, code)
			finish_toggle()
		end)
	end)
end

wireguard = easybar.add(easybar.kind.group, "wireguard", {
	position = "right",
	order = 2,
	background = {
		padding_left = 12,
		padding_right = 12,
	},
	spacing = 0,
	popup = {
		drawing = true,
		background = {
			color = COLORS.popup_bg,
			border_color = COLORS.border,
			border_width = 1,
			corner_radius = 8,
		},
		padding_x = 10,
		padding_y = 8,
	},
})

wireguard_icon = easybar.add(easybar.kind.item, "wireguard_icon", {
	parent = wireguard.name,
	icon = {
		string = VPN_ICON,
		color = COLORS.muted,
	},
	label = {
		string = "",
	},
})

wireguard_popup_label = easybar.add(easybar.kind.item, "wireguard_popup_label", {
	position = "popup." .. wireguard.name,
	label = {
		string = "",
		color = COLORS.muted,
	},
})

wireguard:subscribe({
	easybar.events.network_change,
	easybar.events.forced,
}, function(event)
	apply_network_event(event)
	refresh()
end)

wireguard:subscribe(easybar.events.mouse.clicked, function(event)
	if event.button == nil or event.button == easybar.events.mouse.left_button then
		toggle_wireguard()
	end
end)

refresh()
