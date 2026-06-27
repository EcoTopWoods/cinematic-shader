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
	Presets._order = { "Realistic+", "Lite", "Ultra", "Night City", "Cinematic", "Realistic", "Vibrant", "Dreamy", "Noir", "Horror", "Potato" }

	Presets._data = {
		-- LITE — the gentlest possible touch, for when the full effect feels like "too
		-- much". FIXED exposure (no auto-exposure shifting at all), NO god rays, NO
		-- streetlight beams, NO motion blur / DoF / vignette / grain / dust. Just Future
		-- lighting, tight shadows, a whisper of contrast, and cheap subtle reflections.
		-- Enhances without ever announcing itself.
		Lite = {
			quality = 0.85,
			tonemap_enabled = true, tonemap_mode = "Neutral", tonemap_contrast = 0.06,
			lighting_future = true, lighting_brightness = 1.5, lighting_exposure = -0.05,
			lighting_env_diffuse = 0.95, lighting_env_specular = 1.1, lighting_shadow_softness = 0.2,
			lighting_global_shadows = true,
			eye_adapt_enabled = false,  -- exposure never shifts; rock-steady
			grade_enabled = true, grade_contrast = 0.06, grade_saturation = 0.03,
			grade_tint = Color3.fromRGB(255, 253, 250),
			bloom_enabled = true, bloom_intensity = 0.2, bloom_size = 20, bloom_threshold = 1.6,
			atmos_enabled = true, atmos_density = 0.1, atmos_haze = 0.2, atmos_glare = 0.02,
			reflect_enabled = true, reflect_mode = "Color Blend (cheap)", reflect_strength = 0.35,
			reflect_glass_overlay = false, reflect_mirror = false,
			cam_dof_enabled = false, cam_motionblur = false, cam_shake = false,
			enh_enabled = true, enh_light_shadows = true,
			enh_godrays = false, enh_light_beams = false, enh_dust = false, enh_foliage_wind = false,
			overlay_vignette = false, overlay_grain = false, overlay_chromatic = false,
		},
		-- REALISTIC+  — the refined "best looking" grade. Deep contrast, AO-like shadow
		-- depth (low ambient fill), tight crisp shadows, strong albedo-aware reflections,
		-- and a SLOW, rock-stable auto-exposure so the lighting doesn't lurch when you
		-- move the camera. Grounded colour, gentle bloom on true lights only. Foliage
		-- wind stays OFF (never deforms the world).
		["Realistic+"] = {
			quality = 1.0,
			tonemap_enabled = true, tonemap_mode = "ACES", tonemap_contrast = 0.22, tonemap_white_point = 1.05,
			lighting_future = true, lighting_brightness = 1.45, lighting_exposure = -0.18,
			lighting_env_diffuse = 0.62, lighting_env_specular = 1.6, lighting_shadow_softness = 0.12,
			lighting_global_shadows = true,
			lighting_ambient = Color3.fromRGB(22, 22, 26),
			lighting_outdoor_ambient = Color3.fromRGB(98, 100, 106),
			eye_adapt_enabled = true, eye_adapt_target = 0.5, eye_adapt_speed = 2.6,  -- slow + stable
			grade_enabled = true, grade_contrast = 0.16, grade_saturation = 0.08,
			grade_tint = Color3.fromRGB(255, 250, 242),
			bloom_enabled = true, bloom_intensity = 0.3, bloom_size = 24, bloom_threshold = 1.55,
			bloom_exposure_couple = 0.1,
			atmos_enabled = true, atmos_density = 0.14, atmos_haze = 0.3, atmos_glare = 0.03,
			reflect_enabled = true, reflect_mode = "Raycast Probe (SSR approx.)",
			reflect_strength = 0.7, reflect_fresnel = 0.85, reflect_wetness = 0.45, reflect_rays_per_frame = 56,
			cam_dof_enabled = true, cam_dof_aperture = 14,
			enh_enabled = true, enh_godrays = true, enh_godray_strength = 0.25,
			enh_light_shadows = true, enh_light_beams = true, enh_dust = true, enh_foliage_wind = false,
			overlay_vignette = true, overlay_vignette_intensity = 0.34,
			overlay_grain = true, overlay_grain_intensity = 0.05, overlay_chromatic = false,
		},
		-- The "best quality" / extreme preset: rich but DELIBERATELY not blown out —
		-- neutral-ish exposure, restrained bloom, real SunRaysEffect god-rays, the full
		-- raycast reflection probe, soft shadows, shallow DoF. Heavy on a strong PC.
		Ultra = {
			quality = 1.0,
			tonemap_enabled = true, tonemap_mode = "ACES", tonemap_contrast = 0.15,
			lighting_future = true, lighting_brightness = 2.0, lighting_exposure = -0.05,
			lighting_env_diffuse = 1.1, lighting_env_specular = 1.35, lighting_shadow_softness = 0.5,
			eye_adapt_enabled = true, eye_adapt_target = 0.5, eye_adapt_speed = 1.1,
			grade_enabled = true, grade_contrast = 0.1, grade_saturation = 0.15,
			grade_tint = Color3.fromRGB(255, 247, 236),
			bloom_enabled = true, bloom_intensity = 0.55, bloom_size = 30, bloom_threshold = 1.05,
			atmos_enabled = true, atmos_density = 0.2, atmos_haze = 0.6, atmos_glare = 0.05,
			clouds_enabled = true, clouds_density = 0.65,
			reflect_enabled = true, reflect_mode = "Raycast Probe (SSR approx.)",
			reflect_strength = 0.6, reflect_fresnel = 0.85, reflect_wetness = 0.4,
			reflect_rays_per_frame = 96, reflect_accum_frames = 10, reflect_glass_overlay = false,
			reflect_mirror = true,  -- the hero-floor showpiece mirror (Ultra = strong PC)
			cam_dof_enabled = true, cam_dof_aperture = 22,
			enh_enabled = true, enh_godrays = true, enh_godray_strength = 0.3, enh_dust = true,
			enh_light_shadows = true, enh_light_beams = true,
			overlay_vignette = true, overlay_vignette_intensity = 0.3,
			overlay_grain = true, overlay_grain_intensity = 0.08,
			overlay_chromatic = true, overlay_chromatic_intensity = 0.14,
		},
		-- The default look: SHARP + REALISTIC. Deeper contrast, tight crisp shadows,
		-- stronger (albedo-aware) reflections, minimal haze. Grounded, not oversaturated.
		Cinematic = {
			tonemap_enabled = true, tonemap_mode = "ACES", tonemap_contrast = 0.2,
			lighting_exposure = -0.2, lighting_brightness = 1.4,
			lighting_env_diffuse = 0.7, lighting_env_specular = 1.5, lighting_shadow_softness = 0.15,
			eye_adapt_enabled = true, eye_adapt_target = 0.5,
			grade_enabled = true, grade_contrast = 0.14, grade_saturation = 0.1,
			grade_tint = Color3.fromRGB(255, 248, 238),
			bloom_enabled = true, bloom_intensity = 0.3, bloom_size = 26, bloom_threshold = 1.5,
			atmos_enabled = true, atmos_density = 0.15, atmos_haze = 0.35, atmos_glare = 0.04,
			overlay_vignette = true, overlay_vignette_intensity = 0.3,
			overlay_grain = true, overlay_grain_intensity = 0.06,
			cam_dof_enabled = true, cam_dof_aperture = 16,
			reflect_enabled = true, reflect_strength = 0.65, reflect_fresnel = 0.8,
			enh_godrays = true, enh_godray_strength = 0.28,
		},
		-- GTA-style developed night city: deep contrast, controlled exposure, warm
		-- sodium key vs cool city bounce (a TASTEFUL teal-orange split — not the flat
		-- blue wash), neon/streetlights that bloom while the rest stays grounded, and
		-- wet reflective streets. Heavy; best on a strong PC.
		["Night City"] = {
			quality = 1.0,
			tonemap_enabled = true, tonemap_mode = "ACES", tonemap_contrast = 0.2,
			lighting_future = true, lighting_brightness = 1.3, lighting_exposure = -0.25,
			lighting_clock_time = 20.4, lighting_geo_latitude = 30,
			lighting_ambient = Color3.fromRGB(20, 19, 24),
			lighting_outdoor_ambient = Color3.fromRGB(46, 44, 56),
			lighting_color_shift_top = Color3.fromRGB(255, 226, 190),     -- warm sodium key
			lighting_color_shift_bottom = Color3.fromRGB(72, 88, 120),    -- cool city bounce
			lighting_env_diffuse = 0.7, lighting_env_specular = 1.5, lighting_shadow_softness = 0.6,
			eye_adapt_enabled = true, eye_adapt_target = 0.4, eye_adapt_speed = 1.4,
			grade_enabled = true, grade_contrast = 0.16, grade_saturation = 0.16,
			grade_tint = Color3.fromRGB(255, 240, 224),
			bloom_enabled = true, bloom_intensity = 0.85, bloom_size = 34,
			bloom_threshold = 1.25, bloom_exposure_couple = 0.15,           -- only lights bloom
			atmos_enabled = true, atmos_density = 0.3, atmos_haze = 1.2, atmos_glare = 0.1,
			atmos_color = Color3.fromRGB(60, 66, 86), atmos_decay = Color3.fromRGB(122, 96, 78),
			clouds_enabled = true, clouds_density = 0.7, clouds_color = Color3.fromRGB(120, 120, 140),
			sky_preset = "Night Stars", sky_star_count = 4500,
			reflect_enabled = true, reflect_mode = "Raycast Probe (SSR approx.)",
			reflect_strength = 0.7, reflect_wetness = 0.7, reflect_fresnel = 0.9,
			reflect_rays_per_frame = 80, reflect_glass_overlay = false,
			cam_dof_enabled = true, cam_dof_aperture = 26,
			enh_enabled = true, enh_godrays = true, enh_godray_strength = 0.25,
			enh_lights_repair = true, enh_light_shadows = true, enh_light_beams = true, enh_dust = true,
			overlay_vignette = true, overlay_vignette_intensity = 0.4,
			overlay_grain = true, overlay_grain_intensity = 0.07, overlay_chromatic = false,
			weather_mode = "Clear",
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
