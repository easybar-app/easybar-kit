--- Reusable text helpers for user widgets.
local M = {}

--- Returns one value converted to a string with surrounding whitespace removed.
function M.trim(value)
	return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

--- Returns the length of one string and whether it is valid UTF-8.
local function string_length(value)
	local length = utf8.len(value)
	if length ~= nil then
		return length, true
	end

	return #value, false
end

--- Returns the first `length` characters, falling back to bytes for invalid UTF-8.
local function string_prefix(value, length, valid_utf8)
	if not valid_utf8 then
		return value:sub(1, length)
	end

	local offset = utf8.offset(value, length + 1)
	return offset == nil and value or value:sub(1, offset - 1)
end

--- Returns a string shortened to at most `maximum_length` UTF-8 characters.
--- The default omission marker is `...`.
function M.truncate(value, maximum_length, omission)
	local text = tostring(value or "")
	local limit = math.max(0, math.floor(tonumber(maximum_length) or 0))
	local suffix = omission == nil and "..." or tostring(omission)
	local text_length, text_is_utf8 = string_length(text)

	if text_length <= limit then
		return text
	end

	local suffix_length = string_length(suffix)

	if limit == 0 then
		return ""
	end

	if suffix_length >= limit then
		return string_prefix(text, limit, text_is_utf8)
	end

	return string_prefix(text, limit - suffix_length, text_is_utf8) .. suffix
end

return M
