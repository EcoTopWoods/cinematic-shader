--!nonstrict
--[[
	materials/PBR.lua  —  CONTROLLER (manifest.boot, started 2nd)
	-----------------------------------------------------------------------------
	Material → PBR classifier + global reflectance/roughness bias pass.

	WHY: Roblox parts only expose Material + Reflectance, not a real PBR stack.
	We approximate per-material roughness / metalness / F0 (Fresnel reflectance at
	normal incidence) from a static lookup so Reflections and the Scanner can reason
	about how shiny a surface "should" be, then nudge Reflectance toward that via
	Snapshot (so originals restore on unload).

	PBR.props(materialEnum) is a PURE static lookup — safe to call without start().
	The Scanner calls it during classification, so it must not depend on ctx.

	HONESTY: this is a heuristic material model, not a measured BRDF. We never claim
	metalness/roughness maps exist on stock parts; SurfaceAppearance work is opt-in
	and only touches author-flagged surfaces (see _applySurfaceAppearance).
]]

return function(require)
	local State = require("core/State")
	local Util = require("core/Util")

	local PBR = {}
	PBR.id = "materials/PBR"

	-- ── static material table ────────────────────────────────────────────────
	-- roughness 0(mirror)..1(matte), metalness 0..1, f0 reflectance at normal angle.
	-- Tuned by eye for a filmic look; reflectance is the *baseline* we may bias up.
	local M = Enum.Material
	local TABLE = {
		[M.Plastic]        = { roughness = 0.55, metalness = 0.0, f0 = 0.04 },
		[M.SmoothPlastic]  = { roughness = 0.30, metalness = 0.0, f0 = 0.05 },
		[M.Neon]           = { roughness = 0.20, metalness = 0.0, f0 = 0.02 },
		[M.Glass]          = { roughness = 0.05, metalness = 0.0, f0 = 0.08 },
		[M.ForceField]     = { roughness = 0.10, metalness = 0.0, f0 = 0.05 },
		[M.Metal]          = { roughness = 0.28, metalness = 1.0, f0 = 0.85 },
		[M.DiamondPlate]   = { roughness = 0.40, metalness = 1.0, f0 = 0.80 },
		[M.Foil]           = { roughness = 0.22, metalness = 1.0, f0 = 0.88 },
		[M.CorrodedMetal]  = { roughness = 0.70, metalness = 0.9, f0 = 0.55 },
		[M.Wood]           = { roughness = 0.75, metalness = 0.0, f0 = 0.04 },
		[M.WoodPlanks]     = { roughness = 0.78, metalness = 0.0, f0 = 0.04 },
		[M.Marble]         = { roughness = 0.22, metalness = 0.0, f0 = 0.06 },
		[M.Granite]        = { roughness = 0.55, metalness = 0.0, f0 = 0.05 },
		[M.Slate]          = { roughness = 0.60, metalness = 0.0, f0 = 0.05 },
		[M.Concrete]       = { roughness = 0.85, metalness = 0.0, f0 = 0.03 },
		[M.Pavement]       = { roughness = 0.88, metalness = 0.0, f0 = 0.03 },
		[M.Brick]          = { roughness = 0.90, metalness = 0.0, f0 = 0.03 },
		[M.Cobblestone]    = { roughness = 0.88, metalness = 0.0, f0 = 0.03 },
		[M.Sandstone]      = { roughness = 0.86, metalness = 0.0, f0 = 0.03 },
		[M.Limestone]      = { roughness = 0.80, metalness = 0.0, f0 = 0.04 },
		[M.Rock]           = { roughness = 0.82, metalness = 0.0, f0 = 0.04 },
		[M.Basalt]         = { roughness = 0.80, metalness = 0.0, f0 = 0.04 },
		[M.Sand]           = { roughness = 0.95, metalness = 0.0, f0 = 0.02 },
		[M.Mud]            = { roughness = 0.70, metalness = 0.0, f0 = 0.05 },
		[M.Ground]         = { roughness = 0.92, metalness = 0.0, f0 = 0.02 },
		[M.Grass]          = { roughness = 0.95, metalness = 0.0, f0 = 0.02 },
		[M.LeafyGrass]     = { roughness = 0.96, metalness = 0.0, f0 = 0.02 },
		[M.Fabric]         = { roughness = 0.98, metalness = 0.0, f0 = 0.02 },
		[M.Pebble]         = { roughness = 0.78, metalness = 0.0, f0 = 0.04 },
		[M.Asphalt]        = { roughness = 0.80, metalness = 0.0, f0 = 0.04 },
		[M.Ice]            = { roughness = 0.12, metalness = 0.0, f0 = 0.10 },
		[M.Glacier]        = { roughness = 0.18, metalness = 0.0, f0 = 0.09 },
		[M.Snow]           = { roughness = 0.85, metalness = 0.0, f0 = 0.03 },
		[M.Salt]           = { roughness = 0.80, metalness = 0.0, f0 = 0.03 },
		[M.CrackedLava]    = { roughness = 0.65, metalness = 0.0, f0 = 0.05 },
		[M.Water]          = { roughness = 0.08, metalness = 0.0, f0 = 0.06 },
	}
	local DEFAULT = { roughness = 0.6, metalness = 0.0, f0 = 0.04 }

	-- PURE lookup. Returns a *copy field* table augmented with a baseline reflectance.
	function PBR.props(material)
		local base = TABLE[material] or DEFAULT
		return {
			roughness = base.roughness,
			metalness = base.metalness,
			f0 = base.f0,
			-- baseline engine Reflectance we'd apply if the global pass is on:
			reflectance = base.metalness > 0.5 and base.f0 or (base.f0 * 0.5),
		}
	end

	-- ── global reflectance bias pass ─────────────────────────────────────────
	-- Applies Reflectance to metal/floor/glass parts the Scanner surfaces, biased
	-- by pbr_reflectance_bias / pbr_metal_boost. Foreign writes via Snapshot.
	function PBR.start(ctx)
		local maid = ctx.maid:childMaid()
		PBR._maid = maid
		local Snapshot = ctx.snapshot
		local log = ctx.log
		local q = ctx.getQuality()

		local Scanner = require("detection/Scanner") -- already started before us

		local function targetReflectance(part)
			local props = PBR.props(part.Material)
			local bias = State.get("pbr_reflectance_bias")
			local metalBoost = State.get("pbr_metal_boost")
			local r = props.reflectance + bias
			if props.metalness > 0.5 then
				r = Util.lerp(r, 0.9, metalBoost)
			end
			return Util.clamp(r, 0, 1)
		end

		local function apply(part)
			if not (part and part:IsA("BasePart")) then return end
			if not State.get("pbr_enabled") then return end
			local cls = Scanner.classify(part)
			-- Only touch surfaces where added reflectance reads as "intended":
			if cls.isMetal or cls.isGlass or cls.isFloor then
				Snapshot.set(part, "Reflectance", targetReflectance(part))
			end
		end

		-- enroll already-classified + future parts
		local function applyAll()
			if not State.get("pbr_enabled") then return end
			for _, p in ipairs(Scanner.getByKind("metal")) do apply(p) end
			for _, p in ipairs(Scanner.getByKind("glass")) do apply(p) end
			for _, p in ipairs(Scanner.getByKind("floor")) do apply(p) end
		end

		maid:give(Scanner.onClassified:Connect(function(part)
			apply(part)
		end))
		maid:give(State.observeMany(
			{ "pbr_enabled", "pbr_reflectance_bias", "pbr_metal_boost", "pbr_roughness_bias" },
			function() applyAll() end
		))

		-- first pass shortly after boot (Scanner needs a few frames to fill)
		maid:spawn(function()
			task.wait(0.5)
			applyAll()
		end)

		-- optional SurfaceAppearance scaffold (opt-in, author-flagged only)
		maid:give(State.observe("pbr_surface_appearance", function(on)
			if on then PBR._applySurfaceAppearance(ctx, Scanner) end
		end))

		log.debug("PBR pass online (q=" .. string.format("%.2f", q) .. ")")
		return PBR
	end

	-- Only acts on parts the author flagged by giving them string attributes
	-- "ColorMap"/"NormalMap"/"MetalnessMap"/"RoughnessMap" (rbxassetid). We ship no
	-- texture ids, so on stock places this is a safe no-op. Correct property names
	-- are ColorMap/NormalMap/MetalnessMap/RoughnessMap — NEVER AlbedoMap.
	function PBR._applySurfaceAppearance(ctx, Scanner)
		local Snapshot = ctx.snapshot
		for _, part in ipairs(Scanner.getByKind("metal")) do
			if part:IsA("MeshPart") or part:IsA("Part") then
				local color = part:GetAttribute("ColorMap")
				if type(color) == "string" and color ~= "" then
					if not part:FindFirstChildOfClass("SurfaceAppearance") then
						local sa = Snapshot.create("SurfaceAppearance", {
							ColorMap = color,
							NormalMap = part:GetAttribute("NormalMap") or "",
							MetalnessMap = part:GetAttribute("MetalnessMap") or "",
							RoughnessMap = part:GetAttribute("RoughnessMap") or "",
						}, part)
						ctx.log.debug("SurfaceAppearance applied to", part:GetFullName())
					end
				end
			end
		end
	end

	function PBR.setQuality(_q)
		-- Material bias is cheap; nothing to scale per quality.
	end

	function PBR.stop()
		if PBR._maid then PBR._maid:clean() end
	end

	return PBR
end
