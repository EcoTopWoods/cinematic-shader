--!nonstrict
--[[
	camera/Freecam.lua
	-----------------------------------------------------------------------------
	WASD / gamepad fly camera for screenshots and scene scouting.

	This is one of the few places we DELIBERATELY seize the camera: on enable we
	capture CameraType (Snapshot) and set it Scriptable, lock the mouse to centre,
	and drive the camera ourselves. On disable we restore everything. The session is
	owned by a dedicated Maid so repeated toggles never leak, and teardown disables a
	live session automatically.
]]

return function(require)
	local State = require("core/State")
	local Maid = require("core/Maid")
	local Util = require("core/Util")

	local Freecam = {}
	Freecam.id = "camera/Freecam"
	local active = false

	function Freecam.start(ctx)
		Freecam._ctx = ctx
		Freecam._maid = ctx.maid:childMaid()
		-- ensure a live session is torn down on unload
		Freecam._maid:give(function() if active then Freecam.toggle(false) end end)
		return Freecam
	end

	function Freecam.isActive() return active end

	function Freecam.toggle(on)
		if on == nil then on = not active end
		if on == active then return end
		if on then Freecam._enable() else Freecam._disable() end
	end

	function Freecam._enable()
		local ctx = Freecam._ctx
		local cam = ctx.camera()
		if not cam then return end
		active = true
		local UIS = ctx.services.UserInputService
		local session = Maid.new()
		Freecam._session = session

		ctx.snapshot.capture(cam, "CameraType")
		cam.CameraType = Enum.CameraType.Scriptable

		local prevMouseBehavior = UIS.MouseBehavior
		UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
		session:give(function() pcall(function() UIS.MouseBehavior = prevMouseBehavior end) end)

		-- orientation state seeded from current camera
		local look = cam.CFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		local pitch = math.asin(Util.clamp(look.Y, -1, 1))
		local pos = cam.CFrame.Position

		-- gamepad thumbstick cache
		local moveStick, lookStick = Vector2.zero, Vector2.zero
		session:give(UIS.InputChanged:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				moveStick = Vector2.new(input.Position.X, input.Position.Y)
			elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
				lookStick = Vector2.new(input.Position.X, input.Position.Y)
			end
		end))

		local SENS = 0.003
		session:give(ctx.services.RunService.PreRender:Connect(function(dt)
			-- mouse look
			local md = UIS:GetMouseDelta()
			yaw -= md.X * SENS
			pitch = Util.clamp(pitch - md.Y * SENS, -1.4, 1.4)
			-- gamepad look
			yaw -= lookStick.X * dt * 2
			pitch = Util.clamp(pitch + lookStick.Y * dt * 2, -1.4, 1.4)

			local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
			-- movement basis
			local fwd = rot.LookVector
			local right = rot.RightVector
			local speed = (UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 120 or 48) * dt
			local move = Vector3.zero
			if UIS:IsKeyDown(Enum.KeyCode.W) then move += fwd end
			if UIS:IsKeyDown(Enum.KeyCode.S) then move -= fwd end
			if UIS:IsKeyDown(Enum.KeyCode.D) then move += right end
			if UIS:IsKeyDown(Enum.KeyCode.A) then move -= right end
			if UIS:IsKeyDown(Enum.KeyCode.E) or UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
			if UIS:IsKeyDown(Enum.KeyCode.Q) then move -= Vector3.yAxis end
			-- gamepad move
			move += fwd * moveStick.Y + right * moveStick.X
			if move.Magnitude > 0 then move = move.Unit end
			pos += move * speed

			cam.CFrame = CFrame.new(pos) * rot
		end))

		Freecam._maid:give(session)
		if ctx.notify then pcall(ctx.notify, "Freecam", "WASD + mouse to fly, Shift = fast. Toggle again to exit.", 4) end
		ctx.log.debug("Freecam enabled")
	end

	function Freecam._disable()
		local ctx = Freecam._ctx
		active = false
		if Freecam._session then
			Freecam._session:clean()
			Freecam._session = nil
		end
		local cam = ctx.camera()
		if cam then cam.CameraType = Enum.CameraType.Custom end
		ctx.log.debug("Freecam disabled")
	end

	function Freecam.stop() if Freecam._maid then Freecam._maid:clean() end end

	return Freecam
end
