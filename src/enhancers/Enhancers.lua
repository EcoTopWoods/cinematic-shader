--!nonstrict
--[[
	enhancers/Enhancers.lua  —  CONTROLLER (manifest.boot)
	-----------------------------------------------------------------------------
	Master gate for the budget-aware scene enhancers. Starts each sub-enhancer; each
	one self-gates on enh_enabled AND its own enh_* key, so toggling either in the UI
	turns the effect on/off live. setQuality fans out to subs that scale particle /
	beam budgets.
]]

return function(require)
	local State = require("core/State")

	local Enhancers = {}
	Enhancers.id = "enhancers/Enhancers"
	local subs = {}

	function Enhancers.start(ctx)
		local maid = ctx.maid:childMaid()
		Enhancers._maid = maid

		for _, name in ipairs({
			"enhancers/Foliage", "enhancers/Fire", "enhancers/Smoke", "enhancers/Water",
			"enhancers/Particles", "enhancers/Lights", "enhancers/Beams",
		}) do
			local ok, handle = pcall(function()
				local m = require(name)
				return m.start(ctx) or m
			end)
			if ok and handle then
				subs[#subs + 1] = handle
				ctx.registerHandle(handle)
			else
				ctx.log.error("enhancer failed:", name, handle)
			end
		end

		ctx.log.debug("Enhancers online (" .. #subs .. " active)")
		return Enhancers
	end

	function Enhancers.setQuality(q)
		for _, s in ipairs(subs) do
			if type(s.setQuality) == "function" then pcall(s.setQuality, q) end
		end
	end

	function Enhancers.stop()
		if Enhancers._maid then Enhancers._maid:clean() end
	end

	return Enhancers
end
