--!nonstrict
--[[
	weather/Rain.lua  —  precipitation emitter
	-----------------------------------------------------------------------------
	A single ParticleEmitter attached to the Weather controller's camera-following
	volume part. We use the REAL ParticleEmitter.Squash property to stretch particles
	along their fall direction so they read as rain streaks (no external texture
	needed). Every NumberSequence/ColorSequence is built ONCE at start; at runtime we
	mutate only scalar props (Rate, Acceleration) — zero per-frame allocation.

	Rain.set(rate01, wind01) is called by the Weather controller each frame.
]]

return function(require)
	local Rain = {}
	Rain.id = "weather/Rain"

	-- cached sequences (built once)
	local SIZE = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 0.18),
	})
	local SQUASH = NumberSequence.new({  -- stretch into streaks
		NumberSequenceKeypoint.new(0, 6),
		NumberSequenceKeypoint.new(1, 6),
	})
	local TRANSP = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0.7),
	})
	local COLOR = ColorSequence.new(Color3.fromRGB(170, 185, 205))

	local MAX_RATE = 1400

	function Rain.start(ctx, volumePart)
		local maid = ctx.maid:childMaid()
		Rain._maid = maid
		local Snapshot = ctx.snapshot

		local emitter = Snapshot.create("ParticleEmitter", {
			Name = "Rain",
			Rate = 0,
			Enabled = false,
			Lifetime = NumberRange.new(0.5, 0.7),
			Speed = NumberRange.new(120, 150),
			SpreadAngle = Vector2.new(6, 6),
			Acceleration = Vector3.new(0, -180, 0),
			Drag = 0,
			LockedToPart = false,
			EmissionDirection = Enum.NormalId.Bottom,
			Size = SIZE,
			Squash = SQUASH,
			Transparency = TRANSP,
			Color = COLOR,
			LightInfluence = 1,
			Brightness = 0.5,
			ZOffset = 0,
		}, volumePart)
		Rain._emitter = emitter

		ctx.log.debug("Rain emitter ready")
		return Rain
	end

	-- rate01 in 0..1, wind01 in 0..1 (signed by controller via direction)
	function Rain.set(rate01, windVec)
		local e = Rain._emitter
		if not e then return end
		rate01 = math.clamp(rate01, 0, 1)
		e.Enabled = rate01 > 0.01
		e.Rate = MAX_RATE * rate01
		if windVec then
			e.Acceleration = Vector3.new(windVec.X, -180, windVec.Z)
		end
	end

	function Rain.stop()
		if Rain._maid then Rain._maid:clean() end
	end

	return Rain
end
