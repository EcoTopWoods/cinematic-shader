--!nonstrict
--[[
	lighting/Tonemap.lua  —  driver, started by postfx/Pipeline
	-----------------------------------------------------------------------------
	APPROXIMATE filmic / ACES tonemapping.

	HARD TRUTH: Roblox has no ACES node, no tonemap operator, no LUT pass. The best
	legal approximation of a filmic response is a dedicated ColorCorrectionEffect
	tuned for toe/shoulder contrast + a slight desaturation, applied BEFORE the
	creative grade, working together with ExposureCompensation. This module DRIVES
	that pre-grade CCE (created + owned by postfx/Pipeline, published on
	bus.pipeline.tonemapCCE). It never creates the effect itself.

	The four "modes" are not real curves — they are different contrast/saturation
	bias presets that *evoke* ACES / Filmic / Reinhard / Neutral responses. Comments
	below state the intent of each so nobody mistakes this for a true operator.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Tonemap = {}
	Tonemap.id = "lighting/Tonemap"

	-- contrast/saturation multipliers that lean the CCE toward each look.
	local MODES = {
		ACES     = { contrastMul = 1.0,  satBias = -0.04 }, -- punchy toe, slightly desaturated highlights
		Filmic   = { contrastMul = 0.9,  satBias = -0.02 }, -- gentler shoulder
		Reinhard = { contrastMul = 0.7,  satBias =  0.00 }, -- soft, low-contrast roll-off
		Neutral  = { contrastMul = 0.5,  satBias =  0.02 }, -- nearly linear, minimal grade
	}

	function Tonemap.start(ctx)
		local maid = ctx.maid:childMaid()
		Tonemap._maid = maid

		local function cce()
			return ctx.bus.pipeline and ctx.bus.pipeline.tonemapCCE or nil
		end

		local function apply()
			local effect = cce()
			if not effect then return end
			local enabled = State.get("tonemap_enabled")
			effect.Enabled = enabled
			if not enabled then return end
			local mode = MODES[State.get("tonemap_mode")] or MODES.ACES
			local contrast = State.get("tonemap_contrast") * mode.contrastMul
			local sat = State.get("tonemap_saturation") + mode.satBias
			-- white point biases brightness slightly (>1 lifts, <1 lowers) to mimic
			-- a shoulder that rolls highlights off before the creative grade.
			local wp = State.get("tonemap_white_point")
			effect.Contrast = Util.clamp(contrast, -1, 1)
			effect.Saturation = Util.clamp(sat, -1, 1)
			effect.Brightness = Util.clamp((wp - 1) * 0.15, -0.3, 0.3)
		end

		-- the CCE may not exist the instant we start (Pipeline starts us right after
		-- creating it, but be defensive): poll briefly until present, then wire.
		maid:spawn(function()
			local tries = 0
			while not cce() and tries < 60 do
				task.wait(0.05)
				tries += 1
			end
			apply()
		end)

		maid:give(State.observeMany(
			{ "tonemap_enabled", "tonemap_mode", "tonemap_contrast", "tonemap_saturation", "tonemap_white_point" },
			apply))

		ctx.log.debug("Tonemap driver online")
		return Tonemap
	end

	function Tonemap.stop()
		if Tonemap._maid then Tonemap._maid:clean() end
	end

	return Tonemap
end
