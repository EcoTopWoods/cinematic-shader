--!nonstrict
--[[
	postfx/Bloom.lua  —  driver
	-----------------------------------------------------------------------------
	Drives the owned BloomEffect (bus.pipeline.bloom) from bloom_* config.

	HDR-style coupling: a real HDR bloom thresholds in scene-referred luminance. We
	approximate that by COUPLING the bloom threshold to the live auto-exposure value
	(bus.exposure): when the eye adapts to a dark scene (exposure rises), the
	effective threshold drops so highlights bloom more — and vice-versa. This makes
	bloom track perceived brightness instead of being a static cutoff.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Bloom = {}
	Bloom.id = "postfx/Bloom"
	local qualityMul = 1

	function Bloom.start(ctx)
		local maid = ctx.maid:childMaid()
		Bloom._maid = maid

		local function effect() return ctx.bus.pipeline and ctx.bus.pipeline.bloom end

		local function applyStatic()
			local e = effect()
			if not e then return end
			e.Enabled = State.get("bloom_enabled")
			if not e.Enabled then return end
			e.Intensity = State.get("bloom_intensity") * Util.lerp(0.6, 1, qualityMul)
			e.Size = math.floor(State.get("bloom_size") * Util.lerp(0.6, 1, qualityMul) + 0.5)
		end

		-- threshold coupling runs on a throttled heartbeat
		local accum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			accum += dt
			if accum < 0.1 then return end
			accum = 0
			local e = effect()
			if not e or not State.get("bloom_enabled") then return end
			local couple = State.get("bloom_exposure_couple")
			local exposure = ctx.bus.exposure or 0
			-- higher exposure (darker scene) → lower threshold → more bloom
			local threshold = State.get("bloom_threshold") - couple * exposure
			e.Threshold = math.max(0, threshold)
		end))

		maid:give(State.observeMany(
			{ "bloom_enabled", "bloom_intensity", "bloom_size" }, applyStatic))

		applyStatic()
		return Bloom
	end

	function Bloom.setQuality(q)
		qualityMul = math.clamp(q, 0, 1)
	end

	function Bloom.stop()
		if Bloom._maid then Bloom._maid:clean() end
	end

	return Bloom
end
