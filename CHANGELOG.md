# Changelog

All notable changes to the Cinematic Graphics Suite are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/);
this project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-06-23

Initial public release.

### Added
- **Architecture**: ~60-file modular suite with a dependency-injected `require`
  shim, a central typed `Config` (one source of truth), live `State` with a change
  signal, `Maid`/`Snapshot` robustness layer, and per-domain controllers.
- **Lighting**: capability-gated `Technology = Future`, `LightingStyle = Realistic`
  + `PrioritizeLightingQuality` when present, `ShadowSoftness`, full ambient/exposure/
  ClockTime/latitude/GI control.
- **Post-FX pipeline**: filmic ACES-approx tonemap CCE *before* a creative grade CCE,
  HDR-style bloom whose threshold couples to auto-exposure, auto-focus depth of field,
  and faked vignette / film-grain / dither / chromatic / letterbox / motion-blur
  overlays (GUI + `EditableImage`, feature-detected).
- **Eye adaptation**: scene-luminance estimate driving `ExposureCompensation` with
  frame-rate-independent exponential smoothing.
- **Reflections**: PBR-aware, Fresnel-driven glossy/wet floors; budgeted, temporally
  smoothed, camera-reprojected raycast reflection probes (honest SSR approximation)
  with a cheap color-blend tier and an optional high-tier viewport hero mirror.
- **Atmosphere / Sky / Clouds**, **weather** (rain/snow/storm/lightning) with smooth
  transitions and wet-surface coupling, and named **moods** + day/night cycle.
- **Cinematic camera**: dynamic FOV, auto-focus DoF, faked motion blur, Perlin +
  impulse shake, freecam, and a non-seizing photo mode with composition aids.
- **Enhancers**: foliage wind, fire light, layered smoke, water polish, ambient dust,
  light flicker, and faked god-ray beams — all budget-aware, zero per-frame
  sequence allocation.
- **Performance**: startup micro-benchmark, closed-loop adaptive quality with
  hysteresis, and a toggleable PerfHUD.
- **UI**: Rayfield panel auto-generated from `Config` (live, searchable, persisted),
  with a native FallbackUI when Rayfield is unavailable.
- **Distribution**: network `loader.lua` (mirrors + retries + disk cache), offline
  `cinematic.lua` bundle, `build/bundle.lua`, and a Rojo project.
- **Robustness**: double-load guard, full Snapshot restore (zero residue), and a
  bulletproof `kill()` / public API on `_G`/`getgenv()`.
