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

--- Adds the shared-module search paths exposed by one widget root.
---@param widget_dir string Root directory containing the `shared/` module namespace.
local function configure_shared_module_paths(widget_dir)
	-- Prepend lower-priority paths first because each call inserts at the front.
	prepend_package_path(widget_dir .. "/shared/?/init.lua")
	prepend_package_path(widget_dir .. "/shared/?.lua")
end

--- Adds manual root-local module paths plus the shared module namespace.
---@param widget_dir string Root directory containing manually managed widgets and modules.
local function configure_widget_module_paths(widget_dir)
	configure_shared_module_paths(widget_dir)
	prepend_package_path(widget_dir .. "/?/init.lua")
	prepend_package_path(widget_dir .. "/?.lua")
end

--- Creates an isolated widget environment with a source-scoped EasyBar API.
---@param registry table Active runtime registry.
---@param source_path string Physical widget entrypoint path.
---@param widget_root string Root directory used for package-root asset resolution.
---@param widget_name? string Stable widget name for structured diagnostics.
---@param diagnostic_source? string Logical widget source retained in node diagnostics.
---@return table environment Widget global environment falling back to standard Lua globals.
local function make_widget_env(registry, source_path, widget_root, widget_name, diagnostic_source)
	local env = {
		easybar = registry.make_widget_api(source_path, widget_root, widget_name, diagnostic_source),
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
---@param source_path string Physical widget entrypoint path.
---@param widget_root string Root directory used by the widget-scoped API.
---@param display_file string Widget label used in loader diagnostics.
---@param registry table Active runtime registry.
---@param log table Runtime logger.
---@param widget_name? string Stable widget name for structured command logs.
---@param diagnostic_source? string Logical source retained in node diagnostics.
---@return boolean loaded Whether the widget committed successfully.
local function load_widget_path(source_path, widget_root, display_file, registry, log, widget_name, diagnostic_source)
	local transaction = registry.begin_widget_load(diagnostic_source or source_path)
	local env = make_widget_env(registry, source_path, widget_root, widget_name, diagnostic_source)
	local chunk, load_err = loadfile(source_path, "t", env)
	if not chunk then
		rollback(registry, transaction, log, display_file, "load", load_err)
		return false
	end

	local ok, err = pcall(chunk)
	if not ok then
		rollback(registry, transaction, log, display_file, "execute", err)
		return false
	end

	local committed, commit_err = pcall(registry.commit_widget_load, transaction)
	if not committed then
		rollback(registry, transaction, log, display_file, "validate", commit_err)
		return false
	end

	log.debug("loader loaded file=" .. display_file)
	return true
end

--- Loads every manually discovered widget while isolating failures to individual transactions.
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
	log.debug("runtime widget_shared=" .. widget_dir .. "/shared")

	local loaded = 0
	local failed = 0
	for _, file in ipairs(widget_files or {}) do
		local source_path = widget_dir .. "/" .. file
		if load_widget_path(source_path, widget_dir, file, registry, log) then
			loaded = loaded + 1
		else
			failed = failed + 1
		end
	end
	return loaded, failed
end

--- Loads explicitly activated managed widget entrypoints from their committed store paths.
---@param active_dir string Managed activation root containing widget and shared-module symlinks.
---@param widgets { name:string, path:string, root:string, activation:string }[] Ordered widget descriptors.
---@param registry table Active runtime registry.
---@param log table Runtime logger.
---@return integer loaded Number of committed widgets.
---@return integer failed Number of rejected widgets.
function M.load_managed_widgets(active_dir, widgets, registry, log)
	log.debug("runtime managed_widget_dir=" .. active_dir)
	configure_shared_module_paths(active_dir)
	log.debug("runtime managed_widget_shared=" .. active_dir .. "/shared")

	local loaded = 0
	local failed = 0
	for _, widget in ipairs(widgets or {}) do
		if load_widget_path(widget.path, widget.root, widget.name, registry, log, widget.name, widget.activation) then
			loaded = loaded + 1
		else
			failed = failed + 1
		end
	end
	return loaded, failed
end

return M
