--!nonstrict
--[[
	camera/Shake.lua
	-----------------------------------------------------------------------------
	Handheld camera feel. Two layers:
	  * idle Perlin sway (math.noise over time) scaled by cam_shake_amount — the
	    subtle constant motion that makes a locked camera feel "held",
	  * impulse shakes (Shake.impulse(mag)) that spike and decay, for hits/landings.
	getOffset(dt) returns a small CFrame the CameraFX controller composites ONTO the
	camera (offset-only — never seizes the camera). Allocation-free.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Shake = {}
	Shake.id = "camera/Shake"
	local t = 0
	local impulse = 0

	function Shake.start(ctx)
		Shake._ctx = ctx
		return Shake
	end

	function Shake.impulse(mag)
		impulse = math.min(2, impulse + (mag or 0.5))
	end

	-- returns a CFrame offset (rotation-dominant, tiny translation)
	function Shake.getOffset(dt)
		if not State.get("cam_shake") then return nil end
		t += dt
		local amt = State.get("cam_shake_amount")
		-- idle sway
		local rx = Util.noise(t * 0.7, 0, 0) * 0.012 * amt
		local ry = Util.noise(0, t * 0.6, 0) * 0.012 * amt
		local rz = Util.noise(0, 0, t * 0.5) * 0.006 * amt
		-- impulse (decays)
		if impulse > 0 then
			impulse = math.max(0, impulse - dt * 3)
			local k = impulse
			rx += Util.noise(t * 18, 0, 0) * 0.03 * k
			ry += Util.noise(0, t * 17, 0) * 0.03 * k
			rz += Util.noise(0, 0, t * 16) * 0.02 * k
		end
		return CFrame.Angles(rx, ry, rz)
	end

	function Shake.stop() end

	return Shake
end
