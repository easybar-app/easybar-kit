---Metadata supplied with one EasyBar command completion.
---@class RetryCommandMetadata
---@field duration_ms? number Host-measured command duration in milliseconds.

---Completion callback supplied to one retry attempt.
---@alias RetryDoneCallback fun(output:string, code:EasyBarCommandExitCode, metadata?:RetryCommandMetadata)

---Starts one asynchronous attempt and returns its EasyBar command token.
---@alias RetryAttempt fun(done:RetryDoneCallback, attempt_number:integer):string

---Decides whether one failed attempt should be retried.
---@alias RetryPredicate fun(output:string, code:EasyBarCommandExitCode):boolean

---Receives the final non-retried result and total number of started attempts.
---@alias RetryCompletion fun(output:string, code:integer, attempts:integer, metadata:RetryCommandMetadata)

---Options accepted by `retry.run(...)`.
---@class (exact) RetryOptions
---@field delays? number[] Delay before each subsequent attempt. `delays[1]` follows attempt 1.
---@field attempt RetryAttempt Starts one asynchronous command and invokes `done` exactly once.
---@field should_retry? RetryPredicate Defaults to retrying every non-zero status except cancellation.
---@field on_complete RetryCompletion Runs once for the final result; it is not called after cancellation.

---Cancellable retry operation returned by `retry.run(...)`.
---@class (exact) RetryOperation
---@field cancel fun(self:RetryOperation):boolean Cancels the active command or pending delay.
---@field is_active fun(self:RetryOperation):boolean Returns whether the operation can still complete.

---Asynchronous retry helpers for EasyBar widgets.
---@class RetryModule
local M = {}

local TRANSIENT_NETWORK_PATTERNS = {
	-- Generic timeouts.
	"i/o timeout",
	"timed out",
	"timeout",

	-- Temporary DNS and resolver failures.
	"temporary failure",
	"try again",
	"could not resolve host",
	"name or service not known",
	"nodename nor servname",
	"no such host",
	"server misbehaving",

	-- Routing and local network availability.
	"network is unreachable",
	"no route to host",
	"network is down",
	"host is down",
	"cannot assign requested address",
	"can't assign requested address",

	-- Connection interruptions.
	"connection reset",
	"connection refused",
	"connection closed",
	"connection aborted",
	"broken pipe",

	-- TLS and truncated responses.
	"tls handshake timeout",
	"unexpected eof",

	-- Temporary HTTP gateway/server failures.
	"service unavailable",
	"bad gateway",
	"gateway timeout",
	"http 502",
	"http 503",
	"http 504",
}

---Returns whether a failed command looks like a transient network failure.
---Successful commands are never classified as transient, even when their output contains words
---such as "timeout". The check is heuristic and intended for idempotent network reads.
---@param output string Combined command output.
---@param code EasyBarCommandExitCode Final command status.
---@return boolean transient `true` only for a non-zero status that appears temporary.
function M.is_transient_network_error(output, code)
	local normalized_code = tonumber(code) or 1
	if normalized_code == 0 or normalized_code == 130 then
		return false
	end

	if normalized_code == 124 then
		return true
	end

	local normalized = string.lower(tostring(output or ""))
	for _, pattern in ipairs(TRANSIENT_NETWORK_PATTERNS) do
		if normalized:find(pattern, 1, true) ~= nil then
			return true
		end
	end

	return false
end

local function duration_ms(metadata)
	local value = type(metadata) == "table" and tonumber(metadata.duration_ms) or 0
	if value == nil or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return 0
	end
	return value
end

---Runs one asynchronous operation with delays before subsequent attempts.
---
---`attempt(done, attempt_number)` must start an asynchronous operation, return its EasyBar
---command token, and invoke `done(output, code, metadata)` once. The returned handle cancels either
---the active command or the pending host timer. Cancellation never invokes `on_complete`.
---
---The first attempt starts immediately. `delays[1]` is used before attempt 2, `delays[2]`
---before attempt 3, and so on. Store the returned operation only when the caller needs to cancel
---it or inspect its active state; callbacks and timers retain it until completion otherwise.
---@param easybar_api EasyBar Widget-scoped EasyBar API used for timers and command cancellation.
---@param options RetryOptions Retry policy and asynchronous operation callbacks.
---@return RetryOperation operation Cancellable handle for the complete retry sequence.
function M.run(easybar_api, options)
	assert(type(easybar_api) == "table", "retry.run requires the widget easybar API")
	assert(type(options) == "table", "retry.run requires an options table")
	assert(type(options.attempt) == "function", "retry.run requires options.attempt")
	assert(type(options.on_complete) == "function", "retry.run requires options.on_complete")

	local delays = {}
	for _, value in ipairs(type(options.delays) == "table" and options.delays or {}) do
		local delay = tonumber(value)
		assert(
			delay ~= nil and delay == delay and delay ~= math.huge and delay ~= -math.huge and delay >= 0,
			"retry delays must be finite non-negative numbers"
		)
		delays[#delays + 1] = delay
	end

	---@type RetryPredicate
	local should_retry = options.should_retry or function(_, code)
		return tonumber(code) ~= 0
	end

	local state = {
		attempts = 0,
		active_token = nil,
		timer = nil,
		cancelled = false,
		completed = false,
		duration_ms = 0,
	}

	local operation = {}
	local run_attempt

	local function complete(output, code)
		if state.cancelled or state.completed then
			return
		end

		state.completed = true
		state.active_token = nil
		state.timer = nil
		options.on_complete(output, code, state.attempts, {
			duration_ms = math.floor(state.duration_ms + 0.5),
		})
	end

	run_attempt = function()
		if state.cancelled or state.completed then
			return
		end

		state.attempts = state.attempts + 1

		local callback_called = false
		local ok, token_or_error = pcall(options.attempt, function(output, code, metadata)
			if callback_called then
				return
			end

			callback_called = true
			state.active_token = nil
			state.duration_ms = state.duration_ms + duration_ms(metadata)

			if state.cancelled or state.completed then
				return
			end

			local normalized_code = tonumber(code) or 1
			local delay = delays[state.attempts]
			local retryable = normalized_code ~= 130 and delay ~= nil and should_retry(output, normalized_code)

			if not retryable then
				complete(output, normalized_code)
				return
			end

			state.duration_ms = state.duration_ms + delay * 1000
			state.timer = easybar_api.after(delay, function()
				state.timer = nil
				run_attempt()
			end)
		end, state.attempts)

		if not ok then
			complete(tostring(token_or_error), 1)
			return
		end

		if callback_called then
			return
		end

		if type(token_or_error) ~= "string" or token_or_error == "" then
			complete("retry attempt did not return an asynchronous command token", 1)
			return
		end

		state.active_token = token_or_error
	end

	function operation:cancel()
		if state.cancelled or state.completed then
			return false
		end

		state.cancelled = true

		if state.timer ~= nil then
			state.timer:cancel()
			state.timer = nil
		end

		if type(state.active_token) == "string" and state.active_token ~= "" then
			easybar_api.cancel_async(state.active_token)
			state.active_token = nil
		end

		return true
	end

	function operation:is_active()
		return not state.cancelled and not state.completed
	end

	---@cast operation RetryOperation

	run_attempt()
	return operation
end

return M
