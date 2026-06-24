# Changelog

All notable changes to the Cinematic Graphics Suite are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/);
this project uses [Semantic Versioning](https://semver.org/).

## [1.0.5] — 2026-06-23

### Added — Hero Floor Mirror is now a real showpiece (opt-in)
The `reflect_mirror` toggle (Reflections tab) was rebuilt from a static-subset gimmick
into a proper planar mirror:
- **Auto-picks the floor directly under you** (raycast down) and re-homes onto a new
  floor as you walk (with a 1.5 s cooldown so crossing many small parts can't thrash).
- **Reflects you.** The local character is cloned into the mirror and its part CFrames
  are synced every frame — you see yourself, animation and all.
- **Reflects nearby scenery** via a cheap `GetPartBoundsInBox` region query (capped 55,
  refreshed every 4 s), never `GetDescendants` — no tree-walk hitch.
- **Correct planar reflection** of the camera (position *and* orientation across the
  floor plane), viewport sun synced to the scene, and mirror strength that **blends
  with wetness** so it reads as a wet sheen rather than chrome.
- Enabled by the **Ultra** preset; still off by default (renders a 2nd camera — heavy).

Honest limit: it reflects the cloned subset + you, not distant dynamic objects — Roblox
has no render-to-texture of the live scene, so a fully-universal mirror is impossible.

## [1.0.4] — 2026-06-23

### Fixed
- **The gray wedge in the sky that "followed the camera so precisely"** was a pair
  of camera-facing accent `Beam`s parked in front of the view (FaceCamera + camera-
  relative placement). Deleted entirely. God-rays now use ONLY the engine's
  sun-anchored `SunRaysEffect`, which stays on the actual sun and does not track your
  view — and is kept subtle.
- **Still over-bright**: Brightness 1.6→1.4, Exposure −0.15→−0.2, sun rays gentled.

### Changed
- **Crisper shadows**: `ShadowSoftness` 0.45→0.3 for a tighter, more realistic
  penumbra under Future lighting. Added a one-time hint to set Roblox Graphics to
  Manual/Quality 10 — shadow & reflection *resolution* is the client's graphics
  setting and cannot be forced from a script (honest limitation).
- **Reflections that feel real**: `EnvironmentSpecularScale` 1.0→1.3 so the sky/sun
  genuinely reflect in glossy/wet surfaces (real Future environment reflection),
  paired with the albedo-aware reflectance from 1.0.3.

## [1.0.3] — 2026-06-23

Quality pass — ported the three techniques that made a hand-tuned reference
shader read better, especially for night cities.

### Added
- **Streetlight beams (`enh_light_beams`)** — every nearby PointLight/SpotLight
  gets a tight inner cone + soft outer halo (camera-facing Beams), visible only at
  night (driven by the real sun direction). The developed-night-city look. Coverage-
  capped (120 desktop / 24 mobile), built a few rigs per frame so a lit district
  never spikes a frame, cached sequences → zero per-frame allocation.
- **Light shadows (`enh_light_shadows`)** — turns on `Shadows` for existing lights
  (most games ship them off). The biggest single indoor/night upgrade.

### Changed
- **Albedo-aware floor reflectance** — reflectance now scales by surface brightness
  (true blacks ≈0.12×, whites ≈1.15×), so wet asphalt stays dark instead of turning
  chrome/silver. This is the realism trick that makes wet streets look real.
- Punchier defaults: `EnvironmentDiffuseScale` 0.9→0.8 (less ambient wash, more
  contrast) and bloom threshold 1.1→1.2 (only genuinely bright things bloom).
- **Ultra** and **Night City** presets now enable light shadows + streetlight beams.

## [1.0.2] — 2026-06-23

Stability + look pass. Kills the periodic freeze, the gray planes, and the blue cast.

### Fixed
- **Periodic freeze during play** (sharp moves / spawns) was the hero-floor
  **ViewportMirror**: it auto-enabled on Ultra and ran `workspace:GetDescendants()`
  + up to 40 `:Clone()` calls every 3 s — a guaranteed hitch on big places. It is
  now **off by default** (opt-in `reflect_mirror` toggle) and, when enabled, uses a
  cheap `GetPartBoundsInBox` region query instead of walking the whole tree.
- **"Gray shadow-like things above me"** were the Glass *sheen overlay* planes:
  large up-facing parts (ceilings, overpasses) were classified as floors and got a
  translucent gray plane stuck on top. Glass overlays are now **off by default**, and
  even when on they are never created on a surface above eye level.
- **Blue tint** on bright/bloomed areas: neutralised the cool defaults —
  Ambient, OutdoorAmbient, ColorShift_Bottom and Atmosphere colour are now neutral.
- **Over-brightened lighting**: Brightness 1.9→1.6, Exposure −0.1→−0.15, GI feel
  0.9. Grain dropped to 0.06 and reflection temporal smoothing raised to 0.9 to
  reduce per-pixel shimmer.

### Added
- **Night City** preset — GTA-style developed-night look: deep contrast, controlled
  exposure, warm sodium key vs cool city bounce (a tasteful teal-orange split, not a
  flat blue wash), neon/streetlights that bloom while the rest stays grounded, wet
  reflective streets, stars. Apply from the Presets tab.
- **Hero Floor Mirror** toggle (Reflections tab) — the opt-in for the heavy mirror.

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
