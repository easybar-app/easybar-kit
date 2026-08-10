--- Module contract:
--- Owns JSON encoding and decoding for Swift-Lua process messages.
--- Returns one table with `encode(...)`, `decode(...)`, shape constructors, and `null`.
--- JSON module table.
local M = {}
--- Optional UTF-8 library used for unicode escape decoding.
local utf8lib = rawget(_G, "utf8")

--- Metatable marking tables that must encode as JSON arrays.
local array_metatable = {}
--- Metatable marking tables that must encode as JSON objects.
local object_metatable = {}
--- Unique sentinel used to preserve JSON null values inside Lua tables.
M.null = setmetatable({}, {
	__tostring = function()
		return "null"
	end,
})

--- Marks a Lua table as a JSON array, including when it is empty.
function M.array(value)
	if value == nil then
		value = {}
	end
	assert(type(value) == "table", "json.array expects a table")
	return setmetatable(value, array_metatable)
end

--- Marks a Lua table as a JSON object, including when it is empty.
function M.object(value)
	if value == nil then
		value = {}
	end
	assert(type(value) == "table", "json.object expects a table")
	return setmetatable(value, object_metatable)
end

--- Encodes one Lua string as a JSON string literal.
local function encode_string(value)
	local replacements = {
		['"'] = '\\"',
		["\\"] = "\\\\",
		["\b"] = "\\b",
		["\f"] = "\\f",
		["\n"] = "\\n",
		["\r"] = "\\r",
		["\t"] = "\\t",
	}

	return '"'
		.. value:gsub('[%z\1-\31\\"]', function(char)
			return replacements[char] or string.format("\\u%04x", char:byte())
		end)
		.. '"'
end

--- Returns whether one Lua number is finite and therefore valid JSON.
local function is_finite_number(value)
	return value == value and value ~= math.huge and value ~= -math.huge
end

--- Returns the contiguous length of a JSON-array table, or nil for an object-shaped table.
local function array_length(value)
	local count = 0
	local max_index = 0

	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return nil
		end

		max_index = math.max(max_index, key)
		count = count + 1
	end

	if max_index ~= count then
		return nil
	end

	return max_index
end

--- Returns whether a Lua table should be encoded as a JSON array.
local function array_shape(value)
	local metatable = getmetatable(value)
	if metatable == object_metatable then
		return false, nil
	end

	local length = array_length(value)
	if metatable == array_metatable then
		if length == nil then
			error("json array keys must be contiguous positive integers")
		end
		return true, length
	end

	return length ~= nil, length
end

--- Returns whether a value is a dense JSON-array table.
function M.is_array(value)
	if type(value) ~= "table" then
		return false
	end

	local succeeded, is_array = pcall(function()
		return select(1, array_shape(value))
	end)
	return succeeded and is_array
end

--- Encodes one Lua value as JSON.
local function encode_value(value, seen)
	if value == nil or value == M.null then
		return "null"
	end

	local value_type = type(value)

	if value_type == "boolean" then
		return value and "true" or "false"
	end

	if value_type == "number" then
		if not is_finite_number(value) then
			error("json cannot encode non-finite numbers")
		end
		return tostring(value)
	end

	if value_type == "string" then
		return encode_string(value)
	end

	if value_type == "table" then
		if seen[value] then
			error("json cannot encode cyclic tables")
		end
		seen[value] = true

		local is_array, length = array_shape(value)
		local out = {}

		if is_array then
			for index = 1, length do
				out[#out + 1] = encode_value(value[index], seen)
			end
			seen[value] = nil
			return "[" .. table.concat(out, ",") .. "]"
		end

		for key, item in pairs(value) do
			if type(key) ~= "string" then
				error("json object keys must be strings")
			end
			out[#out + 1] = encode_string(key) .. ":" .. encode_value(item, seen)
		end
		table.sort(out)
		seen[value] = nil
		return "{" .. table.concat(out, ",") .. "}"
	end

	error("unsupported json encode type: " .. value_type)
end

--- Encodes one Lua value tree into a JSON string.
function M.encode(value)
	return encode_value(value, {})
end

--- Converts one Unicode code point to UTF-8.
local function codepoint_to_utf8(codepoint)
	if codepoint < 0 or codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF) then
		error("invalid unicode code point")
	end

	if utf8lib and utf8lib.char then
		return utf8lib.char(codepoint)
	end

	if codepoint <= 0x7F then
		return string.char(codepoint)
	end
	if codepoint <= 0x7FF then
		return string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + (codepoint % 0x40))
	end
	if codepoint <= 0xFFFF then
		return string.char(
			0xE0 + math.floor(codepoint / 0x1000),
			0x80 + (math.floor(codepoint / 0x40) % 0x40),
			0x80 + (codepoint % 0x40)
		)
	end

	return string.char(
		0xF0 + math.floor(codepoint / 0x40000),
		0x80 + (math.floor(codepoint / 0x1000) % 0x40),
		0x80 + (math.floor(codepoint / 0x40) % 0x40),
		0x80 + (codepoint % 0x40)
	)
