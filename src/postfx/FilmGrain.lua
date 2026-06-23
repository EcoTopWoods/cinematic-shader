--!nonstrict
--[[
	postfx/FilmGrain.lua  —  FAKED overlay
	-----------------------------------------------------------------------------
	There is NO native film-grain effect. We author animated monochrome noise into a
	small EditableImage (CPU pixel work) tiled across the screen at low opacity, and
	regenerate it a few times a second for the "moving grain" look.

	EditableImage requires an ID-verified 13+ creator in published places, so it is
	FEATURE-DETECTED (ctx.platform.caps.editableImage). When unavailable we degrade
	to a very subtle full-screen alpha flicker (a crude luminance dither) rather than
	failing. The pixel buffer is reused in-place — no per-frame table allocation; the
	regen itself is throttled (~8 Hz), not per-frame.
]]

return function(require)
	local State = require("core/State")

	local FilmGrain = {}
	FilmGrain.id = "postfx/FilmGrain"

	local SIZE = 128
	local PIXELS = SIZE * SIZE
	local qualityMul = 1

	function FilmGrain.start(ctx)
		local maid = ctx.maid:childMaid()
		FilmGrain._maid = maid
		local Snapshot = ctx.snapshot
		local Util = ctx.util
		local rng = Random.new(1337)

		local label = Snapshot.create("ImageLabel", {
			Name = "FilmGrain",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(SIZE, SIZE),
			ImageTransparency = 1,
			ZIndex = 60, Active = false,
		}, ctx.gui)

		local editable, writeFn
		if ctx.platform.caps.editableImage then
			editable, writeFn = Util.bindEditableImage(label, SIZE)
		end

		-- reused RGBA buffer (flat, 0..1). Allocated ONCE.
		local buffer = table.create(PIXELS * 4, 0)

		local function regen()
			-- monochrome noise into alpha; rgb white so tint stays neutral.
			for i = 0, PIXELS - 1 do
				local n = rng:NextNumber()
				local o = i * 4
				buffer[o + 1] = 1
				buffer[o + 2] = 1
				buffer[o + 3] = 1
				buffer[o + 4] = n -- alpha (final opacity scaled by ImageTransparency)
			end
			if writeFn then writeFn(buffer) end
		end

		if writeFn then
			regen()
		else
			ctx.log.debug("FilmGrain: EditableImage unavailable — using alpha-flicker fallback")
		end

		local accum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			if not State.get("overlay_grain") then
				if label.Visible then label.Visible = false end
				return
			end
			label.Visible = true
			local intensity = State.get("overlay_grain_intensity") * qualityMul
			accum += dt
			if writeFn then
				label.ImageTransparency = 1 - math.clamp(intensity, 0, 1)
				if accum >= 0.12 then -- ~8 Hz regen
					accum = 0
					regen()
				end
			else
				-- fallback: gentle per-frame alpha flicker on a flat tint
				label.ImageTransparency = 1 - math.clamp(intensity, 0, 1) * (0.5 + 0.5 * rng:NextNumber()) * 0.25
			end
		end))

		return FilmGrain
	end

	function FilmGrain.setQuality(q)
		qualityMul = math.clamp(q, 0, 1)
	end

	function FilmGrain.stop()
		if FilmGrain._maid then FilmGrain._maid:clean() end
	end

	return FilmGrain
end
