--!nonstrict
--[[
	reflections/Reflections.lua  —  CONTROLLER (manifest.boot)
	-----------------------------------------------------------------------------
	Glossy / wet reflective floors + reflection-probe strategy selector.

	WHAT'S REAL vs APPROXIMATED (read this before judging the realism claim):
	  * REAL engine reflection: under Future lighting, a part's `Reflectance` plus
	    `EnvironmentSpecularScale` produces genuine environment-mapped reflections,
	    and `Glass` material gives SSR/refraction. We MAXIMISE this — it's the primary,
	    real reflection. Strength is driven by a Schlick-Fresnel term so floors get
	    more reflective at grazing angles, exactly like real surfaces.
	  * APPROXIMATED: local reflections of NEARBY geometry that environment maps miss.
	    That's what the probe strategies estimate (cheap sky tint, or roving raycasts).
	    This is an SSR APPROXIMATION, never true ray tracing.

	Floor classification is delegated to detection/Scanner (material-aware, tag-driven
	via CollectionService, cached) — not a per-frame area heuristic.

	The controller owns floor Reflectance + optional Glass sheen overlays; the active
	probe sub-module supplies a per-floor reflected colour for those overlays.
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local Reflections = {}
	Reflections.id = "reflections/Reflections"

	local MAX_OVERLAYS = 10      -- cap glass sheen planes (budget)
	local FLOOR_RADIUS = 220     -- only service floors within this distance of camera
	local UPDATE_BUDGET = 12     -- floors re-evaluated per throttled tick

	function Reflections.start(ctx)
		local maid = ctx.maid:childMaid()
		Reflections._maid = maid
		local Snapshot = ctx.snapshot
		local caps = ctx.platform.caps
		local Scanner = require("detection/Scanner")

		-- floorEntry: { part=, up=, overlay=BasePart? }
		local floors = {}            -- part -> entry
		local order = {}             -- array of parts (rotating cursor)
		local cursor = 1
		local overlayCount = 0
		Reflections._q = ctx.getQuality()

		-- ── probe strategies ─────────────────────────────────────────────────
		local strategies = {}
		local active = nil
		local function getStrategy(mode)
			if mode == "Color Blend (cheap)" then
				strategies.overlay = strategies.overlay or require("reflections/OverlayReflection")
				return strategies.overlay
			elseif mode == "Raycast Probe (SSR approx.)" then
				strategies.raycast = strategies.raycast or require("reflections/RaycastProbe")
				return strategies.raycast
			end
			return nil -- "Off"
		end

		local function switchStrategy()
			local mode = State.get("reflect_mode")
			local want = getStrategy(mode)
			if want == active then return end
			if active and active.stop then pcall(active.stop) end
			active = want
			if active and active.start then
				pcall(active.start, ctx)
				-- re-register existing floors with the new strategy
				for _, entry in pairs(floors) do
					if active.register then pcall(active.register, entry) end
				end
			end
		end

		-- ── floor enrollment ─────────────────────────────────────────────────
		local function makeOverlay(entry)
			if overlayCount >= MAX_OVERLAYS then return end
			if not (State.get("reflect_glass_overlay") and caps.futureLighting) then return end
			local part = entry.part
			-- thin glass sheen plane hugging the floor's top face. Box-ish floors only.
			local size = part.Size
			local overlay = Snapshot.create("Part", {
				Name = "FloorSheen",
				Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Glass,
				Transparency = 0.6,
				Reflectance = 0.5,
				Size = Vector3.new(size.X, 0.05, size.Z),
				CFrame = part.CFrame * CFrame.new(0, size.Y / 2 + 0.03, 0),
				Color = part.Color,
			}, ctx.worldFolder)
			entry.overlay = overlay
			overlayCount += 1
		end

		local function enroll(part)
			if floors[part] then return end
			if not part:IsA("BasePart") then return end
			local entry = { part = part, up = part.CFrame.UpVector, overlay = nil }
			floors[part] = entry
			order[#order + 1] = part
			if active and active.register then pcall(active.register, entry) end
		end

		local function unenroll(part)
			local entry = floors[part]
			if not entry then return end
			if entry.overlay then overlayCount = math.max(0, overlayCount - 1) end
			if active and active.unregister then pcall(active.unregister, entry) end
			floors[part] = nil
		end

		-- seed from Scanner + subscribe to new classifications
		for _, p in ipairs(Scanner.getFloors()) do enroll(p) end
		maid:give(Scanner.onClassified:Connect(function(part, cls)
			if cls.isFloor then enroll(part) end
		end))

		-- ── per-floor reflectance update (Schlick-Fresnel from grazing angle) ──
		local function wetness()
			local base = State.get("reflect_wetness")
			local fromWeather = (ctx.bus.wetness or 0) * State.get("weather_wet_boost")
			return Util.clamp(base + fromWeather, 0, 1)
		end

		local function updateFloor(entry, camLook, camPos)
			local part = entry.part
			if not part.Parent then return false end
			-- Ceilings/overpasses also have up-facing tops; never glaze a surface that
			-- sits well ABOVE the eye (that produced "gray planes above me").
			local aboveEye = camPos and (part.Position.Y > camPos.Y + 4)
			local cls = Scanner.classify(part)
			local f0 = (cls and cls.f0) or 0.04
			local up = part.CFrame.UpVector
			-- cosθ between view and surface normal; grazing → small → high Fresnel
			local cosT = math.abs(up:Dot(camLook))
			local fr = (1 - cosT) ^ 5                              -- Schlick term
			local fresnelTerm = Util.lerp(1, fr, State.get("reflect_fresnel"))
			local strength = State.get("reflect_strength")
			local wet = wetness()
			-- ALBEDO-AWARE reflectance: a black asphalt mostly ABSORBS the sky it would
			-- reflect — it must never read as chrome when wet. Scale by surface
			-- brightness: true blacks ≈0.12×, mid greys near full, whites slightly
			-- boosted. This is THE trick that makes wet streets look real instead of
			-- silver. (Lifted from a hand-tuned reference shader.)
			local albedo = Util.clamp(Util.luminance(part.Color) * 1.5 + 0.05, 0.12, 1.15)
			local target = Util.clamp(
				(strength * (f0 + (1 - f0) * fresnelTerm) + wet * 0.25) * albedo, 0, 1)
			Snapshot.set(part, "Reflectance", target * Util.lerp(0.7, 1, Reflections._q or 1))

			-- glass sheen overlay (lazy-created, capped) gets the probe colour
			if State.get("reflect_glass_overlay") and caps.futureLighting and not entry.overlay and not aboveEye then
				makeOverlay(entry)
			end
			if entry.overlay then
				Snapshot.set(entry.overlay, "Reflectance", Util.clamp(target + wet * 0.3, 0, 1))
				Snapshot.set(entry.overlay, "Transparency", Util.lerp(0.75, 0.45, wet))
				local probeColor = active and active.colorFor and active.colorFor(entry)
				if probeColor then
					entry.overlay.Color = entry.overlay.Color:Lerp(probeColor, 0.2)
				end
			end
			return true
		end

		local accum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			if not State.get("reflect_enabled") then return end
			accum += dt
			if accum < 0.08 then return end
			accum = 0
			local cam = ctx.camera()
			if not cam then return end
			local camPos = cam.CFrame.Position
			local camLook = cam.CFrame.LookVector
			local budget = math.max(4, math.floor(UPDATE_BUDGET * (Reflections._q or 1)))
			local n = #order
			local processed, scanned = 0, 0
			while processed < budget and scanned < n do
				local part = order[cursor]
				cursor = (cursor % n) + 1
				scanned += 1
				local entry = part and floors[part]
				if not entry or not part.Parent then
					-- compact lazily: skip dead refs (cleaned by unenroll over time)
				else
					if (part.Position - camPos).Magnitude <= FLOOR_RADIUS then
						updateFloor(entry, camLook, camPos)
						processed += 1
					end
				end
			end
		end))

		maid:give(State.observe("reflect_mode", switchStrategy))
		maid:give(State.observe("reflect_glass_overlay", function(on)
			if not on then
				for _, entry in pairs(floors) do
					if entry.overlay then entry.overlay:Destroy(); entry.overlay = nil end
				end
				overlayCount = 0
			end
		end))
		maid:give(workspace.DescendantRemoving:Connect(function(inst)
			if floors[inst] then unenroll(inst) end
		end))

		switchStrategy()

		-- Optional hero-floor viewport mirror — OFF by default and NEVER auto-enabled.
		-- It re-renders a cloned scene subset and was a periodic stutter source, so it
		-- is opt-in via the reflect_mirror toggle only (desktop only).
		local mirrorHandle = nil
		local function syncMirror()
			local want = State.get("reflect_mirror") and not ctx.platform.isMobile and State.get("reflect_enabled")
			if want and not mirrorHandle then
				maid:spawn(function()
					task.wait(0.5) -- let the Scanner populate floors first
					local ok, m = pcall(function() return require("reflections/ViewportMirror").start(ctx) end)
					if ok and m then mirrorHandle = m; ctx.registerHandle(m) end
				end)
			elseif not want and mirrorHandle then
				pcall(function() if mirrorHandle.stop then mirrorHandle.stop() end end)
				mirrorHandle = nil
			end
		end
		maid:give(State.observe("reflect_mirror", syncMirror))

		ctx.log.debug("Reflections online; floors seeded =", #order)
		return Reflections
	end

	function Reflections.setQuality(q)
		Reflections._q = math.clamp(q, 0, 1)
	end

	function Reflections.stop()
		if Reflections._maid then Reflections._maid:clean() end
	end

	return Reflections
end
