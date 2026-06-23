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
		local lum = 0.5

		local function skyLuminance()
			-- day factor from ClockTime: ~1 at noon, ~0 deep night.
			local h = State.get("lighting_clock_time")
			local day = math.clamp(math.sin((h - 6) / 12 * math.pi), 0, 1)
			return 0.10 + day * 0.78
		end

		-- A representative spread of rays approximating "what fills the frame":
		-- forward, four spread, two slightly-up (catch bright sky/windows), one down.
		-- Sky misses count at full sky brightness so looking at a bright sky correctly
		-- READS as bright (→ exposure pulls DOWN, preventing the white-out you'd get
		-- otherwise). This is the auto-adapt that keeps any game from blowing out.
		local FAN = {
			{ 0, 0 }, { 22, 6 }, { -22, 6 }, { 12, -8 }, { -12, -8 },
			{ 40, 14 }, { -40, 14 }, { 0, -28 },
		}
		local function sampleLuminance(cam)
			local cf = cam.CFrame
			local sky = skyLuminance()
			local total, n = 0, 0
			for _, a in ipairs(FAN) do
				local dir = (cf * CFrame.Angles(math.rad(a[2]), math.rad(a[1]), 0)).LookVector
				local r = workspace:Raycast(cf.Position, dir * 160, params)
				if r then
					local ok, c = pcall(function() return r.Instance.Color end)
					-- surface luminance lit by the current sky term; clamp so neon/white
					-- parts don't dominate the meter.
					local sl = (ok and typeof(c) == "Color3") and Util.luminance(c) or 0.5
					total += math.min(1, sl * (0.35 + 0.65 * sky))
				else
					total += sky -- the ray saw open sky → full sky brightness
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
			if sampleAccum >= 0.12 then
				sampleAccum = 0
				lum = sampleLuminance(cam)
				ctx.bus.sceneLuminance = lum
			end
			-- Gentle proportional response around the static exposure baseline: a scene
			-- already near target leaves exposure ≈ lighting_exposure (we ENHANCE, we
			-- don't fight a well-lit game); brighter → pull down, darker → lift modestly.
			-- gain 1.4 + the tightened [min,max] clamp prevents runaway over-exposure.
			local err = State.get("eye_adapt_target") - lum
			local base = State.get("lighting_exposure")
			local target = Util.clamp(base + err * 1.4, State.get("eye_adapt_min"), State.get("eye_adapt_max"))
			ctx.bus.exposure = Util.damp(ctx.bus.exposure, target, State.get("eye_adapt_speed"), dt)
		end))

		ctx.log.debug("EyeAdaptation online")
		return EyeAdaptation
	end

	function EyeAdaptation.stop() if EyeAdaptation._maid then EyeAdaptation._maid:clean() end end

	return EyeAdaptation
end
