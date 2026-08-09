--- Module contract:
--- Owns cancellable host timer state and callback dispatch.
local M = {}
local validation = require("easybar.validation")

--- Creates a broker for cancellable host-owned one-shot timers.
---@param state table Shared mutable runtime state.
---@param hooks table Host timer request and cancellation callbacks.
---@return table broker Timer API used by the registry.
function M.new(state, hooks)
	local broker = {}
	local request_timer = hooks.request_timer
	local request_cancel_timer = hooks.request_cancel_timer
	local before_async_callback = hooks.before_async_callback
	local on_async_callback_error = hooks.on_async_callback_error
	local fallback_token = hooks.fallback_token

	--- Schedules one validated one-shot callback and returns a cancellation handle.
	function broker.after(delay_seconds, callback, ...)
		local signature = "easybar.after(delay_seconds, callback)"
		assert(select("#", ...) == 0, signature .. " does not accept extra arguments")
		local delay = validation.non_negative_number(delay_seconds, validation.MAX_TIMER_DELAY_SECONDS)
		assert(delay ~= nil, signature .. " requires a finite delay >= 0")
		assert(type(callback) == "function", signature .. " requires callback")
		assert(type(request_timer) == "function", "easybar.after unavailable without host timer")
		assert(type(request_cancel_timer) == "function", "easybar.after unavailable without host timer cancellation")

		local token = request_timer(delay) or fallback_token("timer")
		assert(state.pending_timers[token] == nil, "duplicate easybar timer token: " .. tostring(token))
		state.pending_timers[token] = callback
		local handle = { token = token }

		--- Cancels this timer if it is still pending.
		function handle:cancel()
			if state.pending_timers[self.token] == nil then
				return false
			end
			state.pending_timers[self.token] = nil
			request_cancel_timer(self.token)
			return true
		end
		handle.dispose = handle.cancel
		return handle
	end

	--- Drops one callback after the host rejects its timer request.
	function broker.handle_timer_rejected(token)
		if state.pending_timers[token] == nil then
			return false
		end
		state.pending_timers[token] = nil
		return true
	end

	--- Runs and removes the callback for one fired timer token.
	function broker.handle_timer_fired(token)
		local callback = state.pending_timers[token]
		if callback == nil then
			return false
		end
		state.pending_timers[token] = nil
		before_async_callback()
		local ok, err = pcall(callback)
		if not ok then
			on_async_callback_error("timer", err)
		end
		return true
	end

	return broker
end

return M
