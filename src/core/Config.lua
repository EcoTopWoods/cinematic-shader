--!nonstrict
--[[
	core/Config.lua
	=============================================================================
	THE SINGLE SOURCE OF TRUTH.

	Every tunable in the entire suite is declared here exactly once, with typed
	metadata. Modules NEVER hardcode magic numbers — they read live values from
	core/State (which is seeded from these defaults). The UI is GENERATED from
	this table, so adding a setting here automatically:
	    * gives it a validated default + clamp range,
	    * makes it live-editable (State.set fires a change signal),
	    * renders the matching Rayfield control in the right tab/group,
	    * round-trips through JSON export/import.

	Metadata schema per key:
	    default  : the seed value (also defines the runtime type)
	    type     : "number" | "boolean" | "color" | "option" | "keybind" | "string"
	    min,max  : numeric bounds (number type) — values are clamped on set
	    step     : numeric quantisation / UI slider increment
	    options  : array of strings (option type)
	    label    : human label for the UI
	    desc     : tooltip / docs string
	    tab      : UI tab name (must exist in Config.tabs)
	    group    : group heading inside the tab
	    requires : capability key in Platform.caps that must be true, else the
	               control is shown disabled / skipped (e.g. "futureLighting")
	    save     : if true, Rayfield ConfigurationSaving persists this control

	`Config.layout` defines UI ORDER (Lua dicts are unordered). Schema walks the
	layout; any key present in meta but absent from layout still validates but is
	hidden (used for internal/derived values).

	NOTE ON HONESTY: keys named *reflection*/*ssr* drive an APPROXIMATION of
	screen-space reflections via roving raycasts — never true RT. Labels/desc say
	so. Keys named *vignette/grain/chromatic/letterbox/dither/motionblur* drive
	GUI / EditableImage OVERLAYS — the engine exposes no such post effects.
]]

return function(_require)
	local Config = {}

	Config.version = "1.0.5"
	Config.schemaVersion = 1

	Config.tabs = {
		"General", "Lighting", "Reflections", "Atmosphere & Weather",
		"Camera & Cinematic", "Materials", "Performance", "Presets", "About",
	}

	-- KeyCode names are stored as strings and resolved to Enum.KeyCode at use.
	local KEYCODES = {
		"RightShift", "LeftShift", "RightControl", "LeftControl", "F1", "F2",
		"F3", "F4", "Backquote", "P", "V", "B", "K", "Insert", "End", "Home",
	}

	Config.meta = {
		-- ════════════════════════ GENERAL ══════════════════════════════════
		master_enabled = {
			default = true, type = "boolean", label = "Master Enable",
			desc = "Master on/off for the entire suite. Off restores the game look without unloading.",
			tab = "General", group = "Master", save = true,
		},
		quality = {
			default = 1.0, type = "number", min = 0, max = 1, step = 0.05,
			label = "Global Quality", desc = "0 = cheapest, 1 = maximum fidelity. Scales every effect's internal budget.",
			tab = "General", group = "Master", save = true,
		},
		ui_keybind = {
			default = "RightShift", type = "keybind", options = KEYCODES,
			label = "Toggle UI Key", desc = "Key that shows/hides the control panel.",
			tab = "General", group = "Master", save = true,
		},
		intro_notify = {
			default = true, type = "boolean", label = "Startup Notifications",
			desc = "Show a toast when the suite boots / changes preset.",
			tab = "General", group = "Master", save = true,
		},
		log_level = {
			default = "info", type = "option", options = { "silent", "warn", "info", "debug", "trace" },
			label = "Log Verbosity", desc = "Developer console verbosity.",
			tab = "General", group = "Master", save = true,
		},

		-- ════════════════════════ LIGHTING CORE ════════════════════════════
		lighting_enabled = {
			default = true, type = "boolean", label = "Lighting Enhancements",
			desc = "Master toggle for the lighting subsystem.",
			tab = "Lighting", group = "Core", save = true,
		},
		lighting_future = {
			default = true, type = "boolean", label = "Future Lighting",
			desc = "Enable Enum.Technology.Future (per-pixel lighting, soft shadows). Falls back gracefully if unsupported.",
			tab = "Lighting", group = "Core", requires = "futureLighting", save = true,
		},
		lighting_brightness = {
			default = 1.4, type = "number", min = 0, max = 6, step = 0.05,
			label = "Sun Brightness", desc = "Lighting.Brightness — primary light intensity.",
			tab = "Lighting", group = "Core", save = true,
		},
		lighting_exposure = {
			default = -0.2, type = "number", min = -3, max = 3, step = 0.05,
			label = "Exposure Comp.", desc = "Lighting.ExposureCompensation — overall EV. (NOT 'Exposure', that property does not exist.)",
			tab = "Lighting", group = "Core", save = true,
		},
		lighting_clock_time = {
			default = 15.5, type = "number", min = 0, max = 24, step = 0.1,
			label = "Time of Day", desc = "Lighting.ClockTime (hours). Golden hour ≈ 6.2 / 17.6.",
			tab = "Lighting", group = "Core", save = true,
		},
		lighting_geo_latitude = {
			default = 41.7, type = "number", min = -90, max = 90, step = 0.5,
			label = "Geographic Latitude", desc = "Lighting.GeographicLatitude — sun arc / shadow angle.",
			tab = "Lighting", group = "Core", save = true,
		},
		lighting_global_shadows = {
			default = true, type = "boolean", label = "Global Shadows",
			desc = "Lighting.GlobalShadows.", tab = "Lighting", group = "Core", save = true,
		},
		lighting_shadow_softness = {
			default = 0.3, type = "number", min = 0, max = 1, step = 0.05,
			label = "Shadow Softness", desc = "Lighting.ShadowSoftness (Future only). Soft penumbra for cinematic key light.",
			tab = "Lighting", group = "Core", requires = "shadowSoftness", save = true,
		},
		lighting_ambient = {
			default = Color3.fromRGB(26, 24, 24), type = "color",
			label = "Ambient", desc = "Lighting.Ambient — shadow fill colour.",
			tab = "Lighting", group = "Core", save = true,
		},
		lighting_outdoor_ambient = {
			default = Color3.fromRGB(108, 104, 104), type = "color",
			label = "Outdoor Ambient", desc = "Lighting.OutdoorAmbient — skylight fill.",
			tab = "Lighting", group = "Core", save = true,
		},
		lighting_env_diffuse = {
			default = 0.8, type = "number", min = 0, max = 2, step = 0.05,
			label = "Env. Diffuse (GI feel)", desc = "Lighting.EnvironmentDiffuseScale — fakes bounced diffuse GI.",
			tab = "Lighting", group = "Core", save = true,
		},
		lighting_env_specular = {
			default = 1.3, type = "number", min = 0, max = 2, step = 0.05,
			label = "Env. Specular", desc = "Lighting.EnvironmentSpecularScale — environment reflections strength (Future).",
			tab = "Lighting", group = "Core", save = true,
		},
		lighting_color_shift_top = {
			default = Color3.fromRGB(255, 240, 214), type = "color",
			label = "Color Shift Top", desc = "Lighting.ColorShift_Top — warm key tint.",
			tab = "Lighting", group = "Core", save = true,
		},
		lighting_color_shift_bottom = {
			default = Color3.fromRGB(150, 146, 150), type = "color",
			label = "Color Shift Bottom", desc = "Lighting.ColorShift_Bottom — cool bounce tint.",
			tab = "Lighting", group = "Core", save = true,
		},

		-- ════════════════════════ TONEMAP (ACES approx) ════════════════════
		tonemap_enabled = {
			default = true, type = "boolean", label = "Tonemap",
			desc = "Filmic tonemap approximation. There is no ACES node in Roblox — this is a dedicated ColorCorrectionEffect + exposure tuned to mimic the ACES/filmic response, applied BEFORE the creative grade.",
			tab = "Lighting", group = "Tonemap (filmic, approx.)", save = true,
		},
		tonemap_mode = {
			default = "ACES", type = "option", options = { "ACES", "Filmic", "Reinhard", "Neutral" },
			label = "Response Curve", desc = "Which filmic response the CCE is tuned toward (approximation, not a true LUT).",
			tab = "Lighting", group = "Tonemap (filmic, approx.)", save = true,
		},
		tonemap_contrast = {
			default = 0.14, type = "number", min = -0.5, max = 1, step = 0.01,
			label = "Filmic Contrast", desc = "Toe/shoulder contrast of the tonemap CCE.",
			tab = "Lighting", group = "Tonemap (filmic, approx.)", save = true,
		},
		tonemap_saturation = {
			default = -0.04, type = "number", min = -1, max = 1, step = 0.01,
			label = "Tonemap Saturation", desc = "Slight desaturation toward filmic look (creative saturation lives in the grade).",
			tab = "Lighting", group = "Tonemap (filmic, approx.)", save = true,
		},
		tonemap_white_point = {
			default = 1.0, type = "number", min = 0.5, max = 2, step = 0.05,
			label = "White Point", desc = "Highlight roll-off pivot used to bias brightness in the tonemap stage.",
			tab = "Lighting", group = "Tonemap (filmic, approx.)", save = true,
		},

		-- ════════════════════════ EYE ADAPTATION ═══════════════════════════
		eye_adapt_enabled = {
			default = true, type = "boolean", label = "Eye Adaptation",
			desc = "Auto-exposure: samples scene luminance and eases ExposureCompensation toward a target (slow tau).",
			tab = "Lighting", group = "Eye Adaptation", save = true,
		},
		eye_adapt_target = {
			default = 0.45, type = "number", min = 0.05, max = 0.9, step = 0.01,
			label = "Target Luminance", desc = "Mid-grey target the auto-exposure drives toward.",
			tab = "Lighting", group = "Eye Adaptation", save = true,
		},
		eye_adapt_speed = {
			default = 1.2, type = "number", min = 0.1, max = 6, step = 0.1,
			label = "Adaptation Time (tau)", desc = "Seconds of exponential lag. Larger = slower, more cinematic.",
			tab = "Lighting", group = "Eye Adaptation", save = true,
		},
		eye_adapt_min = {
			default = -1.0, type = "number", min = -3, max = 0, step = 0.05,
			label = "Min Exposure", desc = "Lower clamp on auto exposure (bright scenes).",
			tab = "Lighting", group = "Eye Adaptation", save = true,
		},
		eye_adapt_max = {
			default = 0.5, type = "number", min = 0, max = 3, step = 0.05,
			label = "Max Exposure", desc = "Upper clamp on auto exposure (dark scenes).",
			tab = "Lighting", group = "Eye Adaptation", save = true,
		},

		-- ════════════════════════ BLOOM ════════════════════════════════════
		bloom_enabled = {
			default = true, type = "boolean", label = "Bloom",
			desc = "HDR-style bloom. Its Threshold is COUPLED to the live auto-exposure value so blooming tracks perceived brightness.",
			tab = "Lighting", group = "Bloom", save = true,
		},
		bloom_intensity = {
			default = 0.5, type = "number", min = 0, max = 4, step = 0.05,
			label = "Bloom Intensity", desc = "BloomEffect.Intensity.",
			tab = "Lighting", group = "Bloom", save = true,
		},
		bloom_size = {
			default = 24, type = "number", min = 0, max = 56, step = 1,
			label = "Bloom Size", desc = "BloomEffect.Size (px).",
			tab = "Lighting", group = "Bloom", save = true,
		},
		bloom_threshold = {
			default = 1.2, type = "number", min = 0, max = 5, step = 0.05,
			label = "Bloom Threshold", desc = "Base threshold; eye-adaptation offsets this live.",
			tab = "Lighting", group = "Bloom", save = true,
		},
		bloom_exposure_couple = {
			default = 0.2, type = "number", min = 0, max = 1.5, step = 0.05,
			label = "Exposure Coupling", desc = "How strongly auto-exposure modulates the bloom threshold.",
			tab = "Lighting", group = "Bloom", save = true,
		},

		-- ════════════════════════ COLOR GRADE (creative) ═══════════════════
		grade_enabled = {
			default = true, type = "boolean", label = "Color Grade",
			desc = "Creative grade — a SECOND ColorCorrectionEffect after the tonemap stage. This is where the 'look' lives.",
			tab = "Lighting", group = "Creative Grade", save = true,
		},
		grade_brightness = {
			default = 0.0, type = "number", min = -0.5, max = 0.5, step = 0.01,
			label = "Brightness", desc = "Grade CCE.Brightness.",
			tab = "Lighting", group = "Creative Grade", save = true,
		},
		grade_contrast = {
			default = 0.08, type = "number", min = -0.5, max = 0.8, step = 0.01,
			label = "Contrast", desc = "Grade CCE.Contrast.",
			tab = "Lighting", group = "Creative Grade", save = true,
		},
		grade_saturation = {
			default = 0.12, type = "number", min = -1, max = 1, step = 0.01,
			label = "Saturation", desc = "Grade CCE.Saturation. Positive = punchier colour.",
			tab = "Lighting", group = "Creative Grade", save = true,
		},
		grade_tint = {
			default = Color3.fromRGB(255, 246, 232), type = "color",
			label = "Tint", desc = "Grade CCE.TintColor — overall colour cast (warm = cinematic).",
			tab = "Lighting", group = "Creative Grade", save = true,
		},

		-- ════════════════════════ REFLECTIONS ══════════════════════════════
		reflect_enabled = {
			default = true, type = "boolean", label = "Reflective Floors",
			desc = "Glossy/wet floor system. PBR-aware reflectance via Reflectance + EnvironmentSpecularScale + Glass overlays.",
			tab = "Reflections", group = "Floors", save = true,
		},
		reflect_strength = {
			default = 0.55, type = "number", min = 0, max = 1, step = 0.05,
			label = "Reflectance Strength", desc = "Target Reflectance applied to classified floors (modulated by Fresnel).",
			tab = "Reflections", group = "Floors", save = true,
		},
		reflect_wetness = {
			default = 0.4, type = "number", min = 0, max = 1, step = 0.05,
			label = "Wetness", desc = "Raises gloss / lowers roughness on floors; weather can drive this automatically.",
			tab = "Reflections", group = "Floors", save = true,
		},
		reflect_fresnel = {
			default = 0.7, type = "number", min = 0, max = 1, step = 0.05,
			label = "Fresnel Power", desc = "Schlick-Fresnel from camLook·normal — stronger reflections at grazing angles.",
			tab = "Reflections", group = "Floors", save = true,
		},
		reflect_glass_overlay = {
			default = false, type = "boolean", label = "Glass Gloss Overlay",
			desc = "Adds a thin Glass-material overlay on flagged floors for SSR/refraction under Future.",
			tab = "Reflections", group = "Floors", requires = "futureLighting", save = true,
		},
		reflect_floor_tag = {
			default = "CinematicFloor", type = "string",
			label = "Floor Tag", desc = "CollectionService tag that force-marks a part as a reflective floor.",
			tab = "Reflections", group = "Floors", save = true,
		},
		reflect_mode = {
			default = "Raycast Probe (SSR approx.)", type = "option",
			options = { "Off", "Color Blend (cheap)", "Raycast Probe (SSR approx.)" },
			label = "Reflection Method", desc = "Color Blend = cheap tint fallback. Raycast Probe = roving workspace:Raycast accumulated temporally (an SSR APPROXIMATION, not true ray tracing).",
			tab = "Reflections", group = "Probes (SSR approximation)", save = true,
		},
		reflect_rays_per_frame = {
			default = 32, type = "number", min = 4, max = 160, step = 4,
			label = "Rays / Frame", desc = "Budget of roving reflection rays cast each frame.",
			tab = "Reflections", group = "Probes (SSR approximation)", save = true,
		},
		reflect_accum_frames = {
			default = 8, type = "number", min = 1, max = 32, step = 1,
			label = "Temporal Frames", desc = "How many frames the probe buffer accumulates over (more = stabler, laggier).",
			tab = "Reflections", group = "Probes (SSR approximation)", save = true,
		},
		reflect_smoothing = {
			default = 0.9, type = "number", min = 0, max = 0.98, step = 0.01,
			label = "Temporal Smoothing", desc = "Exponential blend that kills shimmer between frames.",
			tab = "Reflections", group = "Probes (SSR approximation)", save = true,
		},
		reflect_reproject = {
			default = true, type = "boolean", label = "Camera Reprojection",
			desc = "Reproject the accumulated buffer by camera delta so reflections track view motion.",
			tab = "Reflections", group = "Probes (SSR approximation)", save = true,
		},
		reflect_multibounce = {
			default = false, type = "boolean", label = "Multi-bounce",
			desc = "Allow a second raycast bounce. Doubles cost — auto-disabled on mobile.",
			tab = "Reflections", group = "Probes (SSR approximation)", save = true,
		},
		reflect_resolution = {
			default = 128, type = "number", min = 64, max = 256, step = 32,
			label = "Probe Buffer Size", desc = "EditableImage buffer resolution (px). Kept small — CPU bound.",
			tab = "Reflections", group = "Probes (SSR approximation)", requires = "editableImage", save = true,
		},
		reflect_mirror = {
			default = false, type = "boolean", label = "Hero Floor Mirror (showpiece, heavy)",
			desc = "Real planar mirror on the floor UNDER you (re-picks as you walk). Reflects nearby scenery AND your own character, synced every frame — you see yourself, animation and all. Mirror strength blends with wetness. EXPENSIVE (renders a 2nd camera) — strong-PC opt-in; it cannot reflect distant dynamic objects (engine limit).",
			tab = "Reflections", group = "Probes (SSR approximation)", save = true,
		},

		-- ════════════════════════ ATMOSPHERE ═══════════════════════════════
		atmos_enabled = {
			default = true, type = "boolean", label = "Atmosphere",
			desc = "Use the modern Atmosphere object (preferred over legacy FogStart/End).",
			tab = "Atmosphere & Weather", group = "Atmosphere", save = true,
		},
		atmos_density = {
			default = 0.18, type = "number", min = 0, max = 1, step = 0.01,
			label = "Density", desc = "Atmosphere.Density — distance haze thickness.",
			tab = "Atmosphere & Weather", group = "Atmosphere", save = true,
		},
		atmos_offset = {
			default = 0.1, type = "number", min = 0, max = 1, step = 0.01,
			label = "Offset", desc = "Atmosphere.Offset — horizon haze bias.",
			tab = "Atmosphere & Weather", group = "Atmosphere", save = true,
		},
		atmos_color = {
			default = Color3.fromRGB(212, 210, 212), type = "color",
			label = "Atmosphere Color", desc = "Atmosphere.Color.",
			tab = "Atmosphere & Weather", group = "Atmosphere", save = true,
		},
		atmos_decay = {
			default = Color3.fromRGB(106, 112, 125), type = "color",
			label = "Decay Color", desc = "Atmosphere.Decay — colour the haze fades toward.",
			tab = "Atmosphere & Weather", group = "Atmosphere", save = true,
		},
		atmos_glare = {
			default = 0.04, type = "number", min = 0, max = 10, step = 0.05,
			label = "Glare", desc = "Atmosphere.Glare — sun glare bloom.",
			tab = "Atmosphere & Weather", group = "Atmosphere", save = true,
		},
		atmos_haze = {
			default = 0.5, type = "number", min = 0, max = 10, step = 0.1,
			label = "Haze", desc = "Atmosphere.Haze.",
			tab = "Atmosphere & Weather", group = "Atmosphere", save = true,
		},

		-- ════════════════════════ SKY + CLOUDS ═════════════════════════════
		sky_enabled = {
			default = true, type = "boolean", label = "Custom Sky",
			desc = "Swap in a curated Sky (skybox, sun/moon size, stars).",
			tab = "Atmosphere & Weather", group = "Sky", save = true,
		},
		sky_preset = {
			default = "Default", type = "option",
			options = { "Default", "Clear Blue", "Golden Dusk", "Overcast", "Night Stars" },
			label = "Sky Preset", desc = "Curated skybox presets.",
			tab = "Atmosphere & Weather", group = "Sky", save = true,
		},
		sky_sun_size = {
			default = 21, type = "number", min = 0, max = 100, step = 1,
			label = "Sun Angular Size", desc = "Sky.SunAngularSize.",
			tab = "Atmosphere & Weather", group = "Sky", save = true,
		},
		sky_moon_size = {
			default = 11, type = "number", min = 0, max = 100, step = 1,
			label = "Moon Angular Size", desc = "Sky.MoonAngularSize.",
			tab = "Atmosphere & Weather", group = "Sky", save = true,
		},
		sky_star_count = {
			default = 3000, type = "number", min = 0, max = 8000, step = 100,
			label = "Star Count", desc = "Sky.StarCount.",
			tab = "Atmosphere & Weather", group = "Sky", save = true,
		},
		clouds_enabled = {
			default = true, type = "boolean", label = "Clouds",
			desc = "workspace.Terrain Clouds object (NOT an 'Atmosphere clouds' — that does not exist).",
			tab = "Atmosphere & Weather", group = "Clouds", save = true,
		},
		clouds_cover = {
			default = 0.55, type = "number", min = 0, max = 1, step = 0.01,
			label = "Cloud Cover", desc = "Clouds.Cover.",
			tab = "Atmosphere & Weather", group = "Clouds", save = true,
		},
		clouds_density = {
			default = 0.6, type = "number", min = 0, max = 1, step = 0.01,
			label = "Cloud Density", desc = "Clouds.Density.",
			tab = "Atmosphere & Weather", group = "Clouds", save = true,
		},
		clouds_color = {
			default = Color3.fromRGB(240, 242, 248), type = "color",
			label = "Cloud Color", desc = "Clouds.Color.",
			tab = "Atmosphere & Weather", group = "Clouds", save = true,
		},

		-- ════════════════════════ WEATHER + MOOD ═══════════════════════════
		weather_mode = {
			default = "Clear", type = "option",
			options = { "Clear", "Rain", "Snow", "Storm" },
			label = "Weather", desc = "Weather state machine. Transitions are smoothed; wet surfaces gain reflectance.",
			tab = "Atmosphere & Weather", group = "Weather", save = true,
		},
		weather_intensity = {
			default = 0.7, type = "number", min = 0, max = 1, step = 0.05,
			label = "Weather Intensity", desc = "Particle rate / opacity scale for the active weather.",
			tab = "Atmosphere & Weather", group = "Weather", save = true,
		},
		weather_wind = {
			default = 0.4, type = "number", min = 0, max = 1, step = 0.05,
			label = "Wind", desc = "Drives precipitation slant and foliage sway.",
			tab = "Atmosphere & Weather", group = "Weather", save = true,
		},
		weather_lightning = {
			default = true, type = "boolean", label = "Storm Lightning",
			desc = "Stochastic lightning flashes (bloom spike + light) during Storm.",
			tab = "Atmosphere & Weather", group = "Weather", save = true,
		},
		weather_wet_boost = {
			default = 0.5, type = "number", min = 0, max = 1, step = 0.05,
			label = "Wet Surface Boost", desc = "How much rain/storm raises floor reflectance/wetness.",
			tab = "Atmosphere & Weather", group = "Weather", save = true,
		},
		mood_preset = {
			default = "Custom", type = "option",
			options = { "Custom", "Golden Hour", "Blue Hour", "Noon", "Night", "Overcast" },
			label = "Mood / Time", desc = "Named time-of-day moods. Selecting one drives ClockTime + ambient toward that look.",
			tab = "Atmosphere & Weather", group = "Mood", save = true,
		},
		mood_auto_cycle = {
			default = false, type = "boolean", label = "Day/Night Cycle",
			desc = "Continuously advance ClockTime for a living sky.",
			tab = "Atmosphere & Weather", group = "Mood", save = true,
		},
		mood_cycle_speed = {
			default = 0.3, type = "number", min = 0.01, max = 4, step = 0.01,
			label = "Cycle Speed", desc = "In-game hours advanced per real second when cycling.",
			tab = "Atmosphere & Weather", group = "Mood", save = true,
		},

		-- ════════════════════════ ENHANCERS ════════════════════════════════
		enh_enabled = {
			default = true, type = "boolean", label = "Scene Enhancers",
			desc = "Master toggle for budget-aware scene enhancers (foliage/fire/smoke/water/dust/beams).",
			tab = "Atmosphere & Weather", group = "Enhancers", save = true,
		},
		enh_foliage_wind = {
			default = true, type = "boolean", label = "Foliage Wind",
			desc = "Sway flagged foliage with noise-driven wind.",
			tab = "Atmosphere & Weather", group = "Enhancers", save = true,
		},
		enh_fire = {
			default = true, type = "boolean", label = "Enhanced Fire",
			desc = "Add PointLight + bloom + heat-haze to Fire instances.",
			tab = "Atmosphere & Weather", group = "Enhancers", save = true,
		},
		enh_smoke = {
			default = true, type = "boolean", label = "Layered Smoke",
			desc = "Soften and layer Smoke emitters.",
			tab = "Atmosphere & Weather", group = "Enhancers", save = true,
		},
		enh_water = {
			default = true, type = "boolean", label = "Water Polish",
			desc = "Terrain water tuning: fresnel tint, transparency, wet edge.",
			tab = "Atmosphere & Weather", group = "Enhancers", save = true,
		},
		enh_dust = {
			default = true, type = "boolean", label = "Ambient Dust",
			desc = "Floating dust motes near the camera for volumetric feel.",
			tab = "Atmosphere & Weather", group = "Enhancers", save = true,
		},
		enh_lights_repair = {
			default = true, type = "boolean", label = "Light Polish",
			desc = "Subtle flicker/repair pass on existing PointLights/SpotLights.",
			tab = "Atmosphere & Weather", group = "Enhancers", save = true,
		},
		enh_godrays = {
			default = true, type = "boolean", label = "God Rays (Beams)",
			desc = "Volumetric light shafts faked with Beams near the sun/lights. Coverage-capped.",
			tab = "Atmosphere & Weather", group = "Enhancers", save = true,
		},
		enh_godray_strength = {
			default = 0.3, type = "number", min = 0, max = 1, step = 0.05,
			label = "God Ray Strength", desc = "Beam transparency/scale for light shafts.",
			tab = "Atmosphere & Weather", group = "Enhancers", save = true,
		},
		enh_light_shadows = {
			default = true, type = "boolean", label = "Light Shadows",
			desc = "Enable real shadow casting on existing PointLights/SpotLights (defaults to off in most games). The single biggest indoor/night upgrade — capped to nearby lights for perf.",
			tab = "Atmosphere & Weather", group = "Enhancers", save = true,
		},
		enh_light_beams = {
			default = true, type = "boolean", label = "Street Light Beams (night)",
			desc = "Volumetric light cones from each PointLight/SpotLight, visible only at night — the developed-night-city look. Coverage-capped, near-camera only.",
			tab = "Atmosphere & Weather", group = "Enhancers", save = true,
		},

		-- ════════════════════════ CAMERA & CINEMATIC ═══════════════════════
		cam_enabled = {
			default = true, type = "boolean", label = "Cinematic Camera",
			desc = "Master toggle for camera FX. Runs NON-EXCLUSIVELY — if another script owns the camera we only add offsets and warn.",
			tab = "Camera & Cinematic", group = "Camera", save = true,
		},
		cam_fov_base = {
			default = 70, type = "number", min = 40, max = 110, step = 1,
			label = "Base FOV", desc = "Camera.FieldOfView baseline.",
			tab = "Camera & Cinematic", group = "Camera", save = true,
		},
		cam_fov_kick = {
			default = 8, type = "number", min = 0, max = 30, step = 1,
			label = "Sprint FOV Kick", desc = "Extra FOV added at full movement speed (smoothed).",
			tab = "Camera & Cinematic", group = "Camera", save = true,
		},
		cam_dof_enabled = {
			default = true, type = "boolean", label = "Auto-Focus DoF",
			desc = "DepthOfFieldEffect whose focus distance auto-tracks what the camera looks at.",
			tab = "Camera & Cinematic", group = "Depth of Field", save = true,
		},
		cam_dof_aperture = {
			default = 18, type = "number", min = 0, max = 200, step = 1,
			label = "Aperture", desc = "DepthOfFieldEffect.FarIntensity feel — bokeh strength.",
			tab = "Camera & Cinematic", group = "Depth of Field", save = true,
		},
		cam_dof_focus_speed = {
			default = 0.25, type = "number", min = 0.02, max = 2, step = 0.01,
			label = "Focus Speed (tau)", desc = "Exponential focus-pull lag.",
			tab = "Camera & Cinematic", group = "Depth of Field", save = true,
		},
		cam_motionblur = {
			default = true, type = "boolean", label = "Motion Blur (faked)",
			desc = "Velocity smear via a GUI overlay + micro BlurEffect pulse. There is NO MotionBlurEffect in Roblox.",
			tab = "Camera & Cinematic", group = "Motion Blur", save = true,
		},
		cam_motionblur_amount = {
			default = 0.35, type = "number", min = 0, max = 1, step = 0.05,
			label = "Motion Blur Amount", desc = "Strength of the faked smear.",
			tab = "Camera & Cinematic", group = "Motion Blur", save = true,
		},
		cam_shake = {
			default = true, type = "boolean", label = "Camera Shake",
			desc = "Perlin idle sway + impulse shakes (handheld feel).",
			tab = "Camera & Cinematic", group = "Shake", save = true,
		},
		cam_shake_amount = {
			default = 0.3, type = "number", min = 0, max = 1, step = 0.05,
			label = "Shake Amount", desc = "Amplitude of idle handheld sway.",
			tab = "Camera & Cinematic", group = "Shake", save = true,
		},
		-- Overlays (all FAKED — engine has no native vignette/grain/CA/letterbox)
		overlay_vignette = {
			default = true, type = "boolean", label = "Vignette (overlay)",
			desc = "Radial darkening via a GUI ImageLabel — faked, does not anti-alias the scene.",
			tab = "Camera & Cinematic", group = "Cinematic Overlays (faked)", save = true,
		},
		overlay_vignette_intensity = {
			default = 0.32, type = "number", min = 0, max = 1, step = 0.05,
			label = "Vignette Intensity", desc = "Overlay opacity.",
			tab = "Camera & Cinematic", group = "Cinematic Overlays (faked)", save = true,
		},
		overlay_grain = {
			default = true, type = "boolean", label = "Film Grain (overlay)",
			desc = "Animated grain via tiled overlay / EditableImage noise.",
			tab = "Camera & Cinematic", group = "Cinematic Overlays (faked)", save = true,
		},
		overlay_grain_intensity = {
			default = 0.06, type = "number", min = 0, max = 1, step = 0.02,
			label = "Grain Intensity", desc = "Grain overlay opacity.",
			tab = "Camera & Cinematic", group = "Cinematic Overlays (faked)", save = true,
		},
		overlay_chromatic = {
			default = false, type = "boolean", label = "Chromatic Aberration (overlay)",
			desc = "Edge RGB-split via offset coloured ImageLabels — faked.",
			tab = "Camera & Cinematic", group = "Cinematic Overlays (faked)", save = true,
		},
		overlay_chromatic_intensity = {
			default = 0.14, type = "number", min = 0, max = 1, step = 0.05,
			label = "Chromatic Amount", desc = "Edge split strength.",
			tab = "Camera & Cinematic", group = "Cinematic Overlays (faked)", save = true,
		},
		overlay_letterbox = {
			default = false, type = "boolean", label = "Letterbox",
			desc = "Cinematic bars via two GUI Frames.",
			tab = "Camera & Cinematic", group = "Cinematic Overlays (faked)", save = true,
		},
		overlay_letterbox_ratio = {
			default = 2.39, type = "number", min = 1.5, max = 2.8, step = 0.01,
			label = "Aspect Ratio", desc = "Target cinematic aspect (2.39 = anamorphic scope).",
			tab = "Camera & Cinematic", group = "Cinematic Overlays (faked)", save = true,
		},
		overlay_dither = {
			default = true, type = "boolean", label = "Anti-banding Dither",
			desc = "Near-transparent tiled blue-noise overlay (EditableImage authored) to hide gradient banding. Does NOT anti-alias 3D edges.",
			tab = "Camera & Cinematic", group = "Cinematic Overlays (faked)", requires = "editableImage", save = true,
		},

		-- ════════════════════════ MATERIALS / PBR ══════════════════════════
		pbr_enabled = {
			default = true, type = "boolean", label = "PBR Material Pass",
			desc = "Classify materials → roughness/F0 and bias reflectance/specular accordingly.",
			tab = "Materials", group = "PBR", save = true,
		},
		pbr_roughness_bias = {
			default = 0.0, type = "number", min = -0.5, max = 0.5, step = 0.01,
			label = "Global Roughness Bias", desc = "Shift all classified roughness (− = glossier).",
			tab = "Materials", group = "PBR", save = true,
		},
		pbr_reflectance_bias = {
			default = 0.0, type = "number", min = 0, max = 0.6, step = 0.01,
			label = "Global Reflectance Bias", desc = "Add baseline Reflectance to metallic/smooth materials.",
			tab = "Materials", group = "PBR", save = true,
		},
		pbr_metal_boost = {
			default = 0.5, type = "number", min = 0, max = 1, step = 0.05,
			label = "Metal Reflectance", desc = "How reflective metal-classified materials become.",
			tab = "Materials", group = "PBR", save = true,
		},
		pbr_surface_appearance = {
			default = false, type = "boolean", label = "SurfaceAppearance (advanced)",
			desc = "Apply optional SurfaceAppearance (ColorMap/NormalMap/MetalnessMap/RoughnessMap) to author-flagged surfaces. NOTE: correct property is ColorMap, NOT AlbedoMap.",
			tab = "Materials", group = "PBR", save = true,
		},

		-- ════════════════════════ PERFORMANCE ══════════════════════════════
		perf_adaptive = {
			default = true, type = "boolean", label = "Adaptive Quality",
			desc = "Closed-loop controller that scales effects to hold the target FPS (with hysteresis).",
			tab = "Performance", group = "Adaptive", save = true,
		},
		perf_target_fps = {
			default = 60, type = "number", min = 24, max = 144, step = 1,
			label = "Target FPS", desc = "Frame-rate the adaptive controller defends.",
			tab = "Performance", group = "Adaptive", save = true,
		},
		perf_min_quality = {
			default = 0.2, type = "number", min = 0, max = 1, step = 0.05,
			label = "Min Quality Floor", desc = "Adaptive controller will not drop below this.",
			tab = "Performance", group = "Adaptive", save = true,
		},
		perf_hud = {
			default = false, type = "boolean", label = "Performance HUD",
			desc = "On-screen FPS / frame-time / per-effect cost readout.",
			tab = "Performance", group = "Diagnostics", save = true,
		},
		perf_scanner_budget = {
			default = 120, type = "number", min = 20, max = 600, step = 10,
			label = "Scanner Parts/Frame", desc = "Max parts the world scanner classifies per frame (streaming-aware, debounced).",
			tab = "Performance", group = "Diagnostics", save = true,
		},
	}

	-- ── UI LAYOUT (ordering) ────────────────────────────────────────────────
	-- Schema walks this; each entry = { tab, group, keys = {...} }.
	Config.layout = {
		{ tab = "General", group = "Master", keys = {
			"master_enabled", "quality", "ui_keybind", "intro_notify", "log_level" } },

		{ tab = "Lighting", group = "Core", keys = {
			"lighting_enabled", "lighting_future", "lighting_brightness", "lighting_exposure",
			"lighting_clock_time", "lighting_geo_latitude", "lighting_global_shadows",
			"lighting_shadow_softness", "lighting_ambient", "lighting_outdoor_ambient",
			"lighting_env_diffuse", "lighting_env_specular", "lighting_color_shift_top",
			"lighting_color_shift_bottom" } },
		{ tab = "Lighting", group = "Tonemap (filmic, approx.)", keys = {
			"tonemap_enabled", "tonemap_mode", "tonemap_contrast", "tonemap_saturation", "tonemap_white_point" } },
		{ tab = "Lighting", group = "Eye Adaptation", keys = {
			"eye_adapt_enabled", "eye_adapt_target", "eye_adapt_speed", "eye_adapt_min", "eye_adapt_max" } },
		{ tab = "Lighting", group = "Bloom", keys = {
			"bloom_enabled", "bloom_intensity", "bloom_size", "bloom_threshold", "bloom_exposure_couple" } },
		{ tab = "Lighting", group = "Creative Grade", keys = {
			"grade_enabled", "grade_brightness", "grade_contrast", "grade_saturation", "grade_tint" } },

		{ tab = "Reflections", group = "Floors", keys = {
			"reflect_enabled", "reflect_strength", "reflect_wetness", "reflect_fresnel",
			"reflect_glass_overlay", "reflect_floor_tag" } },
		{ tab = "Reflections", group = "Probes (SSR approximation)", keys = {
			"reflect_mode", "reflect_rays_per_frame", "reflect_accum_frames", "reflect_smoothing",
			"reflect_reproject", "reflect_multibounce", "reflect_resolution", "reflect_mirror" } },

		{ tab = "Atmosphere & Weather", group = "Atmosphere", keys = {
			"atmos_enabled", "atmos_density", "atmos_offset", "atmos_color", "atmos_decay",
			"atmos_glare", "atmos_haze" } },
		{ tab = "Atmosphere & Weather", group = "Sky", keys = {
			"sky_enabled", "sky_preset", "sky_sun_size", "sky_moon_size", "sky_star_count" } },
		{ tab = "Atmosphere & Weather", group = "Clouds", keys = {
			"clouds_enabled", "clouds_cover", "clouds_density", "clouds_color" } },
		{ tab = "Atmosphere & Weather", group = "Weather", keys = {
			"weather_mode", "weather_intensity", "weather_wind", "weather_lightning", "weather_wet_boost" } },
		{ tab = "Atmosphere & Weather", group = "Mood", keys = {
			"mood_preset", "mood_auto_cycle", "mood_cycle_speed" } },
		{ tab = "Atmosphere & Weather", group = "Enhancers", keys = {
			"enh_enabled", "enh_foliage_wind", "enh_fire", "enh_smoke", "enh_water",
			"enh_dust", "enh_lights_repair", "enh_light_shadows", "enh_light_beams",
			"enh_godrays", "enh_godray_strength" } },

		{ tab = "Camera & Cinematic", group = "Camera", keys = {
			"cam_enabled", "cam_fov_base", "cam_fov_kick" } },
		{ tab = "Camera & Cinematic", group = "Depth of Field", keys = {
			"cam_dof_enabled", "cam_dof_aperture", "cam_dof_focus_speed" } },
		{ tab = "Camera & Cinematic", group = "Motion Blur", keys = {
			"cam_motionblur", "cam_motionblur_amount" } },
		{ tab = "Camera & Cinematic", group = "Shake", keys = {
			"cam_shake", "cam_shake_amount" } },
		{ tab = "Camera & Cinematic", group = "Cinematic Overlays (faked)", keys = {
			"overlay_vignette", "overlay_vignette_intensity", "overlay_grain", "overlay_grain_intensity",
			"overlay_chromatic", "overlay_chromatic_intensity", "overlay_letterbox",
			"overlay_letterbox_ratio", "overlay_dither" } },

		{ tab = "Materials", group = "PBR", keys = {
			"pbr_enabled", "pbr_roughness_bias", "pbr_reflectance_bias", "pbr_metal_boost", "pbr_surface_appearance" } },

		{ tab = "Performance", group = "Adaptive", keys = {
			"perf_adaptive", "perf_target_fps", "perf_min_quality" } },
		{ tab = "Performance", group = "Diagnostics", keys = {
			"perf_hud", "perf_scanner_budget" } },
	}

	-- ── derive flat defaults snapshot ─────────────────────────────────────────
	function Config.buildDefaults()
		local out = {}
		for key, meta in pairs(Config.meta) do
			out[key] = meta.default
		end
		return out
	end

	-- ── validate + clamp a value against its meta ─────────────────────────────
	-- Returns the coerced value (never raises). Unknown keys pass through.
	function Config.coerce(key, value)
		local meta = Config.meta[key]
		if not meta then return value end
		local t = meta.type
		if t == "number" then
			value = tonumber(value)
			if value == nil then return meta.default end
			if meta.min ~= nil and value < meta.min then value = meta.min end
			if meta.max ~= nil and value > meta.max then value = meta.max end
			if meta.step and meta.step > 0 then
				value = math.floor(value / meta.step + 0.5) * meta.step
				-- guard against fp drift pushing past bounds
				if meta.max ~= nil and value > meta.max then value = meta.max end
				if meta.min ~= nil and value < meta.min then value = meta.min end
			end
			return value
		elseif t == "boolean" then
			return value and true or false
		elseif t == "option" then
			for _, opt in ipairs(meta.options or {}) do
				if opt == value then return value end
			end
			return meta.default
		elseif t == "keybind" then
			-- accept a KeyCode name string or an EnumItem
			if typeof(value) == "EnumItem" then return value.Name end
			if type(value) == "string" then return value end
			return meta.default
		elseif t == "color" then
			if typeof(value) == "Color3" then return value end
			return meta.default
		else -- string / freeform
			if value == nil then return meta.default end
			return tostring(value)
		end
	end

	-- Convenience used by callers needing a typed read of meta.
	function Config.get(key) return Config.meta[key] end

	return Config
end
