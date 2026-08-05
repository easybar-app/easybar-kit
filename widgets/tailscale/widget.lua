--- Tailscale widget for EasyBar.
---
--- Left-click toggles Tailscale up/down.
--- Right-click opens exit-node controls.
---
--- `TAILSCALE` may point to an executable name or absolute path, such as
--- `tailscale` or `/opt/homebrew/bin/tailscale`. It must not contain shell arguments.

local text = require("text")

local CHECK_INTERVAL_SECONDS = 60

local COLORS = {
	text = easybar.theme.ref.text,
	muted = easybar.theme.ref.muted,
	success = easybar.theme.ref.success,
	accent = easybar.theme.ref.accent,
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

local TAILSCALE = text.trim(os.getenv("TAILSCALE") or "")
if TAILSCALE == "" then
	TAILSCALE = "tailscale"
end

local tailscale_icon
local popup_label
local popup_exit_node_label

local state = {
	available = false,
	tailscale_connected = false,
	exit_node_enabled = false,
	exit_nodes = {},
	status_detail = "Inactive",
	exit_node_detail = "Exit node unavailable",
}

local refresh

-- Coalesces bursts of status events while one asynchronous read is in flight.
local refresh_running = false
local refresh_pending = false

-- Prevents double-clicks from starting overlapping up/down or exit-node commands.
local action_running = false

local function tailscale_arguments(...)
	return { TAILSCALE, ... }
end

local function command_label(arguments)
	local values = {}
	for index, argument in ipairs(arguments) do
		values[index] = tostring(argument)
	end
	return table.concat(values, " ")
end

--- Runs a Tailscale CLI command asynchronously and normalizes output/code.
local function run_command(arguments, options, callback)
	easybar.spawn_async(arguments, options or COMMAND_OPTIONS, function(output, code)
		output = text.trim(output or "")
		code = code or 0

		callback(output, code == 0, code)
	end)
end

local function log_command_result(action, command, output, ok, code)
	if ok then
		if output ~= "" then
			easybar.log(easybar.level.info, action .. " ok", command, output)
		else
			easybar.log(easybar.level.info, action .. " ok", command)
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

--- Decodes `tailscale status --json` output into a Lua table.
local function decode_json(output)
	local ok, value = pcall(easybar.json.decode, output)
	if ok and type(value) == "table" then
		return value, nil
	end

	return nil, value
end

local function status_label(connected)
	return connected and "Active" or "Inactive"
end

local function first_health_message(status)
	local health = status.Health
	if type(health) ~= "table" then
		return nil
	end

	for _, message in ipairs(health) do
		if type(message) == "string" and text.trim(message) ~= "" then
			return text.trim(message)
		end
	end

	return nil
end

--- Returns the selected exit-node ID while Tailscale is connected.
---
--- Tailscale may retain exit-node status data briefly while transitioning
--- between backend states. Ignoring that data unless the backend is running
--- prevents both "Disabled" and an exit node from being checked.
local function active_exit_node_id(status, connected)
	if not connected then
		return nil
	end

	local exit_node_status = status.ExitNodeStatus
	if type(exit_node_status) ~= "table" then
		return nil
	end

	local id = exit_node_status.ID
	if type(id) ~= "string" then
		return nil
	end

	id = text.trim(id)
	if id == "" then
		return nil
	end

	return id
end

--- Returns the exit nodes advertised by peers, sorted for a stable native menu.
local function exit_nodes_from_status(status, active_id)
	local nodes = {}

	if type(status.Peer) == "table" then
		for peer_id, peer in pairs(status.Peer) do
			if type(peer) == "table" and peer.ExitNodeOption == true then
				local ips = type(peer.TailscaleIPs) == "table" and peer.TailscaleIPs or {}
				local target = text.trim(ips[1] or peer.DNSName or peer.HostName or "")

				if target ~= "" then
					local label = text.trim(peer.HostName or peer.DNSName or target):gsub("%.$", "")

					table.insert(nodes, {
						label = label,
						target = target,
						active = active_id ~= nil and (peer.ID == active_id or peer_id == active_id),
					})
				end
			end
		end
	end

	table.sort(nodes, function(left, right)
		return left.label:lower() < right.label:lower()
	end)

	return nodes
end

local function unavailable_snapshot(detail)
	return {
		available = false,
		tailscale_connected = false,
		exit_node_enabled = false,
		exit_nodes = {},
		status_detail = detail or "Unavailable",
		exit_node_detail = "Exit node unavailable",
	}
end

--- Converts raw `tailscale status --json` data into widget state.
local function snapshot_from_status(status)
	local backend_state = text.trim(status.BackendState or "")
	local connected = backend_state == "Running"
	local health_message = first_health_message(status)

	local status_detail = text.trim(health_message or backend_state)
	if status_detail == "" then
		status_detail = status_label(connected)
	end

	local active_id = active_exit_node_id(status, connected)
	local exit_node_enabled = active_id ~= nil
	local exit_nodes = exit_nodes_from_status(status, active_id)

	local active_exit_node_label
	for _, node in ipairs(exit_nodes) do
		if node.active then
			active_exit_node_label = node.label
			break
		end
	end

	local exit_node_detail
	if not connected then
		exit_node_detail = "Exit node unavailable"
	elseif exit_node_enabled then
		exit_node_detail = active_exit_node_label ~= nil and "Exit node: " .. active_exit_node_label or "Exit node on"
	else
		exit_node_detail = "Exit node off"
	end

	return {
		available = true,
		tailscale_connected = connected,
		exit_node_enabled = exit_node_enabled,
		exit_nodes = exit_nodes,
		status_detail = status_detail,
		exit_node_detail = exit_node_detail,
	}
end

--- Reads current Tailscale status and returns a normalized snapshot.
local function read_status(callback)
	local arguments = tailscale_arguments("status", "--json")

	run_command(arguments, COMMAND_OPTIONS, function(output, ok, code)
		if not ok then
			easybar.log(
				easybar.level.warn,
				"tailscale status failed",
				"code=" .. tostring(code),
				output ~= "" and output or "<empty>"
			)

			callback(unavailable_snapshot("Unavailable"))
			return
		end

		if output == "" then
			easybar.log(easybar.level.warn, "tailscale status returned empty output")
			callback(unavailable_snapshot("Unavailable"))
			return
		end

		local status, err = decode_json(output)
		if status == nil then
			easybar.log(easybar.level.warn, "tailscale status JSON decode failed", tostring(err))
			callback(unavailable_snapshot("Invalid status output"))
			return
		end

		callback(snapshot_from_status(status))
	end)
end

--- Stores the latest snapshot and logs meaningful state transitions.
local function update_state(snapshot)
	if state.tailscale_connected ~= snapshot.tailscale_connected then
		easybar.log(easybar.level.debug, "tailscale state changed", snapshot.tailscale_connected and "active" or "inactive")
	end

	if state.exit_node_enabled ~= snapshot.exit_node_enabled then
		easybar.log(
			easybar.level.debug,
			"tailscale exit node changed",
			snapshot.exit_node_enabled and "enabled" or "disabled"
		)
	end

	state.available = snapshot.available
	state.tailscale_connected = snapshot.tailscale_connected
	state.exit_node_enabled = snapshot.exit_node_enabled
	state.exit_nodes = snapshot.exit_nodes
	state.status_detail = snapshot.status_detail
	state.exit_node_detail = snapshot.exit_node_detail

	return snapshot
end

local function current_icon_name(snapshot)
	if not snapshot.tailscale_connected then
		return "tailscale-inactive.svg"
	end

	if snapshot.exit_node_enabled then
		return "tailscale-active-exit-node.svg"
	end

	return "tailscale-active.svg"
end

local function context_menu(snapshot)
	local exit_nodes = {
		{
			id = "exit_node:disable",
			title = "Disabled",
			checked = not snapshot.exit_node_enabled,
		},
	}

	for index, node in ipairs(snapshot.exit_nodes or {}) do
		table.insert(exit_nodes, {
			id = "exit_node:" .. tostring(index),
			title = node.label,
			checked = node.active,
		})
	end

	if #exit_nodes == 1 then
		table.insert(exit_nodes, {
			title = "No exit nodes available",
			enabled = false,
		})
	end

	return {
		{
			title = "Exit Node",
			submenu = exit_nodes,
		},
		{
			separator = true,
		},
		{
			id = "refresh",
			title = "Refresh",
		},
	}
end

local function render(snapshot)
	local status_color = snapshot.tailscale_connected and COLORS.success or COLORS.muted
	local exit_node_color = snapshot.exit_node_enabled and COLORS.text or COLORS.muted

	tailscale_icon:set({
		icon = {
			string = "",
			image = {
				path = easybar.asset("@/assets/" .. current_icon_name(snapshot)),
				size = 16,
				corner_radius = 0,
			},
		},
		label = {
			string = "",
		},
		opacity = 1.0,
		context_menu = context_menu(snapshot),
	})

	popup_label:set({
		label = {
			string = snapshot.status_detail or status_label(snapshot.tailscale_connected),
			color = status_color,
		},
	})

	popup_exit_node_label:set({
		drawing = snapshot.tailscale_connected and "on" or "off",
		label = {
			string = snapshot.exit_node_detail,
			color = exit_node_color,
		},
	})
end

local function render_working(message)
	if popup_label == nil then
		return
	end

	popup_label:set({
		label = {
			string = message,
			color = COLORS.accent,
		},
	})
end

--- Re-reads status while coalescing events that arrive during an active read.
refresh = function()
	if refresh_running then
		refresh_pending = true
		return
	end

	refresh_running = true

	read_status(function(snapshot)
		refresh_running = false
		render(update_state(snapshot))

		if refresh_pending then
			refresh_pending = false
			refresh()
		end
	end)
end

local function finish_action()
	action_running = false
	refresh()
end

--- Toggles Tailscale up/down while preventing overlapping actions.
local function toggle_tailscale()
	if action_running then
		easybar.log(easybar.level.debug, "tailscale toggle ignored", "action already running")
		return
	end

	action_running = true
	render_working("Working…")

	read_status(function(snapshot)
		if not snapshot.available then
			easybar.log(easybar.level.warn, "tailscale toggle skipped", "status unavailable")
			finish_action()
			return
		end

		local arguments
		if snapshot.tailscale_connected then
			arguments = tailscale_arguments("down")
		else
			arguments = tailscale_arguments("up")
		end

		run_command(arguments, ACTION_COMMAND_OPTIONS, function(output, ok, code)
			log_command_result("tailscale toggle", command_label(arguments), output, ok, code)
			finish_action()
		end)
	end)
end

--- Selects or disables an exit node while Tailscale is active.
local function set_exit_node(target)
	if action_running then
		easybar.log(easybar.level.debug, "tailscale exit node change ignored", "action already running")
		return
	end

	action_running = true
	render_working("Working…")

	read_status(function(snapshot)
		if not snapshot.available then
			easybar.log(easybar.level.warn, "tailscale exit node change skipped", "status unavailable")
			finish_action()
			return
		end

		if not snapshot.tailscale_connected then
			easybar.log(easybar.level.warn, "tailscale exit node change ignored", "tailscale inactive")
			finish_action()
			return
		end

		local arguments = tailscale_arguments("set", "--exit-node=" .. (target or ""), "--accept-routes")

		run_command(arguments, ACTION_COMMAND_OPTIONS, function(output, ok, code)
			log_command_result("tailscale exit node change", command_label(arguments), output, ok, code)
			finish_action()
		end)
	end)
end

tailscale_icon = easybar.add(easybar.kind.item, "tailscale_icon", {
	position = "right",
	order = 2,
	interval = CHECK_INTERVAL_SECONDS,
	icon = {
		image = {
			path = easybar.asset("@/assets/tailscale-inactive.svg"),
			size = 16,
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
		spacing = 6,
	},
	on_interval = function()
		refresh()
	end,
})

popup_label = easybar.add(easybar.kind.item, "tailscale_popup_label", {
	position = "popup." .. tailscale_icon.name,
	label = {
		string = "",
		color = COLORS.text,
	},
})

popup_exit_node_label = easybar.add(easybar.kind.item, "tailscale_popup_exit_node_label", {
	position = "popup." .. tailscale_icon.name,
	drawing = "off",
	label = {
		string = "",
		color = COLORS.muted,
	},
})

tailscale_icon:subscribe({
	easybar.events.network_change,
	easybar.events.system_woke,
	easybar.events.forced,
}, function()
	refresh()
end)

tailscale_icon:subscribe(easybar.events.mouse.clicked, function(event)
	if event.button == nil or event.button == easybar.events.mouse.left_button then
		toggle_tailscale()
	end
end)

tailscale_icon:subscribe(easybar.events.context_menu.clicked, function(event)
	if event.action_id == "refresh" then
		refresh()
	elseif event.action_id == "exit_node:disable" then
		set_exit_node(nil)
	else
		local index = tonumber((event.action_id or ""):match("^exit_node:(%d+)$"))
		local node = index ~= nil and state.exit_nodes[index] or nil

		if node ~= nil then
			set_exit_node(node.target)
		end
	end
end)

refresh()
