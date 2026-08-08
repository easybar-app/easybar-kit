-- Shared host and fixtures for native-inbox widget regression tests.

local M = {}
local configured_root
local json

local function configure(root)
	if configured_root == root then
		return
	end

	package.path = table.concat({
		root .. "/Sources/EasyBarApp/Lua/?.lua",
		root .. "/examples/?.lua",
		root .. "/examples/?/init.lua",
		root .. "/examples/lib/?.lua",
		root .. "/examples/lib/?/init.lua",
		root .. "/Sources/EasyBarApp/Lua/?/init.lua",
		package.path,
	}, ";")

	json = require("easybar.json")
	configured_root = root
end

local function github_notification(id, title, updated_at)
	return json.object({
		id = id,
		reason = "mention",
		updated_at = updated_at,
		repository = json.object({
			full_name = "easybar/easybar",
			html_url = "https://github.com/easybar/easybar",
		}),
		subject = json.object({
			title = title,
			type = "PullRequest",
			url = "https://api.github.com/repos/easybar/easybar/pulls/1",
		}),
	})
end

local function gitlab_issue(id)
	return json.object({
		id = id,
		iid = id,
		title = "Assigned issue " .. tostring(id),
		updated_at = "2026-08-03T09:45:00.123+00:00",
		references = json.object({ full = "easybar/easybar#" .. tostring(id) }),
		web_url = "https://gitlab.com/easybar/easybar/-/issues/" .. tostring(id),
	})
end

local function gitlab_merge_request(id)
	return json.object({
		id = id,
		iid = id,
		project_id = 123,
		title = "Assigned merge request " .. tostring(id),
		updated_at = "2026-08-03T09:46:00Z",
		references = json.object({ full = "easybar/easybar!" .. tostring(id) }),
		web_url = "https://gitlab.com/easybar/easybar/-/merge_requests/" .. tostring(id),
	})
end

local function callable_noop()
	return setmetatable({}, { __call = function() end })
end

local function decoded_fixture(value)
	if value == "github-one" then
		return json.array({ json.array({ github_notification("thread-1", "Review requested", "2026-08-03T09:45:00Z") }) })
	elseif value == "github-two" then
		return json.array({
			json.array({
				github_notification("thread-1", "First review", "2026-08-03T09:45:00Z"),
				github_notification("thread-2", "Second review", "2026-08-03T09:46:00Z"),
			}),
		})
	elseif value == "github-second" then
		return json.array({ json.array({ github_notification("thread-2", "Second review", "2026-08-03T09:46:00Z") }) })
	elseif value == "github-empty" then
		return json.array({ json.array({}) })
	elseif value == "github-object" then
		return json.object({ message = "not an array" })
	elseif value == "github-pr-ready" then
		return json.object({
			state = "OPEN",
			isDraft = false,
			mergeable = "MERGEABLE",
			mergeStateStatus = "CLEAN",
			reviewDecision = "APPROVED",
			headRefOid = "0123456789abcdef",
		})
	elseif value == "gitlab-issues" then
		return json.array({ gitlab_issue(1) })
	elseif value == "gitlab-merge-requests" then
		return json.array({ gitlab_merge_request(2) })
	elseif value == "gitlab-mr-ready" then
		return json.object({
			state = "opened",
			draft = false,
			detailed_merge_status = "mergeable",
			sha = "fedcba9876543210",
		})
	elseif value == "gitlab-empty" then
		return json.array({})
	elseif value == "gitlab-object" then
		return json.object({ message = "not an array" })
	elseif value:find("brew%-one", 1, false) ~= nil then
		return json.object({
			formulae = json.array({
				json.object({
					name = "easybar",
					installed_versions = json.array({ "1.0.0" }),
					current_version = "1.1.0",
					pinned = false,
				}),
			}),
			casks = json.array({}),
		})
	elseif value:find("brew%-empty", 1, false) ~= nil then
		return json.object({ formulae = json.array({}), casks = json.array({}) })
	elseif value:find("brew%-malformed", 1, false) ~= nil then
		return json.object({ formulae = json.object({}) })
	end

	error("unexpected JSON fixture: " .. tostring(value))
