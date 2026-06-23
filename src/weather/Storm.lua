--!nonstrict
--[[
	weather/Storm.lua  —  gust generator
	-----------------------------------------------------------------------------
	Storm is not its own particle system — it intensifies Rain and adds Lightning.
	This module's job is the WIND GUST signal: a smooth noise-driven multiplier the
	Weather controller applies on top of the base wind while a storm is active, so
	rain slant and foliage sway surge and ease like real gusts. Uses math.noise
	(deterministic, allocation-free) accumulated over time — no per-frame tables.
]]

return function(require)
	local Util = require("core/Util")

	local Storm = {}
	Storm.id = "weather/Storm"
	local t = 0
	local active = false

	function Storm.start(ctx)
		Storm._ctx = ctx
		ctx.log.debug("Storm gust generator ready")
		return Storm
	end

	function Storm.setActive(on)
		active = on
	end

	function Storm.isActive()
		return active
	end

	-- advance and return a wind multiplier in ~[0.6, 1.6]
	function Storm.gust(dt)
		if not active then return 1 end
		t += dt * 0.6
		local n = Util.noise(t, 0, 0)          -- -1..1
		return 1.1 + n * 0.5
	end

	function Storm.stop()
		active = false
	end

	return Storm
end
