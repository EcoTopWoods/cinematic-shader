--!nonstrict
--[[
	core/Logger.lua
	-----------------------------------------------------------------------------
	Tiny levelled logger with a ring buffer.

	WHY: We want one consistent prefix in the dev console, a level gate so we can
	go quiet in production, and a retained "last error" that the About tab in the
	UI can surface to the user without them opening the developer console.

	No engine state is mutated here; safe to require early.
]]

return function(_require)
	local Logger = {}

	Logger.Levels = { trace = 1, debug = 2, info = 3, warn = 4, error = 5, silent = 99 }

	local PREFIX = "[Cinematic]"
	local minLevel = Logger.Levels.info
	local ring = {}            -- recent messages, capped
	local RING_MAX = 64
	local lastError = nil

	local function push(levelName, msg)
		ring[#ring + 1] = { level = levelName, msg = msg }
		if #ring > RING_MAX then
			table.remove(ring, 1)
		end
	end

	function Logger.setLevel(levelNameOrNumber)
		if type(levelNameOrNumber) == "string" then
			minLevel = Logger.Levels[levelNameOrNumber] or minLevel
		elseif type(levelNameOrNumber) == "number" then
			minLevel = levelNameOrNumber
		end
	end

	local function fmt(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		return table.concat(parts, " ")
	end

	function Logger.trace(...) if minLevel <= 1 then print(PREFIX, "trace:", ...) end end

	function Logger.debug(...)
		if minLevel <= 2 then print(PREFIX, ...) end
		push("debug", fmt(...))
	end

	function Logger.info(...)
		if minLevel <= 3 then print(PREFIX, ...) end
		push("info", fmt(...))
	end

	function Logger.warn(...)
		if minLevel <= 4 then warn(PREFIX, ...) end
		push("warn", fmt(...))
	end

	function Logger.error(...)
		local m = fmt(...)
		lastError = m
		if minLevel <= 5 then warn(PREFIX, "ERROR:", m) end
		push("error", m)
	end

	-- Run fn in a pcall, logging (not raising) any failure. Returns ok, result.
	function Logger.guard(label, fn, ...)
		local ok, res = pcall(fn, ...)
		if not ok then
			Logger.error(label, "->", res)
		end
		return ok, res
	end

	function Logger.getLastError() return lastError end
	function Logger.getHistory() return ring end
	function Logger.clear() ring = {}; lastError = nil end

	return Logger
end
