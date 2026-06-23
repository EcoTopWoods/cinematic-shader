--!nonstrict
--[[
	camera/MotionBlur.lua  —  FAKED
	-----------------------------------------------------------------------------
	HARD TRUTH: there is NO MotionBlurEffect in Roblox. We fake velocity smear two
	cheap ways that combine acceptably:
	  * a faint full-screen GUI overlay whose alpha rises with camera movement
	    (bus.camDelta), giving a sense of speed blur at the edges,
	  * a tiny pulse on the owned BlurEffect.Size (bus.pipeline.blur) on fast motion.
	Neither truly smears per-pixel by velocity — documented as an approximation.
	update(dt) is called from the CameraFX loop. Overlay created once.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local MotionBlur = {}
	MotionBlur.id = "camera/MotionBlur"

	function MotionBlur.start(ctx)
		local maid = ctx.maid:childMaid()
		MotionBlur._maid = maid
		MotionBlur._ctx = ctx
		local Snapshot = ctx.snapshot

		MotionBlur._overlay = Snapshot.create("Frame", {
			Name = "MotionBlur",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 40, Active = false, Visible = true,
		}, ctx.gui)
		-- a soft inward gradient so the smear reads at the frame edges
		local grad = Snapshot.create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.4, 1),
				NumberSequenceKeypoint.new(0.6, 1),
				NumberSequenceKeypoint.new(1, 0.2),
			}),
		}, MotionBlur._overlay)
		MotionBlur._smear = 0
		return MotionBlur
	end

	function MotionBlur.update(dt)
		local ctx = MotionBlur._ctx
		if not ctx then return end
		local overlay = MotionBlur._overlay
		if not overlay then return end
		if not State.get("cam_motionblur") then
			overlay.BackgroundTransparency = 1
			return
		end
		local amount = State.get("cam_motionblur_amount")
		-- normalise camera delta into 0..1 (delta is studs/frame; ~3 = fast)
		local d = Util.clamp((ctx.bus.camDelta or 0) / 3, 0, 1)
		MotionBlur._smear = Util.damp(MotionBlur._smear, d, 0.08, dt)
		overlay.BackgroundTransparency = 1 - MotionBlur._smear * amount * 0.5
		local blur = ctx.bus.pipeline and ctx.bus.pipeline.blur
		if blur then
			blur.Size = MotionBlur._smear * amount * 8
		end
	end

	function MotionBlur.stop() if MotionBlur._maid then MotionBlur._maid:clean() end end

	return MotionBlur
end
