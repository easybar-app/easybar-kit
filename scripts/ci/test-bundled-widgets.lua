-- Runs startup and behavior regression checks for bundled Lua widgets.
-- The install manifest is the source of truth for selectable widget entrypoints.

local root = assert(arg[1], "repository root argument is required")
local manifest_path = arg[2] or (root .. "/widgets/install-manifest.csv")
local manifest = assert(io.open(manifest_path, "r"))
local widget_files = {}
local widget_paths = {}
local line_number = 0

for raw_line in manifest:lines() do
	line_number = line_number + 1
	local line = raw_line:gsub("\r$", "")
	if line ~= "" and not line:match("^%s*#") then
		local entrypoint, dependencies, extra = line:match("^([^;]+);([^;]*)(.*)$")
		assert(entrypoint ~= nil, "invalid widget manifest line " .. tostring(line_number))
		assert(extra == "", "widget manifest line " .. tostring(line_number) .. " must contain exactly two fields")
		assert(dependencies ~= nil)

		local path = root .. "/widgets/" .. entrypoint
		local file = assert(io.open(path, "r"), "missing widget entrypoint: " .. entrypoint)
		file:close()
		widget_files[#widget_files + 1] = path

		local service = entrypoint:match("^inbox/([^/]+)/widget%.lua$")
		if service ~= nil then
			widget_paths[service .. "-inbox.lua"] = path
		end
	end
end
manifest:close()

assert(#widget_files > 0, "widget manifest contains no selectable entrypoints")

-- Bundled widget startup smoke checks.
do
	package.path = table.concat({
		root .. "/Sources/EasyBarApp/Lua/?.lua",
		root .. "/widgets/?.lua",
		root .. "/widgets/?/init.lua",
		root .. "/widgets/shared/?.lua",
		root .. "/widgets/shared/?/init.lua",
		root .. "/widgets/lib/?.lua",
		root .. "/widgets/lib/?/init.lua",
		root .. "/Sources/EasyBarApp/Lua/?/init.lua",
		package.path,
	}, ";")

	local all_ids = {}
	local ids_by_widget = {}
	local nodes_by_widget = {}
	local commands_by_widget = {}
	local command_callbacks_by_widget = {}

	local function widget_name(path)
		path = tostring(path):gsub("\\", "/")
		local inbox_service = path:match("/inbox/([^/]+)/widget%.lua$")
		if inbox_service ~= nil then
			return inbox_service .. "-inbox"
		end

		local package_name = path:match("/([^/]+)/widget%.lua$")
		if package_name ~= nil then
			return package_name
		end

		local file = path:match("([^/]+)$") or path
		return file:gsub("%.lua$", "")
	end

	local function callable_noop(extra)
		return setmetatable(extra or {}, {
			__call = function() end,
		})
	end

	local function make_file_logger()
		return callable_noop({
			append = function()
				return true, nil
			end,
			line = function()
				return true, nil
			end,
			tail = function()
				return ""
			end,
			trim = function()
				return true, nil
			end,
		})
	end

	local function make_log_api()
		return callable_noop({
			with_prefix = function()
				return callable_noop()
			end,
			with_file = function()
				return make_file_logger()
			end,
		})
	end

	local function make_node(id, props)
		local node = {
			id = id,
			name = id,
			props = props or {},
			subscriptions = {},
		}

		function node:set(next_props)
			self.props = next_props or {}
		end

		function node:get()
			return self.props
		end

		function node:subscribe(events, handler)
			self.subscriptions[#self.subscriptions + 1] = {
				events = events,
				handler = handler,
			}
		end

		function node:remove()
			self.removed = true
		end

		function node:disable()
			self.disabled = true
		end

		function node:unset() end

		return node
	end

	local function make_easybar(widget_name)
		ids_by_widget[widget_name] = {}
		nodes_by_widget[widget_name] = {}
		commands_by_widget[widget_name] = {}
		command_callbacks_by_widget[widget_name] = {}

		local theme_refs = setmetatable({}, {
			__index = function(_, key)
				return "theme." .. tostring(key)
			end,
		})

		local easybar = {
			kind = {
				item = "item",
				row = "row",
				column = "column",
				group = "group",
				popup = "popup",
				slider = "slider",
				progress = "progress",
				progress_slider = "progress_slider",
				sparkline = "sparkline",
				spaces = "spaces",
			},
			level = {
				trace = "trace",
				debug = "debug",
				info = "info",
				warn = "warn",
				error = "error",
			},
			theme = {
				ref = theme_refs,
				colors = theme_refs,
			},
			events = {
				forced = "forced",
				system_woke = "system_woke",
				session_active = "session_active",
				network_change = "network_change",
				wifi_change = "wifi_change",
				mouse = {
					entered = "mouse.entered",
					exited = "mouse.exited",
					clicked = "mouse.clicked",
					left_button = "left",
				},
				context_menu = {
					clicked = "context_menu.clicked",
				},
			},
			json = {
				decode = function(value)
					if value == "[]" then
						return {}
					end
					return {}
				end,
			},
			log = make_log_api(),
			inbox = {
				configure = function() end,
				replace = function() end,
				clear = function() end,
				on_action = function() end,
				on_context_action = function() end,
			},
			storage = {
				get = function(_, _, default)
					return default
				end,
				set = function()
					return true, nil
				end,
			},
		}

		function easybar.add(_, id, props)
			assert(type(id) == "string" and id ~= "", widget_name .. " added an invalid node id")
			assert(
				all_ids[id] == nil,
				widget_name .. " duplicated node id '" .. id .. "' first owned by " .. tostring(all_ids[id])
			)
			all_ids[id] = widget_name
			ids_by_widget[widget_name][id] = (ids_by_widget[widget_name][id] or 0) + 1
			local node = make_node(id, props)
			nodes_by_widget[widget_name][id] = node
			return node
		end

		function easybar.default() end

		function easybar.asset(path)
			path = tostring(path)
			if path:sub(1, 2) == "@/" then
				path = path:sub(3)
			end
			return root .. "/widgets/" .. path
		end

		function easybar.after()
			return {
				cancel = function() end,
			}
		end

		function easybar.cancel_async() end

		function easybar.spawn_async(command, _, callback)
			commands_by_widget[widget_name][#commands_by_widget[widget_name] + 1] = command
			local operation = {
				cancel = function() end,
			}
			if type(callback) == "function" then
				if widget_name == "tailscale" then
					command_callbacks_by_widget[widget_name][#command_callbacks_by_widget[widget_name] + 1] = callback
				else
					callback("smoke-test command disabled", 1)
				end
			end
			return operation
		end

		easybar.exec_async = easybar.spawn_async

		return easybar
	end

	local function command_contains(command, token)
		if type(command) == "string" then
			return command == token or command:find(token, 1, true) ~= nil
		end
		if type(command) ~= "table" then
			return false
		end
		for _, value in ipairs(command) do
			if tostring(value) == token then
				return true
			end
		end
		return false
	end

	local function assert_service_identity(widget_name, required_command, forbidden_command)
		local commands = commands_by_widget[widget_name] or {}
		local found_required = false

		for _, command in ipairs(commands) do
			found_required = found_required or command_contains(command, required_command)
			assert(
				not command_contains(command, forbidden_command),
				widget_name .. " unexpectedly invokes " .. forbidden_command
			)
		end

		assert(found_required, widget_name .. " did not invoke " .. required_command .. " during startup")
	end

	local function assert_expected_ids(widget_name, expected)
		local actual = ids_by_widget[widget_name] or {}
		for _, id in ipairs(expected) do
			assert(actual[id] == 1, widget_name .. " must create node '" .. id .. "' exactly once")
		end

		local actual_count = 0
		for _ in pairs(actual) do
			actual_count = actual_count + 1
		end
		assert(actual_count == #expected, widget_name .. " created an unexpected number of nodes")
	end

	local function expected_rows(root_id, header_id, row_prefix, footer_id)
		local expected = { root_id, header_id, footer_id }
		for index = 1, 8 do
			expected[#expected + 1] = row_prefix .. tostring(index)
		end
		return expected
	end

	local function assert_registry_rejects_duplicate_ids()
		local registry_module = assert(loadfile(root .. "/Sources/EasyBarApp/Lua/easybar/registry.lua"))()
		local registry = registry_module.new()
		registry.add("item", "duplicate_smoke_id", {})

		local ok, duplicate_error = pcall(function()
			registry.add("item", "duplicate_smoke_id", {})
		end)
		assert(not ok, "Lua registry accepted a duplicate node id")
		assert(
			tostring(duplicate_error):find("easybar item already exists: duplicate_smoke_id", 1, true) ~= nil,
			"Lua registry returned an unexpected duplicate-id error: " .. tostring(duplicate_error)
		)
	end

	for _, widget_path in ipairs(widget_files) do
		local source_name = widget_name(widget_path)
		local environment = setmetatable({
			easybar = make_easybar(source_name),
		}, {
			__index = _G,
		})

		local chunk, load_error = loadfile(widget_path, "t", environment)
		assert(chunk, source_name .. " failed to load: " .. tostring(load_error))

		local ok, runtime_error = pcall(chunk)
		assert(ok, source_name .. " failed during startup: " .. tostring(runtime_error))
	end

	assert_service_identity("github", "gh", "glab")
	assert_service_identity("gitlab", "glab", "gh")
	assert_expected_ids(
		"github",
		expected_rows(
			"github_notifications",
			"github_notifications_header",
			"github_notification_",
			"github_notifications_footer"
		)
	)
	assert_expected_ids(
		"gitlab",
		expected_rows("gitlab_work_items", "gitlab_work_items_header", "gitlab_work_item_", "gitlab_work_items_footer")
	)

	-- Bursts of replayed state events should not launch redundant concurrent status reads.
	do
		local widget_name = "tailscale"
		local node = assert(nodes_by_widget[widget_name].tailscale_icon)
		assert(#commands_by_widget[widget_name] == 1, "tailscale must start one initial status read")
		for _, subscription in ipairs(node.subscriptions) do
			if type(subscription.events) == "table" then
				subscription.handler()
				subscription.handler()
			end
		end
		assert(#commands_by_widget[widget_name] == 1, "tailscale started overlapping status reads")
		command_callbacks_by_widget[widget_name][1]("{}", 0)
		assert(#commands_by_widget[widget_name] == 2, "tailscale did not run one coalesced follow-up read")
	end

	assert_registry_rejects_duplicate_ids()

	print("Bundled Lua widget smoke test passed for " .. tostring(#widget_files) .. " files")
end

-- Bundled inbox behavior checks.
do
	package.path = table.concat({
		root .. "/Sources/EasyBarApp/Lua/?.lua",
		root .. "/widgets/?.lua",
		root .. "/widgets/?/init.lua",
		root .. "/widgets/shared/?.lua",
		root .. "/widgets/shared/?/init.lua",
		root .. "/widgets/lib/?.lua",
		root .. "/widgets/lib/?/init.lua",
		root .. "/Sources/EasyBarApp/Lua/?/init.lua",
		package.path,
	}, ";")

	local json = require("easybar.json")
	local inbox = require("inbox")

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

	local function make_host()
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
			return root .. "/widgets/" .. path
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
		local item = assert(state:item("thread-1"), "GitHub notification must be published")
		assert(item.url == "https://github.com/easybar/easybar/pull/1", "GitHub notification must use the native URL field")
		assert(item.timestamp == inbox.timestamp("2026-08-03T09:45:00Z"), "GitHub notification must publish updated_at")
		assert(
			not state:item_has_action("thread-1", "open"),
			"GitHub notification must not duplicate the native Open action"
		)

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

	local function test_github_merge_method_setting_persists_and_drives_merge()
		local state = load_widget("github-inbox.lua")
		assert(
			assert(state:source_action("merge_method:squash")).title == "✓ Squash and merge",
			"GitHub must mark the default squash method in source actions"
		)
		assert(
			assert(state:source_action("merge_confirmation:immediate")).title == "✓ Merge immediately",
			"GitHub must merge immediately by default"
		)

		state.context_action_handler({ action_id = "merge_confirmation:required" })
		assert(state.storage_values["github-inbox:confirm_merge"] == true, "GitHub must persist required confirmation")
		assert(
			assert(state:source_action("merge_confirmation:required")).title == "✓ Require confirmation",
			"GitHub must immediately mark the persisted confirmation mode"
		)

		state.context_action_handler({ action_id = "merge_method:rebase" })
		assert(
			state.storage_values["github-inbox:merge_method"] == "rebase",
			"GitHub must persist the selected merge method"
		)
		assert(
			assert(state:source_action("merge_method:rebase")).title == "✓ Rebase and merge",
			"GitHub must immediately mark the persisted merge method"
		)

		state:run_next_timer()
		state:complete_next_command("github-one", 0)
		state.action_handler({ action_id = "prepare_merge", target_widget_id = "thread-1" })
		state:complete_next_command("github-pr-ready", 0)
		assert(state:item_has_action("thread-1", "confirm_merge"), "ready pull requests must expose merge confirmation")

		state.action_handler({ action_id = "confirm_merge", target_widget_id = "thread-1" })
		local merge_command = assert(state.commands[1], "GitHub must start a merge command").command
		local has_rebase = false
		local has_squash = false
		for _, argument in ipairs(merge_command) do
			has_rebase = has_rebase or argument == "--rebase"
			has_squash = has_squash or argument == "--squash"
		end
		assert(has_rebase, "GitHub merge command must use the persisted rebase method")
		assert(not has_squash, "GitHub merge command must not retain the previous squash method")
	end

	local function test_github_merge_confirmation_defaults_to_immediate()
		local state = load_widget("github-inbox.lua")
		assert(
			assert(state:source_action("merge_confirmation:immediate")).title == "✓ Merge immediately",
			"GitHub must immediately mark the persisted confirmation mode"
		)

		state:run_next_timer()
		state:complete_next_command("github-one", 0)
		state.action_handler({ action_id = "prepare_merge", target_widget_id = "thread-1" })
		state:complete_next_command("github-pr-ready", 0)
		assert(
			state:item_action_is_busy("thread-1", "confirm_merge"),
			"GitHub immediate mode must start merging without a confirmation action"
		)
		local merge_command = assert(state.commands[1], "GitHub immediate mode must start a merge command").command
		local arguments = {}
		for _, argument in ipairs(merge_command) do
			arguments[argument] = true
		end
		assert(arguments["merge"], "GitHub immediate mode must execute gh pr merge after inspection")
		assert(arguments["--match-head-commit"], "GitHub immediate mode must retain the inspected head guard")
		assert(arguments["0123456789abcdef"], "GitHub immediate mode must merge the inspected head commit")
	end

	local function test_gitlab_merge_method_setting_persists_and_drives_merge()
		local state = load_widget("gitlab-inbox.lua")
		assert(
			assert(state:source_action("merge_method:merge")).title == "✓ Project default",
			"GitLab must mark the project-default merge method in source actions"
		)
		assert(
			assert(state:source_action("merge_confirmation:immediate")).title == "✓ Merge immediately",
			"GitLab must merge immediately by default"
		)

		state.context_action_handler({ action_id = "merge_confirmation:required" })
		assert(state.storage_values["gitlab-inbox:confirm_merge"] == true, "GitLab must persist required confirmation")
		assert(
			assert(state:source_action("merge_confirmation:required")).title == "✓ Require confirmation",
			"GitLab must immediately mark the persisted confirmation mode"
		)

		state.context_action_handler({ action_id = "merge_method:rebase" })
		assert(
			state.storage_values["gitlab-inbox:merge_method"] == "rebase",
			"GitLab must persist the selected merge method"
		)
		assert(
			assert(state:source_action("merge_method:rebase")).title == "✓ Rebase and merge",
			"GitLab must immediately mark the persisted merge method"
		)

		state:run_next_timer()
		state:complete_next_command("gitlab-issues", 0)
		state:complete_next_command("gitlab-merge-requests", 0)
		assert(state:item_has_action("merge_request:2", "prepare_merge"), "GitLab merge requests must expose merge")

		state.action_handler({ action_id = "prepare_merge", target_widget_id = "merge_request:2" })
		local inspect_command = assert(state.commands[1], "GitLab must inspect the merge request before merging").command
		assert(
			inspect_command[#inspect_command] == "projects/123/merge_requests/2?with_merge_status_recheck=true",
			"GitLab must inspect the exact project and merge request"
		)
		state:complete_next_command("gitlab-mr-ready", 0)
		assert(state:item_has_action("merge_request:2", "confirm_merge"), "ready merge requests must expose confirmation")

		state.action_handler({ action_id = "confirm_merge", target_widget_id = "merge_request:2" })
		local merge_command = assert(state.commands[1], "GitLab must start a merge command").command
		local arguments = {}
		for _, argument in ipairs(merge_command) do
			arguments[argument] = true
		end
		assert(arguments["--rebase"], "GitLab merge command must use the persisted rebase method")
		assert(not arguments["--squash"], "GitLab merge command must not use the previous method")
		assert(arguments["--auto-merge=false"], "GitLab merge command must not silently enable auto-merge")
		assert(arguments["--yes"], "GitLab merge command must disable the interactive confirmation prompt")
		assert(arguments["--sha"], "GitLab merge command must guard the reviewed source commit")
		assert(arguments["fedcba9876543210"], "GitLab merge command must match the inspected head commit")
		assert(arguments["https://gitlab.com/easybar/easybar"], "GitLab merge command must target the source project")
	end

	local function test_gitlab_merge_confirmation_defaults_to_immediate()
		local state = load_widget("gitlab-inbox.lua")
		assert(
			assert(state:source_action("merge_confirmation:immediate")).title == "✓ Merge immediately",
			"GitLab must immediately mark the persisted confirmation mode"
		)

		state:run_next_timer()
		state:complete_next_command("gitlab-issues", 0)
		state:complete_next_command("gitlab-merge-requests", 0)
		state.action_handler({ action_id = "prepare_merge", target_widget_id = "merge_request:2" })
		state:complete_next_command("gitlab-mr-ready", 0)
		assert(
			state:item_action_is_busy("merge_request:2", "confirm_merge"),
			"GitLab immediate mode must start merging without a confirmation action"
		)
		local merge_command = assert(state.commands[1], "GitLab immediate mode must start a merge command").command
		local arguments = {}
		for _, argument in ipairs(merge_command) do
			arguments[argument] = true
		end
		assert(arguments["merge"], "GitLab immediate mode must execute glab mr merge after inspection")
		assert(arguments["--sha"], "GitLab immediate mode must retain the inspected SHA guard")
		assert(arguments["fedcba9876543210"], "GitLab immediate mode must merge the inspected head commit")
	end

	local function test_gitlab_mark_read_stays_local()
		local state = load_widget("gitlab-inbox.lua")
		state:run_next_timer()
		assert(state:has_busy_source_action(), "GitLab startup refresh must show source activity")
		state:complete_next_command("gitlab-issues", 0)
		state:complete_next_command("gitlab-merge-requests", 0)
		assert(not state:has_busy_source_action(), "GitLab source activity must end after refresh")
		assert(state.items[1].id == "merge_request:2", "GitLab work items must merge by updated_at")
		local item = assert(state:item("issue:1"), "GitLab issue must be published")
		assert(item.url == "https://gitlab.com/easybar/easybar/-/issues/1", "GitLab issue must use the native URL field")
		assert(item.timestamp == inbox.timestamp("2026-08-03T09:45:00.123+00:00"), "GitLab issue must publish updated_at")
		assert(not state:item_has_action("issue:1", "open"), "GitLab issue must not duplicate the native Open action")

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

	local function test_github_overlapping_mutations_coalesce_refresh()
		local state = load_widget("github-inbox.lua")
		state:run_next_timer()
		state:complete_next_command("github-two", 0)

		state.action_handler({ action_id = "mark_read", target_widget_id = "thread-1" })
		state.action_handler({ action_id = "mark_read", target_widget_id = "thread-2" })
		assert(#state.commands == 2, "GitHub mutations must be allowed to overlap across items")

		state:complete_command(1, "", 0)
		assert(#state.commands == 2, "first GitHub mutation must start its refresh")
		state:complete_command(1, "", 0)
		assert(#state.commands == 1, "second GitHub mutation must queue behind the active refresh")
		assert(state:item_action_is_busy("thread-2", "mark_read"), "queued GitHub mutation must remain visibly busy")

		state:complete_next_command("github-second", 0)
		assert(#state.commands == 1, "queued GitHub mutation must start a follow-up refresh")
		assert(state:item_action_is_busy("thread-2", "mark_read"), "queued item must stay busy through the first refresh")
		state:complete_next_command("github-empty", 0)
		assert(state:item("thread-2") == nil, "follow-up refresh must observe the second mutation")
	end

	local function test_remote_errors_retain_snapshots()
		local github = load_widget("github-inbox.lua")
		github:run_next_timer()
		github:complete_next_command("github-one", 0)
		github.context_action_handler({ action_id = "refresh" })
		github:complete_next_command(string.rep("x", 20000), 1)
		assert(github:item("thread-1") ~= nil, "GitHub refresh errors must retain the last good snapshot")
		assert(github.items[1].id == "error", "GitHub errors must be published before capped snapshot items")
		assert(utf8.len(assert(github:item("error")).body) <= inbox.maximum_error_length, "GitHub errors must be bounded")

		github.context_action_handler({ action_id = "refresh" })
		github:complete_next_command("github-object", 0)
		assert(github:item("thread-1") ~= nil, "GitHub malformed responses must retain the last good snapshot")
		assert(github:item("error") ~= nil, "GitHub malformed responses must publish an error")

		local gitlab = load_widget("gitlab-inbox.lua")
		gitlab:run_next_timer()
		gitlab:complete_next_command("gitlab-issues", 0)
		gitlab:complete_next_command("gitlab-empty", 0)
		gitlab.context_action_handler({ action_id = "refresh" })
		gitlab:complete_next_command(string.rep("y", 20000), 1)
		assert(gitlab:item("issue:1") ~= nil, "GitLab refresh errors must retain the last good snapshot")
		assert(gitlab.items[1].id == "error", "GitLab errors must be published before capped snapshot items")
		assert(utf8.len(assert(gitlab:item("error")).body) <= inbox.maximum_error_length, "GitLab errors must be bounded")

		gitlab.context_action_handler({ action_id = "refresh" })
		gitlab:complete_next_command("gitlab-object", 0)
		assert(gitlab:item("issue:1") ~= nil, "GitLab malformed responses must retain the last good snapshot")
		assert(gitlab:item("error") ~= nil, "GitLab malformed responses must publish an error")
	end

	local function test_brew_parser_retains_snapshot_and_handles_warning_braces()
		local state = load_widget("brew-inbox.lua")
		state:run_next_timer()
		state:complete_next_command('{"scenario":"brew-one"}', 0)
		state:run_next_timer()

		state.context_action_handler({ action_id = "refresh" })
		state:complete_next_command('{"scenario":"brew-malformed"}', 0)
		state:run_next_timer()
		assert(state:item("formula:easybar") ~= nil, "Homebrew malformed responses must retain the last good snapshot")
		assert(state:item("error") ~= nil, "Homebrew malformed responses must publish an error")
		assert(state.items[1].id == "error", "Homebrew errors must be published before capped snapshot items")

		state.context_action_handler({ action_id = "refresh" })
		state:complete_next_command('Warning {details}\n{"scenario":"brew-one"}\nTrailing {hint}', 0)
		state:run_next_timer()
		assert(state:item("formula:easybar") ~= nil, "Homebrew must decode JSON surrounded by brace-containing warnings")
		assert(state:item("warning") ~= nil, "Homebrew must retain surrounding warning output")
		assert(state:item("error") == nil, "a valid Homebrew snapshot must clear the prior error")
	end

	local function test_brew_refresh_cancellation_clears_activity()
		local state = load_widget("brew-inbox.lua")
		state:run_next_timer()
		assert(state:has_busy_source_action(), "Homebrew refresh must start with source activity")
		state.context_action_handler({ action_id = "cancel" })
		assert(state:has_busy_source_action(), "Homebrew cancellation must retain activity during its completion delay")
		state:run_next_timer()
		assert(not state:has_busy_source_action(), "Homebrew cancellation must clear source activity")
	end

	local function test_brew_mutation_cancellation_reconciles_snapshot()
		local state = load_widget("brew-inbox.lua")
		state:run_next_timer()
		state:complete_next_command('{"scenario":"brew-one"}', 0)
		state:run_next_timer()

		state.action_handler({ action_id = "upgrade", target_widget_id = "formula:easybar" })
		state.context_action_handler({ action_id = "cancel" })
		assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew cancellation must stay inline")
		assert(not state:has_busy_source_action(), "Homebrew item cancellation must not show source activity")

		state:complete_next_command("", 130)
		state:run_next_timer()
		assert(#state.commands == 1, "Homebrew cancellation must reconcile package state")
		assert(state:item_action_is_busy("formula:easybar", "upgrade"), "Homebrew reconciliation must stay inline")
		state:complete_next_command('{"scenario":"brew-one"}', 0)
		state:run_next_timer()
		assert(
			not state:item_action_is_busy("formula:easybar", "upgrade"),
			"Homebrew reconciliation must finish inline activity"
		)
	end

	local function test_demo_activity()
		local state = load_widget("demo-inbox.lua")
		assert(#state.items == 0, "Inbox demo must start without publishing messages")
		assert(state:source_action("refresh") ~= nil, "Inbox demo must expose its add action")
		assert(state:source_action("clear") ~= nil, "Inbox demo must expose its clear action")

		state.context_action_handler({ action_id = "refresh" })
		assert(state:has_busy_source_action(), "Inbox demo refresh must show source activity")
		state:run_next_timer()
		assert(not state:has_busy_source_action(), "Inbox demo refresh must clear source activity")
		assert(#state.items == 10, "Inbox demo refresh must publish the complete snapshot")
		assert(state:item("github-review") ~= nil, "Inbox demo must publish the review item")

		state.action_handler({ action_id = "dismiss", target_widget_id = "github-review" })
		assert(state:item_action_is_busy("github-review", "dismiss"), "Inbox demo dismiss must show item activity")
		state:run_next_timer()
		assert(state:item("github-review") == nil, "Inbox demo dismiss must remove the selected item")

		state.context_action_handler({ action_id = "clear" })
		assert(#state.items == 0, "Inbox demo clear must remove the snapshot")
	end

	local function test_inbox_timestamp_parser()
		assert(inbox.decode_array(json, "[]") ~= nil, "JSON arrays must decode")
		assert(inbox.decode_array(json, "{}") == nil, "JSON objects must not be accepted as arrays")
		assert(inbox.timestamp("1970-01-01T00:00:00Z") == 0, "UTC epoch timestamp must parse")
		assert(inbox.timestamp("1970-01-01T01:00:00+01:00") == 0, "positive timezone offset must parse")
		assert(inbox.timestamp("1969-12-31T19:00:00-0500") == 0, "compact negative timezone offset must parse")
		assert(inbox.timestamp("2000-02-29T12:34:56.789Z") ~= nil, "fractional leap-day timestamp must parse")
		assert(inbox.timestamp("2026-02-29T00:00:00Z") == nil, "invalid calendar dates must be rejected")
		assert(inbox.timestamp("2026-08-03T09:45:00") == nil, "timestamps without a timezone must be rejected")
	end

	local expected_widgets = {
		["demo-inbox.lua"] = true,
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

	test_demo_activity()
	test_github_item_refresh_stays_inline()
	test_github_merge_method_setting_persists_and_drives_merge()
	test_github_merge_confirmation_defaults_to_immediate()
	test_gitlab_merge_method_setting_persists_and_drives_merge()
	test_gitlab_merge_confirmation_defaults_to_immediate()
	test_gitlab_mark_read_stays_local()
	test_brew_item_refresh_stays_inline()
	test_github_overlapping_mutations_coalesce_refresh()
	test_remote_errors_retain_snapshots()
	test_brew_parser_retains_snapshot_and_handles_warning_braces()
	test_brew_refresh_cancellation_clears_activity()
	test_brew_mutation_cancellation_reconciles_snapshot()
	test_inbox_timestamp_parser()

	print("Inbox widget regression checks passed")
end

print("Bundled Lua widget regression checks passed")
