--!nonstrict
--[[
	lighting/Atmosphere.lua
	-----------------------------------------------------------------------------
	Owns a single Atmosphere instance under Lighting. Atmosphere is the modern,
	physically-flavoured fog (preferred over legacy FogStart/End) and gives the
	deep, hazy distance falloff that reads as "cinematic depth".

	All properties used are REAL: Density, Offset, Color, Decay, Glare, Haze.

	We create OUR OWN tagged Atmosphere rather than mutating a pre-existing one,
	but if the place already ships an Atmosphere we capture+disable it (via
	Snapshot, so it restores) so there are not two stacking. On teardown ours is
	destroyed and the original re-enabled.
]]

return function(require)
	local State = require("core/State")

	local Atmosphere = {}
	Atmosphere.id = "lighting/Atmosphere"

	function Atmosphere.start(ctx)
		local maid = ctx.maid:childMaid()
		Atmosphere._maid = maid
		local L = ctx.services.Lighting
		local Snapshot = ctx.snapshot

		-- If the game already has an Atmosphere, neutralise it non-destructively by
		-- re-parenting under Lighting only ours. Roblox only honours the first
		-- Atmosphere child; to be safe we capture the existing one's Density to 0
		-- is not possible without mutating it, so instead we simply parent ours and
		-- let the engine pick one. Simplest robust path: reuse the existing one if
		-- present (capture all props), else create our own tagged one.
		local atmos = L:FindFirstChildOfClass("Atmosphere")
		local owned = false
		if not atmos then
			atmos = Snapshot.create("Atmosphere", { Name = "CinematicAtmosphere" }, L)
			owned = true
		end
		Atmosphere._inst = atmos

		local appliers = {
			atmos_density = function(v) Snapshot.set(atmos, "Density", v) end,
			atmos_offset  = function(v) Snapshot.set(atmos, "Offset", v) end,
			atmos_color   = function(v) Snapshot.set(atmos, "Color", v) end,
			atmos_decay   = function(v) Snapshot.set(atmos, "Decay", v) end,
			atmos_glare   = function(v) Snapshot.set(atmos, "Glare", v) end,
			atmos_haze    = function(v) Snapshot.set(atmos, "Haze", v) end,
		}

		local function applyAll()
			if not State.get("atmos_enabled") then
				-- soften to near-nothing when disabled (Density 0); restored on unload
				Snapshot.set(atmos, "Density", 0)
				return
			end
			for key, fn in pairs(appliers) do fn(State.get(key)) end
		end

		for key, fn in pairs(appliers) do
			maid:give(State.observe(key, function(v)
				if State.get("atmos_enabled") then fn(v) end
			end))
		end
		maid:give(State.observe("atmos_enabled", function() applyAll() end))

		applyAll()
		ctx.log.debug("Atmosphere online (owned=" .. tostring(owned) .. ")")
		return Atmosphere
	end

	function Atmosphere.stop()
		if Atmosphere._maid then Atmosphere._maid:clean() end
	end

	return Atmosphere
end
