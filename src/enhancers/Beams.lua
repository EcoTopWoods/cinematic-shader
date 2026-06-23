--!nonstrict
--[[
	enhancers/Beams.lua
	-----------------------------------------------------------------------------
	FAKED volumetric god-rays using Beam instances.

	HARD TRUTH: Roblox has no volumetric light scattering. We fake light shafts with
	a small, coverage-capped set of Beams aligned to the sun direction on a camera-
	following rig, faint and additive-feeling via low transparency + LightEmission.
	Beam ColorSequence/NumberSequence are cached ONCE; at runtime we only fade
	transparency (enh_godray_strength) and re-aim the rig along the sun. We disable
	them at night (sun below horizon) automatically.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Beams = {}
	Beams.id = "enhancers/Beams"
	local SHAFTS = 5

	-- cached transparency profile (built ONCE; runtime modulates Width, not this).
	local TRANSP = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.82),
		NumberSequenceKeypoint.new(1, 1),
	})

	function Beams.start(ctx)
		local maid = ctx.maid:childMaid()
		Beams._maid = maid
		local Snapshot = ctx.snapshot
		local L = ctx.services.Lighting

		local rig = Snapshot.create("Part", {
			Name = "GodRayRig",
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			Transparency = 1, Size = Vector3.new(1, 1, 1),
		}, ctx.worldFolder)

		local shafts = {}
		local rng = Random.new(11)
		for i = 1, SHAFTS do
			local a0 = Snapshot.create("Attachment", { Name = "A0_" .. i }, rig)
			local a1 = Snapshot.create("Attachment", { Name = "A1_" .. i }, rig)
			local beam = Snapshot.create("Beam", {
				Name = "GodRay_" .. i,
				Attachment0 = a0, Attachment1 = a1,
				Color = ColorSequence.new(Color3.fromRGB(255, 244, 214)),
				Transparency = TRANSP,
				LightEmission = 1, LightInfluence = 0,
				FaceCamera = true,
				Width0 = 6, Width1 = 14,
				Segments = 4,
			}, rig)
			shafts[i] = { a0 = a0, a1 = a1, beam = beam, jitter = rng:NextNumber(-0.15, 0.15) }
		end

		local accum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			local on = State.get("enh_enabled") and State.get("enh_godrays")
			accum += dt
			if accum < 0.1 then return end
			accum = 0
			local sunDir = L:GetSunDirection()      -- unit vector toward the sun
			local daytime = sunDir.Y > 0.02         -- sun above horizon
			local strength = State.get("enh_godray_strength")
			local cam = ctx.camera()
			local camPos = cam and cam.CFrame.Position or Vector3.zero
			for _, s in ipairs(shafts) do
				s.beam.Enabled = on and daytime and strength > 0.01
				if s.beam.Enabled then
					-- shafts hang in front of the camera, slanted along the sun.
					local base = camPos + cam.CFrame.LookVector * 40
					local offset = Vector3.new(s.jitter * 60, 0, s.jitter * 60)
					s.a0.WorldPosition = base + offset + sunDir * 60
					s.a1.WorldPosition = base + offset - sunDir * 30
					-- modulate width (not the cached transparency seq) with strength
					-- and sun elevation — wider/brighter shafts near midday.
					local w = strength * Util.clamp(sunDir.Y, 0.1, 1)
					s.beam.Width0 = 4 + w * 6
					s.beam.Width1 = 10 + w * 16
				end
			end
		end))

		ctx.log.debug("God-ray beams online")
		return Beams
	end

	function Beams.setQuality(_q) end
	function Beams.stop() if Beams._maid then Beams._maid:clean() end end

	return Beams
end
