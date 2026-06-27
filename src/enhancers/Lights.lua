--!nonstrict
--[[
	enhancers/Lights.lua
	-----------------------------------------------------------------------------
	Light polish for existing PointLight/SpotLight/SurfaceLight (Scanner kind
	"light"). Three layers, each individually toggleable:

	  1. SHADOWS (enh_light_shadows) — most games ship lights with Shadows=false.
	     Turning it on is the single biggest indoor/night upgrade: streetlamps and
	     room lights start casting real shadows under Future lighting. Captured via
	     Snapshot so unload restores the original exactly.

	  2. STREET BEAMS (enh_light_beams) — the developed-night-city look. Each light
	     gets a tight inner cone + soft outer halo (camera-facing Beams), visible
	     ONLY at night (driven by the real sun direction). Coverage-capped and
	     near-camera only so it never floods a busy place. Beam Color/Transparency
	     sequences are cached/set-once — zero per-frame allocation; we only flip
	     .Enabled and nudge Brightness.

	  3. FLICKER (enh_lights_repair) — gentle noise wobble around base brightness
	     for a lived-in feel.

	Budgeted to lights within RADIUS of the camera; rig creation is spread across
	frames (CREATE_BUDGET/frame) so spawning a lit district never spikes a frame.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Lights = {}
	Lights.id = "enhancers/Lights"

	local RADIUS = 160          -- only service lights within this of the camera
	local CREATE_BUDGET = 2     -- new beam rigs built per frame (spreads cost over frames)

	-- cached, set-ONCE beam transparency profiles (never rebuilt per frame).
	local INNER_TRANSP = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.16, 0.45),
		NumberSequenceKeypoint.new(0.85, 0.72),
		NumberSequenceKeypoint.new(1, 1),
	})
	local OUTER_TRANSP = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.8),
		NumberSequenceKeypoint.new(0.8, 0.92),
		NumberSequenceKeypoint.new(1, 1),
	})

	function Lights.start(ctx)
		local maid = ctx.maid:childMaid()
		Lights._maid = maid
		local Snapshot = ctx.snapshot
		local L = ctx.services.Lighting
		local Scanner = require("detection/Scanner")
		local isMobile = ctx.platform.isMobile

		Lights._q = ctx.getQuality()
		local MAX_RIGS = isMobile and 24 or 120

		-- light -> { base = brightness, baseShadows = bool, rig = {...}|nil }
		local lights = setmetatable({}, { __mode = "k" })
		local rigCount = 0

		local function enrollPart(part)
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("Light") and not lights[child] then
					Snapshot.capture(child, "Brightness")
					Snapshot.capture(child, "Shadows")
					lights[child] = { base = child.Brightness, parent = part }
					if State.get("enh_light_shadows") then
						pcall(function() child.Shadows = true end)
					end
				end
			end
		end

		for _, p in ipairs(Scanner.getByKind("light")) do enrollPart(p) end
		maid:give(Scanner.onClassified:Connect(function(part, cls)
			if cls.kind == "light" then enrollPart(part) end
		end))

		-- toggle shadows live
		maid:give(State.observe("enh_light_shadows", function(on)
			for light, info in pairs(lights) do
				if light.Parent then pcall(function() light.Shadows = on end) end
			end
		end))

		-- build a beam rig (inner cone + outer halo) for one light. Returns rig or nil.
		local function buildRig(light, part)
			if rigCount >= MAX_RIGS then return nil end
			local range = light.Range
			if range < 8 then return nil end
			local a0 = Snapshot.create("Attachment", { Name = "CinLightBeamA0" }, part)
			local a1 = Snapshot.create("Attachment", { Name = "CinLightBeamA1" }, part)
			a0.WorldPosition = part.Position
			a1.WorldPosition = part.Position + Vector3.new(0, -1, 0) * (range * 0.82)
			local col = ColorSequence.new(light.Color)
			local inner = Snapshot.create("Beam", {
				Name = "CinLightBeamInner", Attachment0 = a0, Attachment1 = a1,
				Color = col, Transparency = INNER_TRANSP, LightEmission = 1, LightInfluence = 0,
				FaceCamera = true, Segments = 6, Enabled = false,
				Width0 = math.clamp(range * 0.05, 0.25, 1.4),
				Width1 = math.clamp(range * 0.11, 0.5, 3.0),
			}, part)
			local outer = Snapshot.create("Beam", {
				Name = "CinLightBeamOuter", Attachment0 = a0, Attachment1 = a1,
				Color = col, Transparency = OUTER_TRANSP, LightEmission = 1, LightInfluence = 0,
				FaceCamera = true, Segments = 8, Enabled = false,
				Width0 = math.clamp(range * 0.16, 0.6, 4.5),
				Width1 = math.clamp(range * 0.32, 1.5, 9.0),
			}, part)
			rigCount += 1
			return { a0 = a0, a1 = a1, inner = inner, outer = outer }
		end

		local t = 0
		local accum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			t += dt
			accum += dt
			if accum < 0.08 then return end  -- run the pass at ~12 Hz, not every frame
			accum = 0
			local flickerOn = State.get("enh_enabled") and State.get("enh_lights_repair")
			local beamsOn = State.get("enh_enabled") and State.get("enh_light_beams")
			local cam = ctx.camera()
			local camPos = cam and cam.CFrame.Position or Vector3.zero

			-- night factor from the REAL sun position (below horizon → night).
			local sunY = L:GetSunDirection().Y
			local night = Util.clamp((0.04 - sunY) * 3.5, 0, 1)
			local beamsVisible = beamsOn and night > 0.45
			local created = 0

			for light, info in pairs(lights) do
				local part = light.Parent
				if part and part:IsA("BasePart") then
					local near = (part.Position - camPos).Magnitude <= RADIUS

					-- flicker
					if flickerOn and near then
						local flick = Util.noise(t * 4 + part.Position.X * 0.05, 0, 0)
						light.Brightness = math.max(0, info.base * (1 + flick * 0.12))
					elseif not flickerOn then
						light.Brightness = info.base
					end

					-- street beams: lazily build (budgeted) when near + night, toggle visibility
					if beamsVisible and near then
						-- Build new rigs only on HEALTHY frames so sweeping past a row of
						-- lamps (360 spin) can't stack instance-creation stutter. Existing
						-- rigs still just toggle (cheap) — only first discovery is deferred.
						local healthy = (ctx.bus.fps or 60) > 42
						if not info.rig and created < CREATE_BUDGET and healthy then
							info.rig = buildRig(light, part)
							created += 1
						end
						if info.rig then
							info.rig.inner.Enabled = true
							info.rig.outer.Enabled = true
						end
					elseif info.rig then
						info.rig.inner.Enabled = false
						info.rig.outer.Enabled = false
					end
				end
			end
		end))

		ctx.log.debug("Light polish online (shadows + street beams)")
		return Lights
	end

	function Lights.setQuality(q) Lights._q = math.clamp(q, 0, 1) end
	function Lights.stop() if Lights._maid then Lights._maid:clean() end end

	return Lights
end
