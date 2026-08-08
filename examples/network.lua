-- Read-only network example driven by EasyBar's native network event snapshot.

local state = {
	interface_name = nil,
}

local network

local COLORS = {
	text = easybar.theme.ref.text,
	muted = easybar.theme.ref.muted,
	accent = easybar.theme.ref.accent,
}

local function normalize_interface_name(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then
		return nil
	end

	return trimmed
end

local function apply_event(event)
	if event == nil or type(event.network) ~= "table" then
		return
	end

	if event.network.interface_name ~= nil then
		state.interface_name = normalize_interface_name(event.network.interface_name)
	end
end

local function label_text()
	if state.interface_name ~= nil then
		return state.interface_name
	end

	return "offline"
end

local function render()
	local connected = state.interface_name ~= nil
	local color = connected and COLORS.text or COLORS.muted

	network:set({
		icon = {
			string = "📶",
			color = connected and COLORS.accent or COLORS.muted,
		},
		label = {
			string = label_text(),
			color = color,
		},
	})
end

network = easybar.add(easybar.kind.item, "network", {
	position = "right",
	order = 35,
	icon = {
		string = "📶",
		color = COLORS.muted,
	},
	label = {
		string = "",
		color = COLORS.muted,
	},
})

network:subscribe({
	easybar.events.network_change,
	easybar.events.wifi_change,
	easybar.events.system_woke,
	easybar.events.forced,
}, function(event)
	apply_event(event)
	render()
end)

render()
