--!nonstrict
--[[
	camera/CameraFX.lua  —  CONTROLLER (manifest.boot)
	-----------------------------------------------------------------------------
	The cinematic camera brain. Runs on RunService.PreRender (the right place for
	camera work — after the default camera has positioned itself, just before render)
	and composes the contributions of its sub-modules:
	    FOV.update / DoFAuto.update / MotionBlur.update  — write their own effects
	    Shake.getOffset                                  — additive CFrame offset
	    EyeAdaptation                                    — self-loops (exposure)
	    Freecam / PhotoMode                              — explicit camera takeover

	CONTENTION RULE: we are NON-EXCLUSIVE. We never set CameraType for normal play.
	If another script owns the camera (CameraType == Scriptable and it isn't our
	Freecam/PhotoMode), we still only ADD a shake offset on top of its CFrame and warn
	ONCE — we never seize control. Original FieldOfView/CameraType restore on unload.

	It also publishes camera metrics on the bus: camCFrame, camDelta, camSpeed.
]]

return function(require)
	local State = require("core/State")

	local CameraFX = {}
	CameraFX.id = "camera/CameraFX"

	function CameraFX.start(ctx)
		local maid = ctx.maid:childMaid()
		CameraFX._maid = maid

		-- start sub-modules
		local FOV = require("camera/FOV"); FOV.start(ctx); ctx.registerHandle(FOV)
		local DoFAuto = require("camera/DoFAuto"); DoFAuto.start(ctx); ctx.registerHandle(DoFAuto)
		local MotionBlur = require("camera/MotionBlur"); MotionBlur.start(ctx); ctx.registerHandle(MotionBlur)
		local EyeAdaptation = require("camera/EyeAdaptation"); EyeAdaptation.start(ctx); ctx.registerHandle(EyeAdaptation)
		local Shake = require("camera/Shake"); Shake.start(ctx); ctx.registerHandle(Shake)
		local Freecam = require("camera/Freecam"); Freecam.start(ctx); ctx.registerHandle(Freecam)
		local PhotoMode = require("camera/PhotoMode"); PhotoMode.start(ctx); ctx.registerHandle(PhotoMode)
		CameraFX.Shake = Shake
		CameraFX.Freecam = Freecam
		CameraFX.PhotoMode = PhotoMode

		local prevPos = nil
		local warnedContention = false

		maid:give(ctx.services.RunService.PreRender:Connect(function(dt)
			local cam = ctx.camera()
			if not cam then return end

			-- ── publish camera metrics ─────────────────────────────────────────
			local pos = cam.CFrame.Position
			ctx.bus.camDelta = prevPos and (pos - prevPos).Magnitude or 0
			prevPos = pos
			ctx.bus.camCFrame = cam.CFrame
			-- planar character speed
			local speed = 0
			local char = ctx.services.Players.LocalPlayer and ctx.services.Players.LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local v = hrp.AssemblyLinearVelocity
				speed = Vector3.new(v.X, 0, v.Z).Magnitude
			end
			ctx.bus.camSpeed = speed

			if not State.get("cam_enabled") then return end

			-- effects that don't seize the camera run always
			FOV.update(dt)
			DoFAuto.update(dt)
			MotionBlur.update(dt)

			-- Freecam owns the camera while active → skip our offsets
			if Freecam.isActive() then return end

			-- contention detection
			local foreignOwner = (cam.CameraType == Enum.CameraType.Scriptable)
				and not PhotoMode.isActive()
			if foreignOwner and not warnedContention then
				warnedContention = true
				ctx.log.warn("Another script controls the camera — running offset-only (non-exclusive).")
			end

			-- additive shake offset (safe even under a foreign owner)
			local offset = Shake.getOffset(dt)
			if offset then
				cam.CFrame = cam.CFrame * offset
			end
		end))

		ctx.log.debug("CameraFX online")
		return CameraFX
	end

	function CameraFX.setQuality(_q) end

	function CameraFX.stop()
		if CameraFX._maid then CameraFX._maid:clean() end
	end

	return CameraFX
end
