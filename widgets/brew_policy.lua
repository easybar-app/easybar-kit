-- Shared Homebrew manual-upgrade policy for EasyBar widgets.
--
-- Every package listed here remains visible when outdated, but EasyBar will
-- not upgrade it. Keep this list conservative: only add packages that should
-- be updated interactively because they can interrupt local workloads, require
-- privileged/system-extension handling, or need vendor-specific follow-up.

---@alias BrewPolicyKind "formula"|"cask"

---@class BrewPolicyRule
---@field reason string

local MANUAL_UPGRADE_RULES = {
	formula = {
		-- Formula exclusions are intentionally empty by default. Add local
		-- databases or services here when they must be upgraded manually.
		-- ["postgresql@17"] = {
		-- 	reason = "Upgrade after checking the database migration plan",
		-- },
	},
	cask = {
		["docker"] = {
			reason = "Update through Docker Desktop",
		},
		["docker-desktop"] = {
			reason = "Update through Docker Desktop",
		},
		["macfuse"] = {
			reason = "Update manually because macFUSE uses a system extension",
		},
		["macfuse@dev"] = {
			reason = "Update manually because macFUSE uses a system extension",
		},
		["orbstack"] = {
			reason = "Update from OrbStack after stopping active containers and VMs",
		},
		["parallels"] = {
			reason = "Update from Parallels after shutting down active virtual machines",
		},
		["rancher"] = {
			reason = "Update from Rancher Desktop after stopping active workloads",
		},
		["utm"] = {
			reason = "Update manually after shutting down active virtual machines",
		},
		["virtualbox"] = {
			reason = "Update manually after shutting down active virtual machines",
		},
		["virtualbox@6"] = {
			reason = "Update manually after shutting down active virtual machines",
		},
		["virtualbox@beta"] = {
			reason = "Update manually after shutting down active virtual machines",
		},
	},
}

local PREFIX_RULES = {
	formula = {},
	cask = {
		{ prefix = "orbstack@", rule = MANUAL_UPGRADE_RULES.cask["orbstack"] },
		{ prefix = "parallels@", rule = MANUAL_UPGRADE_RULES.cask["parallels"] },
		{ prefix = "rancher@", rule = MANUAL_UPGRADE_RULES.cask["rancher"] },
		{ prefix = "utm@", rule = MANUAL_UPGRADE_RULES.cask["utm"] },
		{ prefix = "virtualbox@", rule = MANUAL_UPGRADE_RULES.cask["virtualbox"] },
	},
}

local policy = {}

--- Returns the configured manual-upgrade rule for a package.
---@param kind BrewPolicyKind
---@param name unknown
---@return BrewPolicyRule?
function policy.rule(kind, name)
	local rules = MANUAL_UPGRADE_RULES[kind]
	if rules == nil then
		return nil
	end

	name = tostring(name or "")
	local exact = rules[name]
	if exact ~= nil then
		return exact
	end

	for _, prefix_rule in ipairs(PREFIX_RULES[kind] or {}) do
		if name:sub(1, #prefix_rule.prefix) == prefix_rule.prefix then
			return prefix_rule.rule
		end
	end

	return nil
end

--- Returns whether EasyBar may upgrade a package.
---@param kind BrewPolicyKind
---@param name unknown
---@return boolean
function policy.is_upgradeable(kind, name)
	return policy.rule(kind, name) == nil
end

--- Returns the manual-upgrade reason for a package.
---@param kind BrewPolicyKind
---@param name unknown
---@return string?
function policy.reason(kind, name)
	local rule = policy.rule(kind, name)
	return rule and rule.reason or nil
end

return policy
