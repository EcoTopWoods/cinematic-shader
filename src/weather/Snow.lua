--!nonstrict
--[[
	weather/Snow.lua  —  precipitation emitter
	-----------------------------------------------------------------------------
	Soft, slow-drifting flakes via one ParticleEmitter on the Weather volume part.
	Cached sequences; runtime mutates only Rate + Acceleration (wind drift). Snow
	does not soak surfaces the way rain does, so the controller applies only a modest
	wetness boost for it.
]]

return function(require)
	local Snow = {}
	Snow.id = "weather/Snow"

	local SIZE = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	local TRANSP = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.85, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	local COLOR = ColorSequence.new(Color3.fromRGB(248, 250, 255))

	local MAX_RATE = 600

	function Snow.start(ctx, volumePart)
		local maid = ctx.maid:childMaid()
		Snow._maid = maid
		local Snapshot = ctx.snapshot

		local emitter = Snapshot.create("ParticleEmitter", {
			Name = "Snow",
			Rate = 0,
			Enabled = false,
			Lifetime = NumberRange.new(3, 4.5),
			Speed = NumberRange.new(8, 14),
			SpreadAngle = Vector2.new(25, 25),
			Acceleration = Vector3.new(0, -10, 0),
			Drag = 1.5,
			RotSpeed = NumberRange.new(-40, 40),
			LockedToPart = false,
			EmissionDirection = Enum.NormalId.Bottom,
			Size = SIZE,
			Transparency = TRANSP,
			Color = COLOR,
			LightInfluence = 1,
			Brightness = 1,
		}, volumePart)
		Snow._emitter = emitter

		ctx.log.debug("Snow emitter ready")
		return Snow
	end

	function Snow.set(rate01, windVec)
		local e = Snow._emitter
		if not e then return end
		rate01 = math.clamp(rate01, 0, 1)
		e.Enabled = rate01 > 0.01
		e.Rate = MAX_RATE * rate01
		if windVec then
			e.Acceleration = Vector3.new(windVec.X * 1.5, -10, windVec.Z * 1.5)
		end
	end

	function Snow.stop()
		if Snow._maid then Snow._maid:clean() end
	end

	return Snow
end
