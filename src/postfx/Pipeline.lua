--!nonstrict
--[[
	postfx/Pipeline.lua  —  CONTROLLER (manifest.boot)
	-----------------------------------------------------------------------------
	Creates and OWNS every post-processing Instance and the render budget.

	The ONLY real post-processing effects in Roblox are: BloomEffect, BlurEffect,
	ColorCorrectionEffect, DepthOfFieldEffect, SunRaysEffect. We create two CCEs —
	a TONEMAP CCE (filmic approximation, applied first conceptually) and a GRADE CCE
	(creative look). We do NOT control the exact inter-effect compositing order the
	engine uses; we only control which effects exist and their values.

	All instances are parented to Lighting via Snapshot (so they restore/destroy on
	unload) and PUBLISHED on ctx.bus.pipeline so sibling modules (Tonemap, Bloom,
	ColorGrade, DoFAuto, EyeAdaptation, Lightning, MotionBlur) can drive them without
	owning their lifecycle.

	Faked overlays (vignette/grain/dither/chromatic/letterbox/motion-blur) are NOT
	post-effects — those live in their own driver modules drawing GUI overlays.
]]

return function(require)
	local State = require("core/State")

	local Pipeline = {}
	Pipeline.id = "postfx/Pipeline"
	local drivers = {}

	function Pipeline.start(ctx)
		local maid = ctx.maid:childMaid()
		Pipeline._maid = maid
		local L = ctx.services.Lighting
		local Snapshot = ctx.snapshot

		-- Create owned effects. Tonemap CCE created FIRST (intent: pre-grade).
		local tonemapCCE = Snapshot.create("ColorCorrectionEffect", {
			Name = "CinematicTonemap", Enabled = true,
		}, L)
		local gradeCCE = Snapshot.create("ColorCorrectionEffect", {
			Name = "CinematicGrade", Enabled = true,
		}, L)
		local bloom = Snapshot.create("BloomEffect", { Name = "CinematicBloom", Enabled = true }, L)
		local dof = Snapshot.create("DepthOfFieldEffect", { Name = "CinematicDoF", Enabled = true }, L)
		local blur = Snapshot.create("BlurEffect", { Name = "CinematicBlur", Size = 0, Enabled = true }, L)
		local sunrays = Snapshot.create("SunRaysEffect", { Name = "CinematicSunRays", Enabled = true }, L)

		-- Publish for cross-module access (READ-only for others; we own lifecycle).
		ctx.bus.pipeline = {
			tonemapCCE = tonemapCCE,
			gradeCCE = gradeCCE,
			bloom = bloom,
			dof = dof,
			blur = blur,
			sunrays = sunrays,
		}

		Pipeline.getEffect = function(name)
			return ctx.bus.pipeline[name]
		end

		-- Sun rays from a simple coupling to atmosphere glare feel.
		local function applySunRays()
			Snapshot.set(sunrays, "Intensity", 0.1)
			Snapshot.set(sunrays, "Spread", 0.9)
		end
		applySunRays()

		-- Start the driver sub-modules. lighting/Tonemap is included here because it
		-- drives the tonemap CCE this Pipeline owns.
		local subs = {
			"lighting/Tonemap",
			"postfx/Bloom", "postfx/ColorGrade", "postfx/DepthOfField",
			"postfx/Vignette", "postfx/FilmGrain", "postfx/Dither",
			"postfx/Chromatic", "postfx/Letterbox",
		}
		for _, name in ipairs(subs) do
			local ok, handle = pcall(function()
				local m = require(name)
				return m.start(ctx) or m
			end)
			if ok and handle then
				drivers[#drivers + 1] = handle
				ctx.registerHandle(handle)
			else
				ctx.log.error("postfx sub failed:", name, handle)
			end
		end

		ctx.log.debug("Pipeline online; effects published on bus.pipeline")
		return Pipeline
	end

	function Pipeline.setQuality(q)
		for _, d in ipairs(drivers) do
			if type(d.setQuality) == "function" then pcall(d.setQuality, q) end
		end
	end

	function Pipeline.stop()
		if Pipeline._maid then Pipeline._maid:clean() end
	end

	return Pipeline
end
