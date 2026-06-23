--!nonstrict
--[[
	postfx/DepthOfField.lua  —  driver
	-----------------------------------------------------------------------------
	Owns the STATIC properties of the DepthOfFieldEffect (bus.pipeline.dof):
	InFocusRadius, NearIntensity, FarIntensity — derived from cam_dof_aperture.

	It deliberately does NOT set FocusDistance: camera/DoFAuto drives that live every
	frame so the lens pulls focus onto whatever the camera looks at. Two writers, one
	effect, cleanly split: static shape here, dynamic focus there.

	Real DepthOfFieldEffect props only.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local DoF = {}
	DoF.id = "postfx/DepthOfField"
	local qualityMul = 1

	function DoF.start(ctx)
		local maid = ctx.maid:childMaid()
		DoF._maid = maid

		local function effect() return ctx.bus.pipeline and ctx.bus.pipeline.dof end

		local function apply()
			local e = effect()
			if not e then return end
			e.Enabled = State.get("cam_dof_enabled")
			if not e.Enabled then return end
			-- aperture → bokeh strength. Far intensity carries most of the cinematic
			-- background blur; near intensity is kept subtle to avoid HUD mush.
			local aperture = State.get("cam_dof_aperture")
			local strength = Util.clamp(aperture / 200, 0, 1) * Util.lerp(0.5, 1, qualityMul)
			e.FarIntensity = strength
			e.NearIntensity = strength * 0.3
			e.InFocusRadius = Util.lerp(40, 8, strength) -- tighter focus band as aperture opens
		end

		maid:give(State.observeMany(
			{ "cam_dof_enabled", "cam_dof_aperture" }, apply))

		apply()
		return DoF
	end

	function DoF.setQuality(q)
		qualityMul = math.clamp(q, 0, 1)
	end

	function DoF.stop()
		if DoF._maid then DoF._maid:clean() end
	end

	return DoF
end
