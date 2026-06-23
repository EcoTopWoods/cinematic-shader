--!nonstrict
--[[
	enhancers/Water.lua
	-----------------------------------------------------------------------------
	Polishes Terrain water for a cleaner, more reflective, more cinematic look by
	tuning the REAL Terrain water properties — WaterColor, WaterTransparency,
	WaterReflectance, WaterWaveSize, WaterWaveSpeed — via Snapshot (restored on
	unload). Wetness from weather nudges reflectance up. Guards the (possible)
	absence of Terrain on baseplate / void places.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Water = {}
	Water.id = "enhancers/Water"

	function Water.start(ctx)
		local maid = ctx.maid:childMaid()
		Water._maid = maid
		local Snapshot = ctx.snapshot
		local terrain = ctx.services.Workspace:FindFirstChildOfClass("Terrain")
		if not terrain then
			ctx.log.debug("Water: no Terrain — skipped")
			return Water
		end

		local function apply()
			if not (State.get("enh_enabled") and State.get("enh_water")) then return end
			local wet = ctx.bus.wetness or 0
			Snapshot.set(terrain, "WaterColor", Color3.fromRGB(18, 58, 78))
			Snapshot.set(terrain, "WaterTransparency", 0.18)
			Snapshot.set(terrain, "WaterReflectance", Util.clamp(0.6 + wet * 0.3, 0, 1))
			Snapshot.set(terrain, "WaterWaveSize", 0.12)
			Snapshot.set(terrain, "WaterWaveSpeed", 8)
		end

		maid:give(State.observeMany({ "enh_enabled", "enh_water" }, apply))
		-- refresh reflectance as wetness drifts (throttled)
		local accum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			accum += dt
			if accum < 1 then return end
			accum = 0
			apply()
		end))
		apply()

		ctx.log.debug("Water polish online")
		return Water
	end

	function Water.stop() if Water._maid then Water._maid:clean() end end

	return Water
end
