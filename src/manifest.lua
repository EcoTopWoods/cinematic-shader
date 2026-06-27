--!nonstrict
--[[
	src/manifest.lua
	-----------------------------------------------------------------------------
	Module registry + load metadata. Returned as a factory like every module, but
	it requires nothing — the loader can call it with a no-op require to read the
	table before the shim is fully warmed.

	* version        — suite version (kept in sync with Config.version).
	* repo           — GitHub coordinates the network loader pins to (EDIT THESE).
	* modules        — EVERY src logical name. Used by:
	                     - the network loader to eagerly warm-fetch all files,
	                     - build/bundle.lua to inline them in a deterministic order.
	                   Order is irrelevant to correctness (requires are lazy) but
	                   core/ is listed first for readability.
	* boot           — ordered list of CONTROLLER modules that init:start()s. Each
	                   controller requires + starts its own sub-modules, so init
	                   never needs to know every leaf file.
]]

return function(_require)
	local manifest = {}

	manifest.version = "1.0.9"
	manifest.schemaVersion = 1

	-- ⚠ EDIT FOR YOUR FORK: the loader pins network fetches to <user>/<name>@<ref>.
	manifest.repo = {
		user = "EcoTopWoods",
		name = "cinematic-shader",
		ref = "v1.0.9", -- a TAG or commit SHA — never a moving branch in production
		srcDir = "src",
	}

	-- Every module file (logical name = path under src/ without extension).
	manifest.modules = {
		-- core
		"core/Util", "core/Logger", "core/Signal", "core/Maid", "core/Platform",
		"core/Config", "core/State", "core/Snapshot",
		-- entry
		"manifest", "init",
		-- detection / materials (needed early by others)
		"detection/Scanner",
		"materials/PBR",
		-- lighting
		"lighting/Lighting", "lighting/Tonemap", "lighting/Atmosphere", "lighting/Sky",
		-- postfx
		"postfx/Pipeline", "postfx/Bloom", "postfx/DepthOfField", "postfx/ColorGrade",
		"postfx/Vignette", "postfx/FilmGrain", "postfx/Dither", "postfx/Chromatic", "postfx/Letterbox",
		-- reflections
		"reflections/Reflections", "reflections/OverlayReflection",
		"reflections/ViewportMirror", "reflections/RaycastProbe",
		-- weather
		"weather/Weather", "weather/Rain", "weather/Snow", "weather/Storm", "weather/Lightning",
		-- time of day
		"timeofday/Mood",
		-- camera
		"camera/CameraFX", "camera/FOV", "camera/DoFAuto", "camera/MotionBlur",
		"camera/EyeAdaptation", "camera/Shake", "camera/Freecam", "camera/PhotoMode",
		-- enhancers
		"enhancers/Enhancers", "enhancers/Foliage", "enhancers/Fire", "enhancers/Smoke",
		"enhancers/Water", "enhancers/Particles", "enhancers/Lights", "enhancers/Beams",
		-- perf
		"perf/AdaptiveQuality", "perf/Benchmark", "perf/PerfHUD",
		-- presets
		"presets/Presets", "presets/Serializer", "presets/ConfigStore",
		-- ui
		"ui/UI", "ui/Schema", "ui/Controls", "ui/Notify", "ui/FallbackUI",
		-- api
		"api/API", "api/Teardown",
	}

	-- Controllers init starts, in order. Each owns + starts its sub-modules.
	manifest.boot = {
		"detection/Scanner",
		"materials/PBR",
		"lighting/Lighting",
		"postfx/Pipeline",
		"reflections/Reflections",
		"timeofday/Mood",
		"weather/Weather",
		"enhancers/Enhancers",
		"camera/CameraFX",
		"perf/AdaptiveQuality",
		"ui/UI",
		"api/API",
	}

	return manifest
end
