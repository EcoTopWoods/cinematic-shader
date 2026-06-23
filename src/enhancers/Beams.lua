--!nonstrict
--[[
	enhancers/Beams.lua  —  god-rays (sun shafts)
	-----------------------------------------------------------------------------
	Roblox has no programmable volumetric scattering, BUT it ships a real, good-
	looking screen-space sun-ray effect: SunRaysEffect. It scatters rays from the
	ACTUAL sun's on-screen position and naturally fades as the sun leaves view —
	exactly what god-rays should do.

	An earlier version parked wide glowing Beam slabs in front of the camera; those
	read as blocky white shafts regardless of where the sun was. We deleted that and
	now drive SunRaysEffect (owned by postfx/Pipeline, published on bus.pipeline.sunrays)
	from real geometry: enh_godray_strength × how directly the camera faces the sun ×
	daytime. A whisper-thin pair of FaceCamera Beams is added ONLY when you look almost
	straight at the sun, as a soft accent — never wide, never opaque.

	Honest framing: this is screen-space sun scattering, not true volumetrics.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Beams = {}
	Beams.id = "enhancers/Beams"

	-- cached, very faint accent-beam transparency (built ONCE).
	local ACCENT_TRANSP = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})

	function Beams.start(ctx)
		local maid = ctx.maid:childMaid()
		Beams._maid = maid
		local Snapshot = ctx.snapshot
		local L = ctx.services.Lighting
		Beams._q = ctx.getQuality()

		-- two thin accent shafts on a camera-following rig (subtle, sun-gated).
		local rig = Snapshot.create("Part", {
			Name = "GodRayRig", Anchored = true, CanCollide = false,
			CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(1, 1, 1),
		}, ctx.worldFolder)
		local accents = {}
		for i = 1, 2 do
			local a0 = Snapshot.create("Attachment", { Name = "GA0_" .. i }, rig)
			local a1 = Snapshot.create("Attachment", { Name = "GA1_" .. i }, rig)
			local beam = Snapshot.create("Beam", {
				Name = "GodRayAccent_" .. i, Attachment0 = a0, Attachment1 = a1,
				Color = ColorSequence.new(Color3.fromRGB(255, 246, 220)),
				Transparency = ACCENT_TRANSP, LightEmission = 1, LightInfluence = 0,
				FaceCamera = true, Width0 = 1.5, Width1 = 4, Segments = 5, Enabled = false,
			}, rig)
			accents[i] = { a0 = a0, a1 = a1, beam = beam, side = (i == 1) and 1 or -1 }
		end

		local accum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			accum += dt
			if accum < 0.08 then return end
			accum = 0

			local sunrays = ctx.bus.pipeline and ctx.bus.pipeline.sunrays
			local cam = ctx.camera()
			local on = State.get("enh_enabled") and State.get("enh_godrays")
			local sunDir = L:GetSunDirection()           -- unit vector toward the sun
			local daytime = math.clamp(sunDir.Y * 6, 0, 1) -- fade near horizon/night
			local facing = 0
			if cam then
				facing = math.clamp(cam.CFrame.LookVector:Dot(sunDir), 0, 1) -- 1 = staring at sun
			end
			local strength = State.get("enh_godray_strength")

			-- DRIVE THE REAL ENGINE EFFECT (the good rays).
			if sunrays then
				local target = on and (strength * 0.45 * daytime * (0.35 + 0.65 * facing)) or 0
				Snapshot.set(sunrays, "Intensity", Util.clamp(target * (Beams._q or 1), 0, 0.5))
				Snapshot.set(sunrays, "Spread", 0.9)
			end

			-- whisper-thin accent shafts, ONLY when looking almost into the sun.
			local accentOn = on and daytime > 0.2 and facing > 0.55 and strength > 0.01
			if cam and accentOn then
				local base = cam.CFrame.Position + sunDir * 80
				for _, s in ipairs(accents) do
					s.beam.Enabled = true
					local lateral = cam.CFrame.RightVector * (s.side * 5)
					s.a0.WorldPosition = base + lateral + sunDir * 40
					s.a1.WorldPosition = base + lateral - cam.CFrame.LookVector * 30
					s.beam.Width0 = 1 + strength * 1.5
					s.beam.Width1 = 3 + strength * 4
				end
			else
				for _, s in ipairs(accents) do s.beam.Enabled = false end
			end
		end))

		ctx.log.debug("God-rays online (SunRaysEffect-driven)")
		return Beams
	end

	function Beams.setQuality(q) Beams._q = math.clamp(q, 0, 1) end
	function Beams.stop() if Beams._maid then Beams._maid:clean() end end

	return Beams
end
