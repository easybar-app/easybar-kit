--- Module contract:
--- Owns structured stderr logging for the Lua runtime and widgets.
--- Returns one logger table with runtime- and widget-scoped writers.
--- Runtime logger module table.
local M = {}

--- Flattens one log field into a single safe line.
local function normalize_text(value)
	value = tostring(value or "")
	value = value:gsub("\r", " ")
	value = value:gsub("\n", " ")
	value = value:gsub("\t", " ")
	return value
end

--- Writes one structured log line to stderr.
local function write(level, source, message)
	io.stderr:write(
		"EASYBAR_LUA_LOG\t"
			.. normalize_text(level)
			.. "\t"
			.. normalize_text(source)
			.. "\t"
			.. normalize_text(message)
			.. "\n"
	)
	io.stderr:flush()
end

--- Writes one runtime trace log line.
function M.trace(message)
	write("TRACE", "runtime", message)
end

--- Writes one runtime debug log line.
function M.debug(message)
	write("DEBUG", "runtime", message)
end

--- Writes one runtime info log line.
function M.info(message)
	write("INFO", "runtime", message)
end

--- Writes one runtime warning log line.
function M.warn(message)
	write("WARN", "runtime", message)
end

--- Writes one runtime error log line.
function M.error(message)
	write("ERROR", "runtime", message)
end

--- Writes one widget-scoped log line.
function M.widget(source, level, message)
	write(level or "INFO", source or "widget", message)
end

return M
