--!nonstrict
--[[
	enhancers/Particles.lua
	-----------------------------------------------------------------------------
	Ambient floating dust motes near the camera — the cheap trick that makes air feel
	volumetric in light shafts. One ParticleEmitter on a camera-following part; cached
	sequences; only Rate is mutated at runtime (scaled by quality + the enh_dust
	toggle). Zero per-frame allocation.
]]

return function(require)
	local State = require("core/State")

	local Particles = {}
	Particles.id = "enhancers/Particles"

	local SIZE = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.04),
		NumberSequenceKeypoint.new(1, 0.06),
	})
	local TRANSP = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.6),
		NumberSequenceKeypoint.new(0.7, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	local COLOR = ColorSequence.new(Color3.fromRGB(255, 250, 235))
	local BASE_RATE = 40

	function Particles.start(ctx)
		local maid = ctx.maid:childMaid()
		Particles._maid = maid
		local Snapshot = ctx.snapshot
		Particles._q = ctx.getQuality()

		local part = Snapshot.create("Part", {
			Name = "DustVolume",
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			Transparency = 1, Size = Vector3.new(60, 30, 60),
		}, ctx.worldFolder)

		local emitter = Snapshot.create("ParticleEmitter", {
			Name = "Dust",
			Rate = 0, Enabled = false,
			Lifetime = NumberRange.new(4, 8),
			Speed = NumberRange.new(0.4, 1.2),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0.3, -0.2, 0),
			Drag = 1,
			RotSpeed = NumberRange.new(-15, 15),
			Size = SIZE, Transparency = TRANSP, Color = COLOR,
			LightInfluence = 1, LightEmission = 0.4,
		}, part)

		maid:give(ctx.services.RunService.Heartbeat:Connect(function()
			local on = State.get("enh_enabled") and State.get("enh_dust")
			emitter.Enabled = on
			if on then
				emitter.Rate = BASE_RATE * (Particles._q or 1)
				local cam = ctx.camera()
				if cam then part.CFrame = cam.CFrame end
			end
		end))

		ctx.log.debug("Dust particles online")
		return Particles
	end

	function Particles.setQuality(q) Particles._q = math.clamp(q, 0, 1) end
	function Particles.stop() if Particles._maid then Particles._maid:clean() end end

	return Particles
end
