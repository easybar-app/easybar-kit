-- Exercises item mutations in every bundled inbox widget against a controllable host API.

local root = assert(arg[1], "repository root argument is required")
local widget_paths = {}
for index = 2, #arg do
	widget_paths[arg[index]:match("([^/]+)$")] = arg[index]
end

package.path = table.concat({
	root .. "/widgets/lib/?.lua",
	root .. "/widgets/lib/?/init.lua",
	package.path,
}, ";")

local function callable_noop()
	return setmetatable({}, { __call = function() end })
end

local function decoded_fixture(value)
	if value == "github-one" then
		return {
			{
				{
					id = "thread-1",
					reason = "mention",
					repository = { full_name = "easybar/easybar", html_url = "https://github.com/easybar/easybar" },
					subject = {
						title = "Review requested",
						type = "PullRequest",
						url = "https://api.github.com/repos/easybar/easybar/pulls/1",
					},
				},
			},
		}
	elseif value == "github-empty" then
		return {}
	elseif value == "gitlab-issues" then
		return {
			{
				id = 1,
				iid = 1,
				title = "Assigned issue",
				references = { full = "easybar/easybar#1" },
				web_url = "https://gitlab.com/easybar/easybar/-/issues/1",
			},
		}
	elseif value == "gitlab-empty" then
		return {}
	elseif value:find("brew%-one", 1, false) ~= nil then
		return {
			formulae = {
				{
					name = "easybar",
					installed_versions = { "1.0.0" },
					current_version = "1.1.0",
					pinned = false,
				},
			},
			casks = {},
		}
	elseif value:find("brew%-empty", 1, false) ~= nil then
		return { formulae = {}, casks = {} }
	end

	error("unexpected JSON fixture: " .. tostring(value))
end

local function make_host()
	local state = {
		configuration = nil,
		items = {},
		action_handler = nil,
		context_action_handler = nil,
		commands = {},
		timers = {},
		next_token = 0,
	}

	local inbox = {}
	function inbox.configure(_, configuration)
		state.configuration = configuration
	end
	function inbox.replace(_, items)
		state.items = items
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
		json = { decode = decoded_fixture },
		log = callable_noop(),
		inbox = inbox,
	}

	function easybar.asset(path)
		return root .. "/widgets/" .. tostring(path)
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
		local command = table.remove(self.commands, 1)
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

	return easybar, state
end

local function load_widget(name)
	local path = assert(widget_paths[name], "missing bundled inbox widget: " .. name)
	local easybar, state = make_host()
	local environment = setmetatable({ easybar = easybar }, { __index = _G })
	local chunk, load_error = loadfile(path, "t", environment)
	assert(chunk, name .. " failed to load: " .. tostring(load_error))
	local ok, runtime_error = pcall(chunk)
	assert(ok, name .. " failed during startup: " .. tostring(runtime_error))
	return state
end

local function test_github_item_refresh_stays_inline()
	local state = load_widget("github-inbox.lua")
	state:run_next_timer()
	assert(state:has_busy_source_action(), "GitHub startup refresh must show source activity")
	state:complete_next_command("github-one", 0)
	assert(not state:has_busy_source_action(), "GitHub source activity must end after refresh")

	state.action_handler({ action_id = "mark_read", target_widget_id = "thread-1" })
	assert(state:item_action_is_busy("thread-1", "mark_read"), "GitHub item mutation must show inline activity")
	assert(not state:has_busy_source_action(), "GitHub item mutation must not show source activity")

	state:complete_next_command("", 0)
	assert(state:item_action_is_busy("thread-1", "mark_read"), "GitHub post-mutation refresh must stay inline")
	assert(not state:has_busy_source_action(), "GitHub post-mutation refresh must not show source activity")

	state:complete_next_command("github-empty", 0)
	assert(state:item("thread-1") == nil, "GitHub refreshed item must disappear")
	assert(not state:has_busy_source_action(), "GitHub item completion must remain source-idle")
end

local function test_gitlab_mark_read_stays_local()
	local state = load_widget("gitlab-inbox.lua")
	state:run_next_timer()
	assert(state:has_busy_source_action(), "GitLab startup refresh must show source activity")
	state:complete_next_command("gitlab-issues", 0)
	state:complete_next_command("gitlab-empty", 0)
	assert(not state:has_busy_source_action(), "GitLab source activity must end after refresh")

	local command_count = #state.commands
	state.action_handler({ action_id = "mark_read", target_widget_id = "issue:1" })
	assert(#state.commands == command_count, "GitLab local mark-read must not start a refresh")
	assert(not state:has_busy_source_action(), "GitLab local mark-read must not show source activity")
end

local function test_brew_item_refresh_stays_inline()
	local state = load_widget("brew-inbox.lua")
	state:run_next_timer()
	assert(state:has_busy_source_action(), "Homebrew startup refresh must show source activity")
	state:complete_next_command('{"scenario":"brew-one"}', 0)
	state:run_next_timer()
	assert(not state:has_busy_source_action(), "Homebrew source activity must end after refresh")

	state.action_handler({ action_id = "upgrade", target_widget_id = "formula:easybar" })
	assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew upgrade must show inline activity")
	assert(not state:has_busy_source_action(), "Homebrew item mutation must not show source activity")

	state:complete_next_command("", 0)
	state:run_next_timer()
	assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew post-mutation refresh must stay inline")
	assert(not state:has_busy_source_action(), "Homebrew post-mutation refresh must not show source activity")

	state:complete_next_command('{"scenario":"brew-empty"}', 0)
	state:run_next_timer()
	assert(state:item("formula:easybar") == nil, "Homebrew refreshed package must disappear")
	assert(not state:has_busy_source_action(), "Homebrew item completion must remain source-idle")
end

local expected_widgets = {
	["brew-inbox.lua"] = true,
	["github-inbox.lua"] = true,
	["gitlab-inbox.lua"] = true,
}
for name in pairs(widget_paths) do
	assert(expected_widgets[name], "uncovered bundled inbox widget: " .. name)
	expected_widgets[name] = nil
end
for name in pairs(expected_widgets) do
	error("missing bundled inbox widget: " .. name)
end

test_github_item_refresh_stays_inline()
test_gitlab_mark_read_stays_local()
test_brew_item_refresh_stays_inline()

print("inbox widget activity checks passed")
