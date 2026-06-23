--!nonstrict
--[[
	postfx/ColorGrade.lua  —  driver
	-----------------------------------------------------------------------------
	The CREATIVE grade: drives the second ColorCorrectionEffect (bus.pipeline.gradeCCE)
	applied AFTER the filmic tonemap CCE. This is where the "look" lives — graded
	blacks, warm tint, punchy-but-controlled saturation. Real CCE props only:
	Brightness, Contrast, Saturation, TintColor.
]]

return function(require)
	local State = require("core/State")

	local ColorGrade = {}
	ColorGrade.id = "postfx/ColorGrade"

	function ColorGrade.start(ctx)
		local maid = ctx.maid:childMaid()
		ColorGrade._maid = maid

		local function effect() return ctx.bus.pipeline and ctx.bus.pipeline.gradeCCE end

		local function apply()
			local e = effect()
			if not e then return end
			e.Enabled = State.get("grade_enabled")
			if not e.Enabled then return end
			e.Brightness = State.get("grade_brightness")
			e.Contrast = State.get("grade_contrast")
			e.Saturation = State.get("grade_saturation")
			e.TintColor = State.get("grade_tint")
		end

		maid:give(State.observeMany(
			{ "grade_enabled", "grade_brightness", "grade_contrast", "grade_saturation", "grade_tint" },
			apply))

		apply()
		return ColorGrade
	end

	function ColorGrade.stop()
		if ColorGrade._maid then ColorGrade._maid:clean() end
	end

	return ColorGrade
end