end

--- Recursive-descent JSON parser.
local Parser = {}
--- Parser metatable.
Parser.__index = Parser

--- Creates one parser for a JSON string.
function Parser:new(text)
	return setmetatable({
		text = text,
		pos = 1,
		len = #text,
	}, self)
end

--- Returns the current character without advancing.
function Parser:peek()
	return self.text:sub(self.pos, self.pos)
end

--- Returns the current character and advances.
function Parser:next()
	local char = self.text:sub(self.pos, self.pos)
	self.pos = self.pos + 1
	return char
end

--- Advances past JSON whitespace.
function Parser:skip_whitespace()
	while self.pos <= self.len do
		local char = self:peek()
		if char == " " or char == "\n" or char == "\r" or char == "\t" then
			self.pos = self.pos + 1
		else
			break
		end
	end
end

--- Consumes one expected character.
function Parser:expect(expected)
	local actual = self:next()
	if actual ~= expected then
		error("expected '" .. expected .. "', got '" .. tostring(actual) .. "'")
	end
end

--- Parses exactly four hexadecimal digits from a Unicode escape.
function Parser:parse_hex_code_unit()
	local hex = self.text:sub(self.pos, self.pos + 3)
	if #hex ~= 4 or not hex:match("^[0-9a-fA-F]+$") then
		error("invalid unicode escape")
	end
	self.pos = self.pos + 4
	return tonumber(hex, 16)
end

--- Parses one Unicode escape, including UTF-16 surrogate pairs.
function Parser:parse_unicode_escape()
	local high = self:parse_hex_code_unit()

	if high >= 0xD800 and high <= 0xDBFF then
		if self.text:sub(self.pos, self.pos + 1) ~= "\\u" then
			error("high surrogate must be followed by a low surrogate")
		end
		self.pos = self.pos + 2
		local low = self:parse_hex_code_unit()
		if low < 0xDC00 or low > 0xDFFF then
			error("invalid low surrogate")
		end

		local codepoint = 0x10000 + (high - 0xD800) * 0x400 + (low - 0xDC00)
		return codepoint_to_utf8(codepoint)
	end

	if high >= 0xDC00 and high <= 0xDFFF then
		error("unexpected low surrogate")
	end

	return codepoint_to_utf8(high)
end

