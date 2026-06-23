--!nonstrict
--[[
	lighting/Sky.lua
	-----------------------------------------------------------------------------
	Owns a Sky (under Lighting) and a Clouds (under workspace.Terrain).

	HARD TRUTH: clouds are a `Clouds` instance parented to workspace.Terrain — there
	is NO "Atmosphere clouds" object. Sky properties used are all REAL: SkyboxUp/Dn/
	Lf/Rt/Ft/Bk, SunAngularSize, MoonAngularSize, StarCount, CelestialBodiesShown.

	Skybox FACE ids are intentionally left blank in the presets below — we ship no
	texture assets, and pointing faces at an invalid id would look worse than the
	game's own sky. Presets therefore tune sun/moon/stars/celestial bodies and you
	can paste your own face asset ids into SKY_PRESETS to get full skybox swaps.
]]

return function(require)
	local State = require("core/State")

	local Sky = {}
	Sky.id = "lighting/Sky"

	-- Paste rbxassetid strings into the face fields to enable full skybox swaps.
	-- Leaving a face as "" means "leave the existing sky face untouched".
	local SKY_PRESETS = {
		["Default"]     = { stars = 3000, celestial = true,  sun = 21, moon = 11 },
		["Clear Blue"]  = { stars = 1500, celestial = true,  sun = 21, moon = 11 },
		["Golden Dusk"] = { stars = 2200, celestial = true,  sun = 28, moon = 13 },
		["Overcast"]    = { stars = 800,  celestial = false, sun = 16, moon = 9 },
		["Night Stars"] = { stars = 7000, celestial = true,  sun = 12, moon = 22 },
		-- faces = { up=, dn=, lf=, rt=, ft=, bk= }   ← add your own ids here
	}

	function Sky.start(ctx)
		local maid = ctx.maid:childMaid()
		Sky._maid = maid
		local L = ctx.services.Lighting
		local Snapshot = ctx.snapshot

		-- own a Sky (reuse existing if present so we don't double up)
		local sky = L:FindFirstChildOfClass("Sky")
		if not sky then
			sky = Snapshot.create("Sky", { Name = "CinematicSky" }, L)
		end
		Sky._sky = sky

		-- own a Clouds under Terrain (guard Terrain existence on void places)
		local terrain = ctx.services.Workspace:FindFirstChildOfClass("Terrain")
		local clouds
		if terrain then
			clouds = terrain:FindFirstChildOfClass("Clouds")
			if not clouds then
				clouds = Snapshot.create("Clouds", { Name = "CinematicClouds" }, terrain)
			end
			Sky._clouds = clouds
		end

		local function applySky()
			if not State.get("sky_enabled") then return end
			local preset = SKY_PRESETS[State.get("sky_preset")] or SKY_PRESETS.Default
			-- sun/moon/stars come from explicit config keys (preset seeds defaults)
			Snapshot.set(sky, "SunAngularSize", State.get("sky_sun_size"))
			Snapshot.set(sky, "MoonAngularSize", State.get("sky_moon_size"))
			Snapshot.set(sky, "StarCount", State.get("sky_star_count"))
			pcall(function() Snapshot.set(sky, "CelestialBodiesShown", preset.celestial) end)
			-- optional face swaps when the preset carries ids
			if preset.faces then
				local f = preset.faces
				if f.up and f.up ~= "" then Snapshot.set(sky, "SkyboxUp", f.up) end
				if f.dn and f.dn ~= "" then Snapshot.set(sky, "SkyboxDn", f.dn) end
				if f.lf and f.lf ~= "" then Snapshot.set(sky, "SkyboxLf", f.lf) end
				if f.rt and f.rt ~= "" then Snapshot.set(sky, "SkyboxRt", f.rt) end
				if f.ft and f.ft ~= "" then Snapshot.set(sky, "SkyboxFt", f.ft) end
				if f.bk and f.bk ~= "" then Snapshot.set(sky, "SkyboxBk", f.bk) end
			end
		end

		local function applyClouds()
			if not clouds then return end
			local on = State.get("clouds_enabled")
			Snapshot.set(clouds, "Enabled", on)
			if on then
				Snapshot.set(clouds, "Cover", State.get("clouds_cover"))
				Snapshot.set(clouds, "Density", State.get("clouds_density"))
				Snapshot.set(clouds, "Color", State.get("clouds_color"))
			end
		end

		maid:give(State.observeMany(
			{ "sky_enabled", "sky_preset", "sky_sun_size", "sky_moon_size", "sky_star_count" },
			applySky))
		maid:give(State.observeMany(
			{ "clouds_enabled", "clouds_cover", "clouds_density", "clouds_color" },
			applyClouds))

		applySky()
		applyClouds()
		ctx.log.debug("Sky online (clouds=" .. tostring(clouds ~= nil) .. ")")
		return Sky
	end

	function Sky.stop()
		if Sky._maid then Sky._maid:clean() end
	end

	return Sky
end
