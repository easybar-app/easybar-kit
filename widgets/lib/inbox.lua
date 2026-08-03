--- Reusable data helpers for inbox-publishing widgets.
local text = require("text")

local M = {}

M.maximum_error_length = 12000

---Returns a bounded, non-empty error message.
---@param output any
---@param fallback string
---@return string
function M.error_message(output, fallback)
	local message = text.trim(output)
	if message == "" then
		message = tostring(fallback)
	end
	return text.truncate(message, M.maximum_error_length, "…")
end

---Decodes one JSON array, preserving the distinction between `{}` and `[]`.
---@param json_module table
---@param output string
---@return table? value
function M.decode_array(json_module, output)
	local ok, value = pcall(json_module.decode, output)
	if not ok or type(json_module.is_array) ~= "function" or not json_module.is_array(value) then
		return nil
	end
	return value
end

local function is_leap_year(year)
	return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function days_in_month(year, month)
	local lengths = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	if month == 2 and is_leap_year(year) then
		return 29
	end
	return lengths[month]
end

-- Gregorian calendar date to days since 1970-01-01, independent of the local timezone.
local function days_from_civil(year, month, day)
	year = year - (month <= 2 and 1 or 0)
	local era = math.floor(year / 400)
	local year_of_era = year - era * 400
	local month_position = month + (month > 2 and -3 or 9)
	local day_of_year = math.floor((153 * month_position + 2) / 5) + day - 1
	local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) - math.floor(year_of_era / 100) + day_of_year
	return era * 146097 + day_of_era - 719468
end

local function timezone_offset(rest)
	if rest == "Z" or rest == "z" then
		return 0
	end

	local sign, hours, minutes = rest:match("^([+-])(%d%d):?(%d%d)$")
	if sign == nil then
		return nil
	end
	hours = tonumber(hours)
	minutes = tonumber(minutes)
	if hours > 23 or minutes > 59 then
		return nil
	end
	local seconds = hours * 3600 + minutes * 60
	return sign == "+" and seconds or -seconds
end

---Parses an ISO-8601 timestamp into Unix seconds without depending on the host timezone.
---Fractional seconds are accepted and discarded because inbox sorting uses second precision.
---@param value any
---@return number? timestamp
function M.timestamp(value)
	if type(value) ~= "string" then
		return nil
	end

	local year, month, day, hour, minute, second, rest =
		value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt](%d%d):(%d%d):(%d%d)(.*)$")
	if year == nil then
		return nil
	end

	year = tonumber(year)
	month = tonumber(month)
	day = tonumber(day)
	hour = tonumber(hour)
	minute = tonumber(minute)
	second = tonumber(second)
	if month < 1 or month > 12 or day < 1 or day > days_in_month(year, month) then
		return nil
	end
	if hour > 23 or minute > 59 or second > 59 then
		return nil
	end

	local zone = rest
	if rest:sub(1, 1) == "." then
		local fraction
		fraction, zone = rest:match("^(%.%d+)(.*)$")
		if fraction == nil then
			return nil
		end
	end

	local offset = timezone_offset(zone)
	if offset == nil then
		return nil
	end

	return days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second - offset
end

return M