--- Parses one JSON string.
function Parser:parse_string()
	self:expect('"')

	local out = {}

	while self.pos <= self.len do
		local char = self:next()

		if char == '"' then
			return table.concat(out)
		end

		if char == "\\" then
			local escape = self:next()

			if escape == '"' then
				out[#out + 1] = '"'
			elseif escape == "\\" then
				out[#out + 1] = "\\"
			elseif escape == "/" then
				out[#out + 1] = "/"
			elseif escape == "b" then
				out[#out + 1] = "\b"
			elseif escape == "f" then
				out[#out + 1] = "\f"
			elseif escape == "n" then
				out[#out + 1] = "\n"
			elseif escape == "r" then
				out[#out + 1] = "\r"
			elseif escape == "t" then
				out[#out + 1] = "\t"
			elseif escape == "u" then
				out[#out + 1] = self:parse_unicode_escape()
			else
				error("invalid escape sequence")
			end
		else
			if char:byte() < 0x20 then
				error("unescaped control character in json string")
			end
			out[#out + 1] = char
		end
	end

	error("unterminated string")
end

--- Parses one JSON number.
function Parser:parse_number()
	local start = self.pos

	--- Consumes the next character when it matches one numeric grammar pattern.
	local function advance_if(pattern)
		local char = self:peek()
		if char ~= "" and char:match(pattern) then
			self.pos = self.pos + 1
			return true
		end
		return false
	end

	advance_if("[-]")

	if self:peek() == "0" then
		self.pos = self.pos + 1
	else
		if not advance_if("%d") then
			error("invalid number")
		end
		while advance_if("%d") do
		end
	end

	if self:peek() == "." then
		self.pos = self.pos + 1
		if not advance_if("%d") then
			error("invalid fraction")
		end
		while advance_if("%d") do
		end
	end

	local char = self:peek()
	if char == "e" or char == "E" then
		self.pos = self.pos + 1
		advance_if("[+-]")
		if not advance_if("%d") then
			error("invalid exponent")
		end
		while advance_if("%d") do
		end
	end

	local value = tonumber(self.text:sub(start, self.pos - 1))
	if value == nil or not is_finite_number(value) then
		error("invalid number")
	end

	return value
end

--- Parses true, false, or null.
function Parser:parse_literal()
	if self.text:sub(self.pos, self.pos + 3) == "true" then
		self.pos = self.pos + 4
		return true
	end

	if self.text:sub(self.pos, self.pos + 4) == "false" then
		self.pos = self.pos + 5
		return false
	end

	if self.text:sub(self.pos, self.pos + 3) == "null" then
		self.pos = self.pos + 4
		return M.null
	end

	error("invalid literal")
end

--- Parses one JSON array.
function Parser:parse_array()
	self:expect("[")
	self:skip_whitespace()

	local out = M.array()

	if self:peek() == "]" then
		self.pos = self.pos + 1
		return out
	end

	while true do
		out[#out + 1] = self:parse_value()
		self:skip_whitespace()

		local char = self:peek()
		if char == "]" then
			self.pos = self.pos + 1
			break
		end

		self:expect(",")
		self:skip_whitespace()
	end

	return out
end

--- Parses one JSON object.
function Parser:parse_object()
	self:expect("{")
	self:skip_whitespace()

	local out = M.object()

	if self:peek() == "}" then
		self.pos = self.pos + 1
		return out
	end

	while true do
		local key = self:parse_string()
		self:skip_whitespace()
		self:expect(":")
		self:skip_whitespace()
		out[key] = self:parse_value()
		self:skip_whitespace()

		local char = self:peek()
		if char == "}" then
			self.pos = self.pos + 1
			break
		end

		self:expect(",")
		self:skip_whitespace()
	end

	return out
end

--- Parses one JSON value.
function Parser:parse_value()
	self:skip_whitespace()

	local char = self:peek()

	if char == '"' then
		return self:parse_string()
	end

	if char == "{" then
		return self:parse_object()
	end

	if char == "[" then
		return self:parse_array()
	end

	if char == "-" or char:match("%d") then
		return self:parse_number()
	end

	return self:parse_literal()
end

--- Decodes one JSON string into Lua values.
function M.decode(text)
	assert(type(text) == "string", "json.decode expects a string")
	local parser = Parser:new(text)
	local value = parser:parse_value()
	parser:skip_whitespace()

	if parser.pos <= parser.len then
		error("trailing characters after json value")
	end

	return value
end

return M
