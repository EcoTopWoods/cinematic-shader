--!nonstrict
--[[
	camera/EyeAdaptation.lua
	-----------------------------------------------------------------------------
	Auto-exposure. We have no framebuffer/luminance readback, so we ESTIMATE scene
	luminance cheaply: a sky-brightness term from ClockTime plus a few forward/down
	raycasts whose hit-colour luminance proxies for what the camera sees. That
	estimate (bus.sceneLuminance) drives ExposureCompensation toward eye_adapt_target
	using frame-rate-independent exponential smoothing with a SLOW tau
	(eye_adapt_speed) — exactly the "v += (target-v)*(1-exp(-dt/tau))" form — so the
	exposure breathes like a real eye, clamped to [eye_adapt_min, eye_adapt_max].

	bus.exposure is consumed by lighting/Lighting (applies it) and postfx/Bloom
	(threshold coupling). Documented as an estimate, not a real meter.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local EyeAdaptation = {}
	EyeAdaptation.id = "camera/EyeAdaptation"

	function EyeAdaptation.start(ctx)
		local maid = ctx.maid:childMaid()
		EyeAdaptation._maid = maid
		local L = ctx.services.Lighting

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local function refresh()
			local ignore = { ctx.worldFolder }
			local char = ctx.services.Players.LocalPlayer and ctx.services.Players.LocalPlayer.Character
			if char then ignore[#ignore + 1] = char end
			params.FilterDescendantsInstances = ignore
		end
		refresh()
		local lp = ctx.services.Players.LocalPlayer
		if lp then maid:give(lp.CharacterAdded:Connect(refresh)) end

		-- seed exposure from the static config so we don't pop on first frame
		ctx.bus.exposure = State.get("lighting_exposure")
		local lum = 0.4

		local function skyLuminance()
			-- day factor from ClockTime: ~1 at noon, ~0 deep night.
			local h = State.get("lighting_clock_time")
			local day = math.clamp(math.sin((h - 6) / 12 * math.pi), 0, 1)
			return 0.08 + day * 0.72
		end

		local function sampleLuminance(cam)
			local cf = cam.CFrame
			local sky = skyLuminance()
			local total, n = 0, 0
			-- 1 forward + 2 spread + 1 down: cheap, fixed
			local dirs = {
				cf.LookVector,
				(cf * CFrame.Angles(0, math.rad(20), 0)).LookVector,
				(cf * CFrame.Angles(0, math.rad(-20), 0)).LookVector,
				Vector3.new(0, -1, 0),
			}
			for _, d in ipairs(dirs) do
				local r = workspace:Raycast(cf.Position, d * 120, params)
				if r then
					local ok, c = pcall(function() return r.Instance.Color end)
					total += (ok and typeof(c) == "Color3") and Util.luminance(c) * sky or sky * 0.3
				else
					total += sky -- saw the sky
				end
				n += 1
			end
			return total / math.max(1, n)
		end

		local sampleAccum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			if not State.get("eye_adapt_enabled") then
				-- hand exposure back to the static value when disabled
				ctx.bus.exposure = State.get("lighting_exposure")
				return
			end
			local cam = ctx.camera()
			if not cam then return end
			sampleAccum += dt
			if sampleAccum >= 0.1 then
				sampleAccum = 0
				lum = sampleLuminance(cam)
				ctx.bus.sceneLuminance = lum
			end
			-- darker than target → raise exposure; brighter → lower it
			local err = State.get("eye_adapt_target") - lum
			local target = Util.clamp(err * 2.5, State.get("eye_adapt_min"), State.get("eye_adapt_max"))
			ctx.bus.exposure = Util.damp(ctx.bus.exposure, target, State.get("eye_adapt_speed"), dt)
		end))

		ctx.log.debug("EyeAdaptation online")
		return EyeAdaptation
	end

	function EyeAdaptation.stop() if EyeAdaptation._maid then EyeAdaptation._maid:clean() end end

	return EyeAdaptation
end
