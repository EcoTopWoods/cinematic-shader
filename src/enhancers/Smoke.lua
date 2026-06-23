--!nonstrict
--[[
	enhancers/Smoke.lua
	-----------------------------------------------------------------------------
	Softens / layers existing Smoke instances (Scanner kind "smoke") by nudging their
	Opacity, Size and RiseVelocity for a thicker, slower, more volumetric look. We
	mutate the GAME's Smoke via Snapshot (capture-once → restore on unload); we never
	create or destroy the game's emitters. All real Smoke properties.
]]

return function(require)
	local State = require("core/State")

	local Smoke = {}
	Smoke.id = "enhancers/Smoke"

	function Smoke.start(ctx)
		local maid = ctx.maid:childMaid()
		Smoke._maid = maid
		local Snapshot = ctx.snapshot
		local Scanner = require("detection/Scanner")
		local touched = setmetatable({}, { __mode = "k" })

		local function apply(part)
			local on = State.get("enh_enabled") and State.get("enh_smoke")
			if not on then return end
			local smoke = part:FindFirstChildOfClass("Smoke")
			if not smoke or touched[smoke] then return end
			touched[smoke] = true
			Snapshot.set(smoke, "Opacity", math.min(1, smoke.Opacity * 1.15))
			Snapshot.set(smoke, "Size", smoke.Size * 1.25)
			Snapshot.set(smoke, "RiseVelocity", smoke.RiseVelocity * 0.7)
		end

		local function applyAll()
			for _, p in ipairs(Scanner.getByKind("smoke")) do apply(p) end
		end

		maid:give(Scanner.onClassified:Connect(function(part, cls)
			if cls.kind == "smoke" then apply(part) end
		end))
		maid:give(State.observeMany({ "enh_enabled", "enh_smoke" }, applyAll))
		task.defer(applyAll)

		ctx.log.debug("Smoke enhancer online")
		return Smoke
	end

	function Smoke.stop() if Smoke._maid then Smoke._maid:clean() end end

	return Smoke
end
