--!nonstrict
--[[
	postfx/Dither.lua  —  FAKED overlay
	-----------------------------------------------------------------------------
	A near-transparent tiled blue-noise overlay that breaks up the visible banding
	you get in smooth gradients (skies, fog, soft bloom). Authored once into a small
	EditableImage and left static (unlike grain it does not animate).

	HARD TRUTH: this hides 8-bit gradient banding; it does NOT anti-alias 3D edges —
	the engine gives us no MSAA/FXAA control. Feature-detected; no-op (with a logged
	note) when EditableImage is unavailable.
]]

return function(require)
	local State = require("core/State")

	local Dither = {}
	Dither.id = "postfx/Dither"

	local SIZE = 64
	local PIXELS = SIZE * SIZE

	function Dither.start(ctx)
		local maid = ctx.maid:childMaid()
		Dither._maid = maid

		if not ctx.platform.caps.editableImage then
			ctx.log.debug("Dither: EditableImage unavailable — skipped")
			return Dither
		end

		local Snapshot = ctx.snapshot
		local Util = ctx.util
		local rng = Random.new(7)

		local label = Snapshot.create("ImageLabel", {
			Name = "Dither",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(SIZE, SIZE),
			ImageTransparency = 0.96,
			ZIndex = 61, Active = false,
		}, ctx.gui)

		local editable, writeFn = Util.bindEditableImage(label, SIZE)
		if not writeFn then
			ctx.log.debug("Dither: EditableImage bind failed — skipped")
			label:Destroy()
			return Dither
		end

		-- static blue-ish noise: high-frequency, value-balanced around mid-grey so it
		-- nudges pixels both up and down across a band edge.
		local buffer = table.create(PIXELS * 4, 0)
		for i = 0, PIXELS - 1 do
			local n = rng:NextNumber()
			local o = i * 4
			buffer[o + 1] = n
			buffer[o + 2] = n
			buffer[o + 3] = n
			buffer[o + 4] = 1
		end
		writeFn(buffer)

		local function apply()
			local on = State.get("overlay_dither")
			label.Visible = on
		end
		maid:give(State.observe("overlay_dither", apply))
		apply()

		return Dither
	end

	function Dither.stop()
		if Dither._maid then Dither._maid:clean() end
	end

	return Dither
end
