--!nonstrict
--[[
	camera/DoFAuto.lua
	-----------------------------------------------------------------------------
	Auto-focus depth of field. Each frame we raycast from the camera forward; the hit
	distance (or a far default on a miss) becomes the focus target, and we ease the
	owned DepthOfFieldEffect.FocusDistance (bus.pipeline.dof) toward it with frame-
	rate-independent damping (cam_dof_focus_speed = tau) for a smooth focus pull.

	postfx/DepthOfField owns the effect's static shape (aperture); we only drive the
	live FocusDistance. update(dt) is called from the CameraFX loop.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local DoFAuto = {}
	DoFAuto.id = "camera/DoFAuto"
	local FAR = 200

	function DoFAuto.start(ctx)
		local maid = ctx.maid:childMaid()
		DoFAuto._maid = maid
		DoFAuto._ctx = ctx
		-- cached raycast params (ignore our own instances + character)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local function refresh()
			local ignore = { ctx.worldFolder }
			local char = ctx.services.Players.LocalPlayer and ctx.services.Players.LocalPlayer.Character
			if char then ignore[#ignore + 1] = char end
			params.FilterDescendantsInstances = ignore
		end
		refresh()
		local lp = ctx.services.Players.LocalPlayer
		if lp then maid:give(lp.CharacterAdded:Connect(refresh)) end
		DoFAuto._params = params
		DoFAuto._focus = 50
		return DoFAuto
	end

	function DoFAuto.update(dt)
		local ctx = DoFAuto._ctx
		if not ctx then return end
		if not State.get("cam_dof_enabled") then return end
		local dof = ctx.bus.pipeline and ctx.bus.pipeline.dof
		if not dof then return end
		local cam = ctx.camera()
		if not cam then return end
		local origin = cam.CFrame.Position
		local dir = cam.CFrame.LookVector * FAR
		local result = workspace:Raycast(origin, dir, DoFAuto._params)
		local targetDist = result and (result.Position - origin).Magnitude or FAR
		DoFAuto._focus = Util.damp(DoFAuto._focus, targetDist, State.get("cam_dof_focus_speed"), dt)
		dof.FocusDistance = DoFAuto._focus
	end

	function DoFAuto.stop() if DoFAuto._maid then DoFAuto._maid:clean() end end

	return DoFAuto
end
