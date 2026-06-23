--!nonstrict
--[[
	camera/FOV.lua
	-----------------------------------------------------------------------------
	Dynamic field-of-view. The camera widens slightly as the player moves faster
	(a speed/sprint "kick"), eased with frame-rate-independent damping so it never
	snaps. Writes Camera.FieldOfView directly (captured once via Snapshot so unload
	restores the original FOV). Reads bus.camSpeed (written by CameraFX).
	update(dt) is called from the CameraFX PreRender loop for tight ordering.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local FOV = {}
	FOV.id = "camera/FOV"
	local SPRINT_REF = 26 -- studs/s treated as "full speed" for the kick

	function FOV.start(ctx)
		FOV._ctx = ctx
		FOV._captured = false
		return FOV
	end

	function FOV.update(dt)
		local ctx = FOV._ctx
		if not ctx then return end
		local cam = ctx.camera()
		if not cam then return end
		if not FOV._captured then
			ctx.snapshot.capture(cam, "FieldOfView")
			FOV._captured = true
		end
		local base = State.get("cam_fov_base")
		local kick = State.get("cam_fov_kick")
		local speed = ctx.bus.camSpeed or 0
		local target = base + kick * Util.clamp(speed / SPRINT_REF, 0, 1)
		cam.FieldOfView = Util.damp(cam.FieldOfView, target, 0.2, dt)
	end

	function FOV.stop() end

	return FOV
end
