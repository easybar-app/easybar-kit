--- Module contract:
--- Owns widget discovery paths, isolated environments, and transactional widget startup.
local M = {}

local function prepend_package_path(entry)
	for existing in package.path:gmatch("[^;]+") do
		if existing == entry then
			return
		end
	end
	package.path = entry .. ";" .. package.path
end

local function configure_widget_module_paths(widget_dir)
	-- Prepend lower-priority paths first because each call inserts at the front.
	prepend_package_path(widget_dir .. "/lib/?/init.lua")
	prepend_package_path(widget_dir .. "/lib/?.lua")
	prepend_package_path(widget_dir .. "/shared/?/init.lua")
	prepend_package_path(widget_dir .. "/shared/?.lua")
	prepend_package_path(widget_dir .. "/integrations/?/init.lua")
	prepend_package_path(widget_dir .. "/integrations/?.lua")
end

local function make_widget_env(registry, source_path)
	local env = {
		easybar = registry.make_widget_api(source_path),
	}
	setmetatable(env, { __index = _G })
	return env
end

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

local function load_widget_file(widget_dir, file, registry, log)
	local path = widget_dir .. "/" .. file
	local transaction = registry.begin_widget_load(path)
	local env = make_widget_env(registry, path)
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

function M.load_widgets(widget_dir, widget_files, registry, log)
	log.debug("runtime started")
	log.debug("runtime widget_dir=" .. widget_dir)
	configure_widget_module_paths(widget_dir)
	log.debug("runtime widget_integrations=" .. widget_dir .. "/integrations")
	log.debug("runtime widget_shared=" .. widget_dir .. "/shared")
	log.debug("runtime widget_lib_legacy=" .. widget_dir .. "/lib")

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
