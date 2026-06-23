--!nonstrict
--[[
	presets/Presets.lua  —  pure module (no lifecycle)
	-----------------------------------------------------------------------------
	Named PARTIAL look overlays. Applying a preset sets ONLY the keys it names (via
	State.applyOverlay), so it composes with — rather than wipes — the rest of the
	user's tuning. Every value targets a real Config key. Users can author their own
	by adding to this table or via JSON import (presets/Serializer).
]]

return function(require)
	local State = require("core/State")

	local Presets = {}
	Presets._current = "Cinematic"

	-- ordered list for the UI dropdown
	Presets._order = { "Cinematic", "Realistic", "Vibrant", "Dreamy", "Noir", "Horror", "Potato" }

	Presets._data = {
		Cinematic = {
			tonemap_enabled = true, tonemap_mode = "ACES", tonemap_contrast = 0.18,
			lighting_exposure = 0.15, lighting_brightness = 2.2,
			grade_enabled = true, grade_contrast = 0.09, grade_saturation = 0.12,
			grade_tint = Color3.fromRGB(255, 246, 232),
			bloom_enabled = true, bloom_intensity = 1.2, bloom_size = 24,
			atmos_enabled = true, atmos_density = 0.34,
			overlay_vignette = true, overlay_vignette_intensity = 0.45,
			overlay_grain = true, overlay_grain_intensity = 0.16,
			cam_dof_enabled = true, cam_dof_aperture = 18,
			reflect_enabled = true, reflect_strength = 0.55,
		},
		Realistic = {
			tonemap_enabled = true, tonemap_mode = "Neutral", tonemap_contrast = 0.1,
			lighting_exposure = 0.05, lighting_brightness = 2.0,
			grade_enabled = true, grade_contrast = 0.05, grade_saturation = 0.02,
			grade_tint = Color3.fromRGB(250, 250, 250),
			bloom_enabled = true, bloom_intensity = 0.7,
			atmos_enabled = true, atmos_density = 0.22,
			overlay_vignette = true, overlay_vignette_intensity = 0.25,
			overlay_grain = false,
			eye_adapt_enabled = true,
		},
		Vibrant = {
			tonemap_mode = "Filmic", tonemap_contrast = 0.2,
			grade_enabled = true, grade_contrast = 0.14, grade_saturation = 0.35,
			grade_tint = Color3.fromRGB(255, 250, 245),
			bloom_enabled = true, bloom_intensity = 1.3,
			sky_preset = "Clear Blue", clouds_color = Color3.fromRGB(252, 252, 255),
			atmos_density = 0.18,
			overlay_vignette = true, overlay_vignette_intensity = 0.3,
		},
		Dreamy = {
			tonemap_mode = "Filmic", tonemap_contrast = 0.06,
			grade_enabled = true, grade_contrast = -0.02, grade_saturation = 0.18,
			grade_tint = Color3.fromRGB(255, 240, 230),
			bloom_enabled = true, bloom_intensity = 1.8, bloom_size = 40,
			cam_dof_enabled = true, cam_dof_aperture = 60,
			atmos_enabled = true, atmos_density = 0.4, atmos_haze = 3,
			overlay_vignette = true, overlay_vignette_intensity = 0.5,
			mood_preset = "Golden Hour",
		},
		Noir = {
			tonemap_mode = "ACES", tonemap_contrast = 0.3,
			grade_enabled = true, grade_contrast = 0.28, grade_saturation = -0.85,
			grade_tint = Color3.fromRGB(235, 240, 248),
			bloom_enabled = true, bloom_intensity = 0.5,
			overlay_vignette = true, overlay_vignette_intensity = 0.7,
			overlay_grain = true, overlay_grain_intensity = 0.32,
			overlay_letterbox = true,
			atmos_density = 0.3,
		},
		Horror = {
			tonemap_mode = "ACES", tonemap_contrast = 0.22,
			lighting_exposure = -0.6, lighting_brightness = 1.2,
			lighting_ambient = Color3.fromRGB(10, 12, 16),
			lighting_outdoor_ambient = Color3.fromRGB(24, 30, 42),
			grade_enabled = true, grade_contrast = 0.16, grade_saturation = -0.25,
			grade_tint = Color3.fromRGB(200, 214, 235),
			bloom_enabled = true, bloom_intensity = 0.6,
			atmos_enabled = true, atmos_density = 0.6, atmos_color = Color3.fromRGB(120, 130, 150),
			overlay_vignette = true, overlay_vignette_intensity = 0.75,
			overlay_grain = true, overlay_grain_intensity = 0.3,
			mood_preset = "Night", weather_mode = "Storm",
		},
		Potato = {
			quality = 0.2,
			reflect_enabled = false, reflect_mode = "Off", reflect_glass_overlay = false,
			reflect_multibounce = false,
			enh_godrays = false, enh_dust = false, enh_foliage_wind = false,
			cam_motionblur = false, cam_dof_enabled = false,
			overlay_grain = false, overlay_dither = false, overlay_chromatic = false,
			bloom_intensity = 0.6, atmos_density = 0.15,
			clouds_enabled = false,
		},
	}

	function Presets.names()
		return table.clone(Presets._order)
	end

	function Presets.current()
		return Presets._current
	end

	function Presets.apply(name)
		local overlay = Presets._data[name]
		if not overlay then return {} end
		Presets._current = name
		return State.applyOverlay(overlay)
	end

	return Presets
end
