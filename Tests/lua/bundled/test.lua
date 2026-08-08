-- Smoke-loads every selectable example widget from the install manifest.

local root = assert(arg[1], "repository root argument is required")
local manifest_path = root .. "/widgets/install-manifest.csv"
local manifest = assert(io.open(manifest_path, "r"))
local entrypoints = {}

for raw_line in manifest:lines() do
	local line = raw_line:gsub("\r$", "")
	if line ~= "" and not line:match("^%s*#") then
		local entrypoint = assert(line:match("^([^;]+);"), "invalid widget manifest line: " .. line)
		entrypoints[#entrypoints + 1] = entrypoint
	end
end
manifest:close()

assert(#entrypoints > 0, "widget manifest contains no selectable entrypoints")

local host = assert(loadfile(root .. "/Tests/lua/helpers/widget_host.lua"))()
host.configure(root)
local shared_ids = {}

for _, entrypoint in ipairs(entrypoints) do
	local path = root .. "/widgets/" .. entrypoint
	local easybar = host.new(root, { shared_ids = shared_ids })
	local environment = setmetatable({ easybar = easybar }, { __index = _G })
	local chunk, load_error = loadfile(path, "t", environment)
	assert(chunk, entrypoint .. " failed to load: " .. tostring(load_error))

	local ok, runtime_error = pcall(chunk)
	assert(ok, entrypoint .. " failed during startup: " .. tostring(runtime_error))
end

print("Lua example smoke test passed for " .. tostring(#entrypoints) .. " widgets")
