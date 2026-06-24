--!nonstrict
--[[
	enhancers/Beams.lua  —  sun god-rays
	-----------------------------------------------------------------------------
	Roblox ships a real, sun-anchored screen-space scattering effect: SunRaysEffect.
	It emanates from the ACTUAL sun's on-screen position and fades as the sun leaves
	view — which is exactly right and, crucially, it does NOT track the camera.

	An earlier version ALSO added camera-facing Beam "accent shafts" in front of the
	camera. Those read as a gray wedge that followed the view with eerie precision
	(FaceCamera + camera-relative placement). Deleted — they were the artifact. We now
	drive ONLY the engine SunRaysEffect, kept deliberately subtle, gated by how directly
	the camera faces the sun and by daytime.

	Honest framing: screen-space sun scattering, not true volumetrics. (Per-streetlight
	volumetric cones live in enhancers/Lights.lua, a separate feature.)
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Beams = {}
	Beams.id = "enhancers/Beams"

	function Beams.start(ctx)
		local maid = ctx.maid:childMaid()
		Beams._maid = maid
		local L = ctx.services.Lighting
		local Snapshot = ctx.snapshot
		Beams._q = ctx.getQuality()

		local accum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			accum += dt
			if accum < 0.1 then return end
			accum = 0

			local sunrays = ctx.bus.pipeline and ctx.bus.pipeline.sunrays
			if not sunrays then return end

			local on = State.get("enh_enabled") and State.get("enh_godrays")
			local cam = ctx.camera()
			local sunDir = L:GetSunDirection()             -- unit vector toward the sun
			local daytime = math.clamp(sunDir.Y * 6, 0, 1)  -- fade near horizon / night
			local facing = 0
			if cam then
				facing = math.clamp(cam.CFrame.LookVector:Dot(sunDir), 0, 1) -- 1 = staring at sun
			end
			local strength = State.get("enh_godray_strength")

			-- Subtle, sun-anchored. No camera-following geometry.
			local target = on and (strength * 0.32 * daytime * (0.25 + 0.75 * facing)) or 0
			Snapshot.set(sunrays, "Intensity", Util.clamp(target * (Beams._q or 1), 0, 0.32))
			Snapshot.set(sunrays, "Spread", 0.85)
		end))

		ctx.log.debug("God-rays online (SunRaysEffect only — no camera-following beams)")
		return Beams
	end

	function Beams.setQuality(q) Beams._q = math.clamp(q, 0, 1) end
	function Beams.stop() if Beams._maid then Beams._maid:clean() end end

	return Beams
end
