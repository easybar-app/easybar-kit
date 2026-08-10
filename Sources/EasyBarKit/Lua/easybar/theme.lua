--- Module contract:
--- Exposes the resolved active EasyBar theme passed by the Swift host.
--- Returns immutable-by-convention theme snapshots for widget APIs.

--- Theme module table.
local M = {}

--- Environment variable containing the resolved theme JSON.
local THEME_ENV = "EASYBAR_INTERNAL_THEME_JSON"

--- Loads the sibling generated theme token module.
local function load_theme_tokens()
	local base_dir = debug.getinfo(1, "S").source:match("^@(.*/)")
	local chunk, err = loadfile(base_dir .. "theme_tokens.lua")

	if not chunk then
		error("failed to load easybar theme tokens module: " .. tostring(err))
	end

	return chunk()
end

--- Supported theme color tokens.
local COLOR_KEYS = load_theme_tokens().keys

--- Returns one deep copy of a table.
local function deep_copy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}

	for key, item in pairs(value) do
		copy[key] = deep_copy(item)
	end

	return copy
end

--- Loads the sibling JSON module.
local function load_json()
	local base_dir = debug.getinfo(1, "S").source:match("^@(.*/)")
	local chunk, err = loadfile(base_dir .. "json.lua")

	if not chunk then
		error("failed to load easybar json module: " .. tostring(err))
	end

	return chunk()
end

--- Decodes the host-provided theme JSON.
local function decode_theme()
	local encoded = os.getenv(THEME_ENV)

	if encoded == nil or encoded == "" then
		error(THEME_ENV .. " is missing")
	end

	local json = load_json()
	local ok, decoded = pcall(json.decode, encoded)

	if not ok then
		error("failed to decode " .. THEME_ENV .. ": " .. tostring(decoded))
	end

	return decoded
end

--- Builds theme reference strings for all supported tokens.
local function build_refs()
	local refs = {}

	for _, key in ipairs(COLOR_KEYS) do
		refs[key] = "theme." .. key
	end

	return refs
end

--- Returns normalized theme colors for all supported tokens.
local function build_colors(theme)
	local colors = {}

	for _, key in ipairs(COLOR_KEYS) do
		colors[key] = theme.colors[key]
	end

	return colors
end
--- Validates one decoded theme payload.
local function validate_theme(theme)
	if type(theme) ~= "table" then
		error("theme payload must be a table")
	end

	if type(theme.name) ~= "string" or theme.name == "" then
		error("theme.name must be a non-empty string")
	end

	if type(theme.colors) ~= "table" then
		error("theme.colors must be a table")
	end

	for _, key in ipairs(COLOR_KEYS) do
		if type(theme.colors[key]) ~= "string" or theme.colors[key] == "" then
			error("theme.colors." .. key .. " must be a non-empty string")
		end
	end
end

--- Returns the normalized public theme shape.
local function build_theme(theme)
	return {
		name = theme.name,
		colors = build_colors(theme),
		ref = build_refs(),
	}
end

--- Active resolved theme payload.
local active_theme = decode_theme()
validate_theme(active_theme)
active_theme = build_theme(active_theme)

--- Returns a copy of the active resolved theme.
function M.current()
	return deep_copy(active_theme)
end

return M
