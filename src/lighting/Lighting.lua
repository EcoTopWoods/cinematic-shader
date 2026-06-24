--!nonstrict
--[[
	lighting/Lighting.lua  —  CONTROLLER (manifest.boot)
	-----------------------------------------------------------------------------
	Sole writer to Lighting's core properties. Applies every lighting_* config key
	and owns the Future-lighting capability gate. Also starts Atmosphere + Sky.

	WHY each lever (all REAL Lighting properties — no inventions):
	  Technology=Future ......... per-pixel lighting + soft shadows (gated by caps)
	  LightingStyle=Realistic ... newer realistic pipeline (gated by caps)
	  Brightness/ClockTime/GeographicLatitude ... key light + sun position
	  ExposureCompensation ...... overall EV (driven by EyeAdaptation via bus.exposure)
	  EnvironmentDiffuse/SpecularScale ... fakes GI + environment reflections
	  ShadowSoftness ............ Future-only penumbra
	  Ambient/OutdoorAmbient .... shadow + skylight fill
	  ColorShift_Top/Bottom ..... warm key / cool bounce tint

	Every foreign write goes through Snapshot so unload restores the game exactly.
]]

return function(require)
	local State = require("core/State")

	local Lighting = {}
	Lighting.id = "lighting/Lighting"

	function Lighting.start(ctx)
		local maid = ctx.maid:childMaid()
		Lighting._maid = maid
		local L = ctx.services.Lighting
		local Snapshot = ctx.snapshot
		local caps = ctx.platform.caps
		local log = ctx.log

		-- ── capability-gated technology/style ────────────────────────────────
		local function applyTechnology()
			if not State.get("lighting_enabled") then return end
			if State.get("lighting_future") and caps.futureLighting then
				Snapshot.set(L, "Technology", Enum.Technology.Future)
			end
			if caps.realisticLightingStyle then
				pcall(function() Snapshot.set(L, "LightingStyle", Enum.LightingStyle.Realistic) end)
			end
			if caps.prioritizeLightingQuality then
				pcall(function() Snapshot.set(L, "PrioritizeLightingQuality", true) end)
			end
		end

		-- ── direct property appliers, each keyed to its config ───────────────
		local appliers = {
			lighting_brightness    = function(v) Snapshot.set(L, "Brightness", v) end,
			lighting_clock_time    = function(v) Snapshot.set(L, "ClockTime", v) end,
			lighting_geo_latitude  = function(v) Snapshot.set(L, "GeographicLatitude", v) end,
			lighting_global_shadows= function(v) Snapshot.set(L, "GlobalShadows", v) end,
			lighting_ambient       = function(v) Snapshot.set(L, "Ambient", v) end,
			lighting_outdoor_ambient = function(v) Snapshot.set(L, "OutdoorAmbient", v) end,
			lighting_env_diffuse   = function(v) Snapshot.set(L, "EnvironmentDiffuseScale", v) end,
			lighting_env_specular  = function(v) Snapshot.set(L, "EnvironmentSpecularScale", v) end,
			lighting_color_shift_top    = function(v) Snapshot.set(L, "ColorShift_Top", v) end,
			lighting_color_shift_bottom = function(v) Snapshot.set(L, "ColorShift_Bottom", v) end,
			lighting_shadow_softness = function(v)
				if caps.shadowSoftness then Snapshot.set(L, "ShadowSoftness", v) end
			end,
		}

		local function applyAll()
			if not State.get("lighting_enabled") then return end
			applyTechnology()
			for key, fn in pairs(appliers) do
				fn(State.get(key))
			end
			-- exposure: if eye-adaptation is off, apply the static config value now.
			if not State.get("eye_adapt_enabled") then
				Snapshot.set(L, "ExposureCompensation", State.get("lighting_exposure"))
			end
		end

		-- live updates per key
		for key, fn in pairs(appliers) do
			maid:give(State.observe(key, function(v)
				if State.get("lighting_enabled") then fn(v) end
			end))
		end
		maid:give(State.observe("lighting_future", function() applyTechnology() end))
		maid:give(State.observe("lighting_exposure", function(v)
			if not State.get("eye_adapt_enabled") then
				Snapshot.set(L, "ExposureCompensation", v)
			end
		end))
		maid:give(State.observe("lighting_enabled", function(on)
			if on then applyAll() end
			-- when toggled off we leave Snapshot to restore on teardown; live revert
			-- of a single subsystem is intentionally a no-op to avoid fighting others.
		end))

		-- ── exposure bridge ──────────────────────────────────────────────────
		-- EyeAdaptation writes bus.exposure each frame; we push it to the engine
		-- here (Lighting is the sole writer to ExposureCompensation). Throttled.
		local accum = 0
		maid:give(ctx.services.RunService.Heartbeat:Connect(function(dt)
			accum += dt
			if accum < 0.05 then return end
			accum = 0
			if State.get("lighting_enabled") and State.get("eye_adapt_enabled") then
				local e = ctx.bus.exposure
				if type(e) == "number" then
					Snapshot.set(L, "ExposureCompensation", e)
				end
			end
		end))

		applyAll()

		-- start sub-systems
		for _, name in ipairs({ "lighting/Atmosphere", "lighting/Sky" }) do
			local ok, handle = pcall(function()
				local m = require(name)
				return m.start(ctx) or m
			end)
			if ok and handle then ctx.registerHandle(handle) else log.error("lighting sub failed:", name, handle) end
		end

		-- One-time hint. Shadow + reflection RESOLUTION is the client's Graphics
		-- Quality slider — we physically cannot force it from a script. If it's on
		-- Automatic or low, the crispest shadows aren't possible no matter the tuning,
		-- so we nudge the user to set Manual / Quality 10.
		maid:spawn(function()
			task.wait(3)
			local ok, ugs = pcall(function() return UserSettings():GetService("UserGameSettings") end)
			if not ok or not ugs then return end
			local saved = ugs.SavedQualityLevel
			local lvl = (typeof(saved) == "EnumItem" and saved.Value) or tonumber(saved) or 0
			if lvl == 0 or (lvl > 0 and lvl < 8) then
				pcall(function()
					ctx.services.StarterGui:SetCore("SendNotification", {
						Title = "Cinematic Suite",
						Text = "For 1080p-crisp shadows & reflections: Roblox menu → Settings → Graphics Mode = Manual, Quality 10.",
						Duration = 9,
					})
				end)
			end
		end)

		log.debug("Lighting online (future=" .. tostring(State.get("lighting_future") and caps.futureLighting) .. ")")
		return Lighting
	end

	function Lighting.stop()
		if Lighting._maid then Lighting._maid:clean() end
	end

	return Lighting
end
