--!nonstrict
--[[
	postfx/Letterbox.lua  —  cinematic bars
	-----------------------------------------------------------------------------
	Two black bars (top + bottom) that crop the frame to a target aspect ratio
	(overlay_letterbox_ratio, e.g. 2.39 anamorphic scope). The bar height is derived
	from the live viewport aspect vs the target aspect, so it is correct on any
	screen and recomputes on resize. Bars tween in/out for a smooth reveal.

	This is the one "overlay" that is genuinely real (it IS just black bars) rather
	than an approximation of a shader effect. GUI Frames only — no scene impact.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Letterbox = {}
	Letterbox.id = "postfx/Letterbox"

	function Letterbox.start(ctx)
		local maid = ctx.maid:childMaid()
		Letterbox._maid = maid
		local Snapshot = ctx.snapshot
		local TweenService = ctx.services.TweenService

		local top = Snapshot.create("Frame", {
			Name = "LetterboxTop", BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 0), Position = UDim2.fromScale(0, 0),
			ZIndex = 60, Active = false, Visible = false,
		}, ctx.gui)
		local bottom = Snapshot.create("Frame", {
			Name = "LetterboxBottom", BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 0), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1),
			ZIndex = 60, Active = false, Visible = false,
		}, ctx.gui)

		local function barFraction()
			local cam = ctx.camera()
			local vp = (cam and cam.ViewportSize) or Vector2.new(16, 9)
			local viewAspect = vp.X / math.max(1, vp.Y)
			local target = State.get("overlay_letterbox_ratio")
			if target <= viewAspect then return 0 end             -- screen already wider
			return Util.clamp((1 - viewAspect / target) / 2, 0, 0.25)
		end

		local function apply(animate)
			local on = State.get("overlay_letterbox")
			local frac = on and barFraction() or 0
			local goal = UDim2.new(1, 0, frac, 0)
			top.Visible = frac > 0
			bottom.Visible = frac > 0
			if animate then
				local ti = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				pcall(function() TweenService:Create(top, ti, { Size = goal }):Play() end)
				pcall(function() TweenService:Create(bottom, ti, { Size = goal }):Play() end)
			else
				top.Size, bottom.Size = goal, goal
			end
		end

		maid:give(State.observeMany({ "overlay_letterbox", "overlay_letterbox_ratio" }, function() apply(true) end))
		local cam = ctx.camera()
		if cam then
			maid:give(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() apply(false) end))
		end
		apply(false)
		return Letterbox
	end

	function Letterbox.stop()
		if Letterbox._maid then Letterbox._maid:clean() end
	end

	return Letterbox
end
