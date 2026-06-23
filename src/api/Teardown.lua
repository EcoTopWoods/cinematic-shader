--!nonstrict
--[[
	api/Teardown.lua  —  the kill switch
	-----------------------------------------------------------------------------
	Bulletproof, idempotent unload that leaves ZERO residue:
	  1. exit PhotoMode / Freecam if active (restores camera takeover),
	  2. destroy the Rayfield window (UI.stop),
	  3. ctx.maid:clean() — stops EVERY loop/connection/thread (no orphaned
	     PreRender/Heartbeat),
	  4. Snapshot.restoreAll — writes back EVERY captured original property (Lighting,
	     Camera FOV/Type, Terrain water, part Reflectance/CFrame, …) and Destroys ONLY
	     our tagged created instances (effects, overlays, folders, emitters),
	  5. force Camera back to Custom,
	  6. clear the global handle.
	Each step is pcall-guarded so one failure can't strand the rest.
]]

return function(require)
	local Platform = require("core/Platform")
	local Snapshot = require("core/Snapshot")
	local Logger = require("core/Logger")

	local Teardown = {}
	local killing = false

	function Teardown.kill()
		if killing then return end
		killing = true
		Logger.info("Teardown: unloading…")

		local globals = Platform.globalTable()
		local handle = globals["__CINEMATIC_SHADER"]
		local ctx = handle and handle.ctx

		-- 1. exit camera takeovers
		pcall(function()
			local fc = require("camera/Freecam")
			if fc.isActive and fc.isActive() then fc.toggle(false) end
		end)
		pcall(function()
			local pm = require("camera/PhotoMode")
			if pm.isActive and pm.isActive() then pm.toggle(false) end
		end)

		-- 2. destroy the UI (Rayfield window is not ours to tag, so stop() Destroys it)
		pcall(function() require("ui/UI").stop() end)

		-- 3. stop every subsystem loop/connection
		if ctx and ctx.maid then
			pcall(function() ctx.maid:clean() end)
		end

		-- 4. restore all captured properties + destroy all tagged instances
		local roots = {}
		if ctx and ctx.services then
			roots[#roots + 1] = ctx.services.Lighting
			roots[#roots + 1] = ctx.services.Workspace
		end
		pcall(function() Snapshot.restoreAll(roots) end)

		-- 5. force camera back to default control
		pcall(function()
			local cam = workspace.CurrentCamera
			if cam and cam.CameraType == Enum.CameraType.Scriptable then
				cam.CameraType = Enum.CameraType.Custom
			end
		end)

		-- 6. clear the global handle
		if handle then handle.__alive = false end
		pcall(function() globals["__CINEMATIC_SHADER"] = nil end)

		Logger.info("Teardown complete — game state restored.")
		killing = false
	end

	Teardown.destroy = Teardown.kill
	return Teardown
end
