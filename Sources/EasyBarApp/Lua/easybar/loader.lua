--- Module contract:
--- Owns widget module paths, isolated environments, and transactional widget startup.
local M = {}

--- Prepends one module search pattern unless it is already configured.
---@param entry string Lua package search pattern.
local function prepend_package_path(entry)
	for existing in package.path:gmatch("[^;]+") do
		if existing == entry then
			return
		end
	end
	package.path = entry .. ";" .. package.path
end

--- Adds package-local and shared module paths for widgets.
---@param widget_dir string Root directory containing installed widgets and libraries.
local function configure_widget_module_paths(widget_dir)
	-- Prepend lower-priority paths first because each call inserts at the front.
	prepend_package_path(widget_dir .. "/shared/?/init.lua")
	prepend_package_path(widget_dir .. "/shared/?.lua")
	prepend_package_path(widget_dir .. "/?/init.lua")
	prepend_package_path(widget_dir .. "/?.lua")
end

--- Creates an isolated widget environment with a source-scoped EasyBar API.
---@param registry table Active runtime registry.
---@param source_path string Absolute widget entrypoint path.
---@param widget_dir string Root directory used for asset resolution.
---@return table environment Widget global environment falling back to standard Lua globals.
local function make_widget_env(registry, source_path, widget_dir)
	local env = {
		easybar = registry.make_widget_api(source_path, widget_dir),
	}
	setmetatable(env, { __index = _G })
	return env
end

--- Rolls back a failed widget load transaction and reports both original and rollback errors.
---@param registry table Active runtime registry.
---@param transaction table Widget-load transaction to restore.
---@param log table Runtime logger.
---@param file string Widget file name used in diagnostics.
---@param phase string Failed load phase.
---@param err any Original failure value.
local function rollback(registry, transaction, log, file, phase, err)
	local rollback_ok, rollback_err = pcall(registry.rollback_widget_load, transaction)
	if not rollback_ok then
		log.error(
			"loader rollback failed file="
				.. tostring(file)
				.. " phase="
				.. tostring(phase)
				.. " error="
				.. tostring(rollback_err)
		)
	end
	log.error("loader failed to " .. tostring(phase) .. " file=" .. tostring(file) .. " error=" .. tostring(err))
end

--- Loads, executes, validates, and commits one widget file transactionally.
---@param widget_dir string Root directory containing widget files.
---@param file string Widget path relative to `widget_dir`.
---@param registry table Active runtime registry.
---@param log table Runtime logger.
---@return boolean loaded Whether the widget committed successfully.
local function load_widget_file(widget_dir, file, registry, log)
	local path = widget_dir .. "/" .. file
	local transaction = registry.begin_widget_load(path)
	local env = make_widget_env(registry, path, widget_dir)
	local chunk, load_err = loadfile(path, "t", env)
	if not chunk then
		rollback(registry, transaction, log, file, "load", load_err)
		return false
	end

	local ok, err = pcall(chunk)
	if not ok then
		rollback(registry, transaction, log, file, "execute", err)
		return false
	end

	local committed, commit_err = pcall(registry.commit_widget_load, transaction)
	if not committed then
		rollback(registry, transaction, log, file, "validate", commit_err)
		return false
	end

	log.debug("loader loaded file=" .. file)
	return true
end

--- Loads every discovered widget while isolating failures to individual transactions.
---@param widget_dir string Root directory containing widget files.
---@param widget_files string[] Ordered widget paths relative to `widget_dir`.
---@param registry table Active runtime registry.
---@param log table Runtime logger.
---@return integer loaded Number of committed widgets.
---@return integer failed Number of rejected widgets.
function M.load_widgets(widget_dir, widget_files, registry, log)
	log.debug("runtime started")
	log.debug("runtime widget_dir=" .. widget_dir)
	configure_widget_module_paths(widget_dir)
	log.debug("runtime widget_packages=" .. widget_dir)
	log.debug("runtime widget_shared=" .. widget_dir .. "/shared")

	local loaded = 0
	local failed = 0
	for _, file in ipairs(widget_files or {}) do
		if load_widget_file(widget_dir, file, registry, log) then
			loaded = loaded + 1
		else
			failed = failed + 1
		end
	end
	return loaded, failed
end

return M
