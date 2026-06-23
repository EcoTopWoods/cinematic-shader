--!nonstrict
--[[
	reflections/OverlayReflection.lua  —  probe strategy ("Color Blend (cheap)")
	-----------------------------------------------------------------------------
	The cheapest reflection tier: NO raycasting. Floors are tinted toward a single
	sampled environment colour (a blend of OutdoorAmbient and the sky's warm shift),
	refreshed a few times a second. Combined with the controller's Fresnel-driven
	Reflectance this gives a convincing flat sheen at almost zero cost — the right
	fallback for mobile / low tiers.

	Same strategy interface as RaycastProbe so the controller can swap between them.
]]

return function(require)
	local OverlayReflection = {}
	OverlayReflection.id = "reflections/OverlayReflection"

	local sharedColor = Color3.fromRGB(150, 160, 175)

	function OverlayReflection.register(_entry) end
	function OverlayReflection.unregister(_entry) end
	function OverlayReflection.colorFor(_entry) return sharedColor end
	function OverlayReflection.setQuality(_q) end

	function OverlayReflection.start(ctx)
		local maid = ctx.maid:childMaid()
		OverlayReflection._maid = maid
		local L = ctx.services.Lighting

		local function refresh()
			sharedColor = L.OutdoorAmbient:Lerp(L.ColorShift_Top, 0.4)
		end
		refresh()

		local accum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			accum += dt
			if accum < 0.5 then return end
			accum = 0
			refresh()
		end))

		ctx.log.debug("OverlayReflection (cheap color-blend) online")
		return OverlayReflection
	end

	function OverlayReflection.stop()
		if OverlayReflection._maid then OverlayReflection._maid:clean() end
	end

	return OverlayReflection
end
