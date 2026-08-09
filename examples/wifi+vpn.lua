-- Read-only VPN indicator using the primary-interface tunnel flag from native
-- network events; it does not start or stop the VPN.

local state = {
	vpn_connected = false,
}

local vpn

local COLORS = {
	connected = easybar.theme.ref.accent,
	disconnected = easybar.theme.ref.muted,
}

--- Applies the primary-interface tunnel flag from one native network event.
---@param event table? EasyBar event payload.
local function apply_event(event)
	if event == nil or type(event.network) ~= "table" then
		return
	end

	local value = event.network.primary_interface_is_tunnel
	if type(value) == "boolean" then
		state.vpn_connected = value
	end
end

--- Returns display content for the current VPN connection state.
---@return table status Icon, label, and color fields.
local function current_state()
	if state.vpn_connected then
		return {
			icon = "󰦝",
			label = "VPN On",
			color = COLORS.connected,
		}
	end

	return {
		icon = "󰌾",
		label = "VPN Off",
		color = COLORS.disconnected,
	}
end

--- Updates the VPN widget from the latest native network state.
local function render()
	local status = current_state()

	vpn:set({
		icon = {
			string = status.icon,
			color = status.color,
		},
		label = {
			string = status.label,
			color = status.color,
		},
	})
end

vpn = easybar.add(easybar.kind.item, "vpn", {
	position = "right",
	order = 41,
})

vpn:subscribe({
	easybar.events.network_change,
	easybar.events.wifi_change,
	easybar.events.system_woke,
	easybar.events.forced,
}, function(event)
	apply_event(event)
	render()
end)

render()