end

local function make_host(root)
	local state = {
		configuration = nil,
		items = {},
		action_handler = nil,
		context_action_handler = nil,
		commands = {},
		timers = {},
		storage_values = {},
		next_token = 0,
	}

	local inbox = {}
	function inbox.configure(_, configuration)
		state.configuration = configuration
	end
	function inbox.replace(_, items)
		state.items = items
	end
	function inbox.clear()
		state.items = {}
	end
	function inbox.on_action(_, handler)
		state.action_handler = handler
	end
	function inbox.on_context_action(_, handler)
		state.context_action_handler = handler
	end

	local easybar = {
		kind = { item = "item" },
		level = { trace = "trace", debug = "debug", info = "info", warn = "warn", error = "error" },
		events = {
			forced = "forced",
			system_woke = "system_woke",
			session_active = "session_active",
		},
		json = { decode = decoded_fixture, is_array = json.is_array, null = json.null },
		log = callable_noop(),
		inbox = inbox,
		storage = {
			get = function(widget, key, default)
				local value = state.storage_values[widget .. ":" .. key]
				return value == nil and default or value
			end,
			set = function(widget, key, value)
				state.storage_values[widget .. ":" .. key] = value
				return true, nil
			end,
		},
	}

	function easybar.asset(path)
		path = tostring(path)
		if path:sub(1, 2) == "@/" then
			path = path:sub(3)
		end
		return root .. "/examples/" .. path
	end

	function easybar.add()
		return { subscribe = function() end }
	end

	function easybar.after(delay, callback)
		local timer = { delay = delay, callback = callback, cancelled = false }
		function timer:cancel()
			self.cancelled = true
		end
		state.timers[#state.timers + 1] = timer
		return timer
	end

	function easybar.spawn_async(command, options, callback)
		state.next_token = state.next_token + 1
		local token = "command-" .. tostring(state.next_token)
		state.commands[#state.commands + 1] = {
			token = token,
			command = command,
			options = options,
			callback = callback,
		}
		return token
	end

	function easybar.cancel_async()
		return true
	end

	function state:run_next_timer()
		while #self.timers > 0 do
			local timer = table.remove(self.timers, 1)
			if not timer.cancelled then
				timer.callback()
				return
			end
		end
		error("expected a pending timer")
	end

	function state:complete_next_command(output, code)
		return self:complete_command(1, output, code)
	end

	function state:complete_command(index, output, code)
		local command = table.remove(self.commands, index)
		assert(command ~= nil, "expected a pending command")
		command.callback(output, code, { duration_ms = 1 })
		return command
	end

	function state:has_busy_source_action()
		for _, action in ipairs((self.configuration or {}).actions or {}) do
			if action.busy == true then
				return true
			end
		end
		return false
	end

	function state:item(id)
		for _, item in ipairs(self.items) do
			if item.id == id then
				return item
			end
		end
		return nil
	end

	function state:item_action_is_busy(item_id, action_id)
		local item = self:item(item_id)
		if item == nil then
			return false
		end
		for _, action in ipairs(item.actions or {}) do
			if action.id == action_id then
				return action.busy == true
			end
		end
		return false
	end

	function state:item_has_action(item_id, action_id)
		local item = self:item(item_id)
		for _, action in ipairs(item and item.actions or {}) do
			if action.id == action_id then
				return true
			end
		end
		return false
	end

	function state:source_action(action_id)
		for _, action in ipairs((self.configuration or {}).actions or {}) do
			if action.id == action_id then
				return action
			end
		end
		return nil
	end

	return easybar, state
end

function M.load(root, entrypoint)
	configure(root)
	local easybar, state = make_host(root)
	local path = root .. "/examples/" .. entrypoint
	local environment = setmetatable({ easybar = easybar }, { __index = _G })
	local chunk, load_error = loadfile(path, "t", environment)
	assert(chunk, entrypoint .. " failed to load: " .. tostring(load_error))
	local ok, runtime_error = pcall(chunk)
	assert(ok, entrypoint .. " failed during startup: " .. tostring(runtime_error))
	return state
end

return M
