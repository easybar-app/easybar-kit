-- Publishes representative test data for the native inbox.

local SOURCE = "Inbox demo"
local NOW = os.time()
local DEMO_DELAY_SECONDS = 1.25

---@type EasyBarInboxSourcePresentation
local GITHUB = {
	name = "GitHub",
	icon = easybar.asset("assets/github.svg"),
	color = "#A371F7",
}
---@type EasyBarInboxSourcePresentation
local GITLAB = {
	name = "GitLab",
	icon = easybar.asset("assets/gitlab.svg"),
	color = "#FC6D26",
}
---@type EasyBarInboxSourcePresentation
local HOMEBREW = {
	name = "Homebrew",
	icon = easybar.asset("assets/brew.svg"),
	color = "#FBB040",
}

---@type EasyBarInboxItem[]
local DEMO_ITEMS = {
	{
		id = "github-review",
		title = "Review requested on pull request #482",
		body = "The macOS checks passed and the change is ready for review.",
		timestamp = NOW,
		category = "Pull requests",
		severity = "success",
		unread = true,
		source = GITHUB,
		actions = { { id = "dismiss", title = "Dismiss" } },
	},
	{
		id = "github-security",
		title = "Dependabot found a critical vulnerability",
		body = "`swift-nio` should be upgraded before the next release.",
		format = "markdown",
		timestamp = NOW - 90,
		category = "Security",
		severity = "error",
		unread = true,
		source = GITHUB,
	},
	{
		id = "github-mention",
		title = "You were mentioned in issue #917",
		body = "A question is waiting for your input.",
		timestamp = NOW - 180,
		category = "Issues",
		severity = "info",
		unread = false,
		source = GITHUB,
	},
	{
		id = "gitlab-pipeline",
		title = "Pipeline requires attention",
		body = "The deploy job is waiting for manual approval.",
		timestamp = NOW - 270,
		category = "Pipelines",
		severity = "warning",
		unread = true,
		source = GITLAB,
	},
	{
		id = "gitlab-merge-request",
		title = "Merge request !128 is ready",
		body = "All discussions are resolved and the pipeline passed.",
		timestamp = NOW - 360,
		category = "Merge requests",
		severity = "success",
		unread = true,
		source = GITLAB,
		actions = { { id = "dismiss", title = "Dismiss" } },
	},
	{
		id = "gitlab-issue",
		title = "Issue #73 was assigned to you",
		body = "Investigate the intermittent authentication timeout.",
		timestamp = NOW - 450,
		category = "Issues",
		severity = "info",
		unread = false,
		source = GITLAB,
	},
	{
		id = "brew-outdated",
		title = "Three packages can be upgraded",
		body = "formulae: lua, swiftformat · casks: visual-studio-code",
		timestamp = NOW - 540,
		category = "Packages",
		severity = "info",
		unread = false,
		source = HOMEBREW,
		actions = { { id = "dismiss", title = "Dismiss" } },
	},
	{
		id = "brew-pinned",
		title = "Pinned formula was not upgraded",
		body = "postgresql@16 remains on 16.3.",
		timestamp = NOW - 630,
		category = "Formulae",
		severity = "warning",
		unread = true,
		source = HOMEBREW,
	},
	{
		id = "brew-error",
		title = "Could not refresh package metadata",
		body = "Homebrew could not reach the package registry.",
		timestamp = NOW - 720,
		category = "Updates",
		severity = "error",
		unread = true,
		source = HOMEBREW,
	},
}

---@type EasyBarInboxItem[]
local items = {}
local source_busy = false
local busy_item_id = nil

local function copy_actions(actions)
	local copy = {}
	for _, action in ipairs(actions or {}) do
		copy[#copy + 1] = {
			id = action.id,
			title = action.title,
		}
	end
	return copy
end

local function copy_item(item)
	return {
		id = item.id,
		title = item.title,
		body = item.body,
		format = item.format,
		timestamp = item.timestamp,
		category = item.category,
		severity = item.severity,
		unread = item.unread,
		dismissible = item.dismissible,
		source = item.source,
		url = item.url,
		actions = copy_actions(item.actions),
	}
end

local function configure_source_actions()
	local actions
	if source_busy then
		actions = {
			{ id = "activity", title = "Refreshing demo…", enabled = false, busy = true },
		}
	else
		actions = {
			{ id = "refresh", title = "Refresh" },
			{ id = "clear", title = "Clear demo" },
		}
	end
	easybar.inbox.configure(SOURCE, { actions = actions })
end

---Restores a fresh mutable snapshot from the immutable demo templates.
local function reset_items()
	items = {}
	for _, item in ipairs(DEMO_ITEMS) do
		items[#items + 1] = copy_item(item)
	end
end

---Publishes the current demo snapshot without affecting real inbox sources.
local function publish()
	local snapshot = {}
	for _, item in ipairs(items) do
		local published = copy_item(item)
		if published.id == busy_item_id then
			published.actions = {
				{ id = "dismiss", title = "Dismissing…", enabled = false, busy = true },
			}
		end
		snapshot[#snapshot + 1] = published
	end
	easybar.inbox.replace(SOURCE, snapshot)
end

---Removes one demo item after showing an item-scoped activity spinner.
---@param event EasyBarInboxActionEvent
local function handle_action(event)
	if event.action_id ~= "dismiss" or busy_item_id ~= nil then
		return
	end

	busy_item_id = event.target_widget_id
	publish()

	easybar.after(DEMO_DELAY_SECONDS, function()
		for index = #items, 1, -1 do
			if items[index].id == busy_item_id then
				table.remove(items, index)
				break
			end
		end
		busy_item_id = nil
		publish()
	end)
end

easybar.inbox.on_action(SOURCE, handle_action)
configure_source_actions()

easybar.inbox.on_context_action(SOURCE, function(event)
	if event.action_id == "refresh" and not source_busy then
		source_busy = true
		configure_source_actions()
		easybar.after(DEMO_DELAY_SECONDS, function()
			reset_items()
			source_busy = false
			configure_source_actions()
			publish()
		end)
	elseif event.action_id == "clear" then
		items = {}
		busy_item_id = nil
		publish()
	end
end)

-- Loading the widget registers its actions but leaves item creation to Refresh.
easybar.inbox.clear(SOURCE)
