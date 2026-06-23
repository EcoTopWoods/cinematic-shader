--!nonstrict
--[[
	perf/AdaptiveQuality.lua  —  CONTROLLER (manifest.boot)
	-----------------------------------------------------------------------------
	Closed-loop quality controller. Tracks an FPS EMA and nudges bus.qualityMul up or
	down to defend perf_target_fps, WITH HYSTERESIS (a deadband + consecutive-sample
	requirement) so it doesn't oscillate. Every effect module consumes the resulting
	ctx.getQuality() via its setQuality(0..1), so a single dial scales the whole
	pipeline.

	Conceptual step ladder when LOWERING (cost-first): viewport mirror → volumetric
	beams → particle rates → scanner budget → DoF; raising reverses it. Rather than
	bespoke per-feature toggles (which would fight the user's explicit settings) we
	scale the shared qualityMul, which those subsystems already interpret in that
	rough cost order via their setQuality implementations.

	Starts Benchmark (for the initial tier) and PerfHUD.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local AdaptiveQuality = {}
	AdaptiveQuality.id = "perf/AdaptiveQuality"

	function AdaptiveQuality.start(ctx)
		local maid = ctx.maid:childMaid()
		AdaptiveQuality._maid = maid

		local Benchmark = require("perf/Benchmark"); Benchmark.start(ctx); ctx.registerHandle(Benchmark)
		local PerfHUD = require("perf/PerfHUD"); PerfHUD.start(ctx); ctx.registerHandle(PerfHUD)
		AdaptiveQuality.Benchmark = Benchmark

		local fps = 60
		local belowCount, aboveCount = 0, 0
		local STEP = 0.08
		local tickAccum = 0

		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			-- FPS EMA (frame-rate independent-ish; dt is per frame)
			if dt > 0 then
				local inst = 1 / dt
				fps = fps + (inst - fps) * 0.1
			end
			ctx.bus.fps = fps

			tickAccum += dt
			if tickAccum < 0.5 then return end
			tickAccum = 0
			if not State.get("perf_adaptive") then return end

			local target = State.get("perf_target_fps")
			local lowBand = target * 0.92
			local highBand = target * 1.06
			local minMul = State.get("perf_min_quality")

			if fps < lowBand then
				belowCount += 1; aboveCount = 0
				if belowCount >= 2 then
					belowCount = 0
					local newMul = Util.clamp((ctx.bus.qualityMul or 1) - STEP, minMul, 1)
					if newMul ~= ctx.bus.qualityMul then
						ctx.bus.qualityMul = newMul
						if ctx.fanoutQuality then pcall(ctx.fanoutQuality) end
						ctx.log.debug(("Adaptive ↓ q=%.2f (fps %.0f)"):format(newMul, fps))
					end
				end
			elseif fps > highBand then
				aboveCount += 1; belowCount = 0
				if aboveCount >= 3 then -- raise more cautiously than we drop
					aboveCount = 0
					local newMul = Util.clamp((ctx.bus.qualityMul or 1) + STEP * 0.6, minMul, 1)
					if newMul ~= ctx.bus.qualityMul then
						ctx.bus.qualityMul = newMul
						if ctx.fanoutQuality then pcall(ctx.fanoutQuality) end
						ctx.log.debug(("Adaptive ↑ q=%.2f (fps %.0f)"):format(newMul, fps))
					end
				end
			else
				belowCount = 0; aboveCount = 0 -- in the deadband: stable
			end
		end))

		ctx.log.debug("AdaptiveQuality online")
		return AdaptiveQuality
	end

	function AdaptiveQuality.stop()
		if AdaptiveQuality._maid then AdaptiveQuality._maid:clean() end
	end

	return AdaptiveQuality
end
