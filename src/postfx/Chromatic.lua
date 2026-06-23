--!nonstrict
--[[
	postfx/Chromatic.lua  —  FAKED overlay (chromatic aberration)
	-----------------------------------------------------------------------------
	There is NO native chromatic-aberration post-effect in Roblox. Real CA resamples
	the framebuffer per colour channel with a radial offset that grows toward the
	edges — we have NO framebuffer access, so a true version is impossible.

	What we CAN do legally is paint subtle COLOUR FRINGING at the screen edges: a red
	gradient bleeding in from the left edge and a complementary blue/cyan gradient
	from the right. That reproduces the *visual signature* of lens CA (coloured edge
	fringe) without claiming to be the real per-channel resample. Kept deliberately
	subtle (capped alpha) so it reads as a lens artefact, not a colour wash.

	GUI overlay only: does not anti-alias or alter the 3D scene. Sequences cached;
	rebuilt only when intensity changes.
]]

return function(require)
	local State = require("core/State")

	local Chromatic = {}
	Chromatic.id = "postfx/Chromatic"

	function Chromatic.start(ctx)
		local maid = ctx.maid:childMaid()
		Chromatic._maid = maid
		local Snapshot = ctx.snapshot

		local root = Snapshot.create("Frame", {
			Name = "ChromaticAberration",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 48, Active = false,
		}, ctx.gui)

		-- two thin coloured edge bands, each faded inward by a UIGradient.
		local function edgeBand(color, posX)
			local f = Snapshot.create("Frame", {
				BackgroundColor3 = color, BorderSizePixel = 0,
				Size = UDim2.fromScale(0.14, 1), Position = UDim2.fromScale(posX, 0),
				ZIndex = 48, Active = false,
			}, root)
			local g = Snapshot.create("UIGradient", { Rotation = 0 }, f)
			return g
		end
		local leftG = edgeBand(Color3.fromRGB(255, 48, 48), 0)        -- opaque toward x=0
		local rightG = edgeBand(Color3.fromRGB(48, 150, 255), 0.86)   -- opaque toward x=1

		local function rebuild(intensity)
			-- cap fringe at ~45% alpha so it stays a subtle lens artefact.
			local opaque = 1 - math.clamp(intensity, 0, 1) * 0.45
			leftG.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, opaque), NumberSequenceKeypoint.new(1, 1),
			})
			rightG.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, opaque),
			})
		end

		local function apply()
			local on = State.get("overlay_chromatic")
			root.Visible = on
			if on then rebuild(State.get("overlay_chromatic_intensity")) end
		end

		maid:give(State.observeMany({ "overlay_chromatic", "overlay_chromatic_intensity" }, apply))
		apply()
		return Chromatic
	end

	function Chromatic.stop()
		if Chromatic._maid then Chromatic._maid:clean() end
	end

	return Chromatic
end
