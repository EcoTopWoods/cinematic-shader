--!nonstrict
--[[
	postfx/Vignette.lua  —  FAKED overlay
	-----------------------------------------------------------------------------
	There is NO native vignette post-effect in Roblox. We fake edge darkening with
	four black edge Frames, each carrying a UIGradient whose transparency ramps from
	opaque (screen edge) to transparent (inward). Overlapping corners read darkest —
	exactly what a lens vignette does.

	This is a GUI overlay: it darkens pixels but does NOT anti-alias or affect the
	3D scene. NumberSequences are cached and only rebuilt when intensity changes
	(never per-frame).
]]

return function(require)
	local State = require("core/State")

	local Vignette = {}
	Vignette.id = "postfx/Vignette"

	function Vignette.start(ctx)
		local maid = ctx.maid:childMaid()
		Vignette._maid = maid
		local Snapshot = ctx.snapshot

		local root = Snapshot.create("Frame", {
			Name = "Vignette",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 50,
			Active = false,            -- never intercept input
		}, ctx.gui)

		-- (size, position, gradientRotation, edgeAtOffset0)
		-- edgeAtOffset0=true means offset 0 is the opaque screen edge.
		local edges = {
			{ UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0),    90, true  }, -- top
			{ UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0.68), 90, false }, -- bottom
			{ UDim2.fromScale(0.32, 1), UDim2.fromScale(0, 0),    0,  true  }, -- left
			{ UDim2.fromScale(0.32, 1), UDim2.fromScale(0.68, 0), 0,  false }, -- right
		}

		local gradients = {}
		for _, e in ipairs(edges) do
			local frame = Snapshot.create("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				Size = e[1], Position = e[2],
				ZIndex = 50, Active = false,
			}, root)
			local grad = Snapshot.create("UIGradient", { Rotation = e[3] }, frame)
			gradients[#gradients + 1] = { grad = grad, edgeAtZero = e[4] }
		end

		local function rebuild(intensity)
			-- opaque-end alpha = 1-intensity (Transparency 0 = fully opaque black)
			local opaque = 1 - math.clamp(intensity, 0, 1)
			for _, g in ipairs(gradients) do
				local seq
				if g.edgeAtZero then
					seq = NumberSequence.new({
						NumberSequenceKeypoint.new(0, opaque),
						NumberSequenceKeypoint.new(1, 1),
					})
				else
					seq = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(1, opaque),
					})
				end
				g.grad.Transparency = seq
			end
		end

		local function apply()
			local on = State.get("overlay_vignette")
			root.Visible = on
			if on then rebuild(State.get("overlay_vignette_intensity")) end
		end

		maid:give(State.observeMany({ "overlay_vignette", "overlay_vignette_intensity" }, apply))
		apply()
		return Vignette
	end

	function Vignette.stop()
		if Vignette._maid then Vignette._maid:clean() end
	end

	return Vignette
end
