--- Module contract:
--- Owns finite numeric validation shared by the public Lua APIs and schedulers.
local M = {}

M.MAX_INTERVAL_SECONDS = 365 * 24 * 60 * 60
M.MAX_TIMER_DELAY_SECONDS = M.MAX_INTERVAL_SECONDS
M.MAX_COMMAND_TIMEOUT_SECONDS = 24 * 60 * 60
M.MAX_COMMAND_OUTPUT_BYTES = 64 * 1024 * 1024

--- Returns whether one value can be represented as a finite Lua number.
function M.is_finite_number(value)
	local number = tonumber(value)
	return number ~= nil and number == number and number ~= math.huge and number ~= -math.huge
end

--- Returns one finite number within optional inclusive bounds, or nil.
function M.finite_number(value, minimum, maximum)
	if not M.is_finite_number(value) then
		return nil
	end

	local number = tonumber(value)
	if minimum ~= nil and number < minimum then
		return nil
	end
	if maximum ~= nil and number > maximum then
		return nil
	end
	return number
end

--- Returns one finite positive number within an optional upper bound, or nil.
function M.positive_number(value, maximum)
	return M.finite_number(value, 0, maximum) and tonumber(value) > 0 and tonumber(value) or nil
end

--- Returns one finite non-negative number within an optional upper bound, or nil.
function M.non_negative_number(value, maximum)
	return M.finite_number(value, 0, maximum)
end

--- Returns one finite positive integer within an optional upper bound, or nil.
function M.positive_integer(value, maximum)
	local number = M.positive_number(value, maximum)
	if number == nil or math.floor(number) ~= number then
		return nil
	end
	return number
end

--- Returns one whole-second widget interval in the supported range, or nil.
function M.interval_seconds(value)
	local number = M.positive_number(value, M.MAX_INTERVAL_SECONDS)
	if number == nil then
		return nil
	end
	return math.max(1, math.floor(number))
end

return M
