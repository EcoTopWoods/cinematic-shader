# Changelog

All notable changes to the Cinematic Graphics Suite are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/);
this project uses [Semantic Versioning](https://semver.org/).

## [1.0.1] — 2026-06-23

Tuning + reliability pass after first in-game testing. The default look now
*enhances* a scene instead of blowing it out, and auto-adapts to any game.

### Fixed
- **Network loader was unreliable** — it fetched all ~64 source modules in a
  parallel burst, tripping `raw.githubusercontent.com` rate limiting and aborting.
  It now fetches the single pre-built `dist/cinematic.lua` bundle in **one request**
  (mirrors + retries + disk cache retained). One request ≫ sixty-four.
- **God-rays were blocky white slabs** parked in front of the camera regardless of
  sun position. Replaced with the engine's real `SunRaysEffect`, driven by actual
  sun on-screen visibility (`camLook · sunDirection`) — rays now emanate from the
  sun and fade as it leaves view. A whisper-thin accent beam appears only when you
  look almost straight into the sun.
- **Blown-out / washed-out default grade.** Calmed the defaults so the suite grades
  rather than overexposes: brightness 2.2→1.9, exposure 0.15→−0.1, bloom 1.1→0.5
  (threshold 0.9→1.1), atmosphere haze 1.8→0.5, glare 0.35→0.04. Chromatic aberration
  now **off** by default (it read as the "fake AI cinematic" tell).

### Changed
- **Eye-adaptation reworked** into a proper auto-adapt: meters a representative fan
  of view rays (sky misses count as full brightness) and eases exposure around the
  static baseline with a tightened clamp — settles near-neutral on a well-lit game,
  genuinely darkens bright scenes, lifts dark ones. No more runaway over-exposure.
- **New `Ultra` preset** (best-quality / extreme): full raycast reflection probe,
  soft shadows, shallow DoF, rich-but-restrained grade — deliberately not blown out.
  Retuned `Cinematic` to match the calmer baseline.
- Config save-slot epoch bumped so a retuned release starts from fresh defaults
  instead of reloading your old saved (blown-out) values.

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
