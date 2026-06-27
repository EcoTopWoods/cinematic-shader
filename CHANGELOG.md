# Changelog

All notable changes to the Cinematic Graphics Suite are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/);
this project uses [Semantic Versioning](https://semver.org/).

## [1.0.12] — 2026-06-23

### Changed — CLARITY: sharp, not blurry/overexposed
The "blurry / overexposed / not clear" look was depth-of-field + motion blur + bloom
softening the image. The default is now sharp and clean:
- **Depth of Field OFF by default** (was blurring the whole background).
- **Motion blur OFF by default.**
- **Bloom minimised** (0.3→0.18, threshold up) so nothing halos/washes.
- **Less exposure / haze** (brightness 1.3, exposure −0.25, atmosphere haze 0.18,
  density 0.12, env-specular 1.35) and **grain off** — clearer air, no overexposure.
- Realistic+ and Cinematic presets retuned to match (DoF + beams + grain off).

### Changed — UI swapped from Rayfield to Fluent
The control panel now uses the **Fluent** library — a sleek, app-style dark UI with
icons per tab. Same auto-generated controls (sliders/toggles/dropdowns/colour/keybind),
same live updates, same preset / import-export / freecam / photo-mode / unload actions.
The toggle key now **minimises** the window (Fluent style). FallbackUI still covers the
no-HTTP case. (Dropping Rayfield's auto-save also removes the stale-saved-config issue.)

### Note
Geometry is never modified — the suite only *reads* the world (raycasts) to drive
lighting. And Roblox still exposes no programmable GPU shaders / RTX access; set
Roblox Graphics to Manual / Quality 10 to use your card's full output.

## [1.0.11] — 2026-06-23

### Changed
- **All beam effects off by default.** The sun god-rays (SunRaysEffect) and the
  streetlight beams (camera-facing `Beam` quads that rotate to face you — read as
  "following") are now opt-in. The default look has no beams at all.
- **New `Lite` preset** — the gentlest touch: FIXED exposure (no auto-exposure shift),
  no god rays / beams / motion blur / DoF / vignette / grain / dust. Just Future
  lighting, tight shadows, a whisper of contrast, and cheap subtle reflections. For
  when the full effect feels like too much. Second in the dropdown.

### Note
Roblox exposes NO programmable GPU shaders (no GLSL/HLSL, no compute, no custom RTX
ray tracing) — a script physically cannot run a GPU shader or use the RTX directly.
Every Roblox "shader," this one included, composes built-in Lighting + post-effect
instances + overlays. An RTX card makes Roblox's OWN renderer (Future lighting,
shadows) look great — set Graphics to Manual / Quality 10 to use it.

## [1.0.10] — 2026-06-23

### Fixed — indoor / window blow-out ("too overexposed, not buttery")
High-dynamic-range indoor scenes (a sunlit window, white walls) were flooding to
white with hard clipping. Two changes:
- **Auto-exposure is now asymmetric, like a real eye:** when the scene is too BRIGHT
  it pulls exposure down *harder and faster* (gain 1.1, half the time-constant) so
  highlights stop blowing out; when too dark it lifts gently. Still fed by the
  heavily-smoothed luminance, so no lurch. Max brightening cap lowered (0.5→0.3).
- **Bloom tamed so only genuinely bright things glow:** intensity 0.45→0.3, threshold
  1.2→1.5, exposure-coupling 0.2→0.1. Daylit white walls no longer flood-bloom; neon
  and the sun still do. Realistic+ and Cinematic presets aligned.

## [1.0.9] — 2026-06-23

### Fixed — frame consistency during fast spins / driving
The stutter wasn't sustained low FPS — it was **bursty work spiking single frames**:
- **World scanner** classified up to 120 parts in one frame; while driving with
  streaming on, a freshly-loaded chunk spiked a frame. Default budget lowered
  120→70, and it now classifies far fewer parts on any frame that already ran long
  (frame-pacing guard) so the work spreads instead of stacking.
- **Streetlight beam rigs** were instantiated as you swept past lamps (a 360 spin
  past a row of them stacked the cost). Creation budget halved (4→2) and new rigs
  are only built on healthy frames — existing ones still just toggle (cheap).

### Changed — more photographic
- Grade saturation pulled back (0.1→0.07; Realistic+ 0.12→0.08) — real life is less
  saturated than Roblox's punchy default, so this reads more natural.
- Realistic+ reflection ray budget trimmed (80→56) for headroom; temporal
  accumulation keeps the reflection quality.

## [1.0.8] — 2026-06-23

### Fixed — exposure no longer lurches when the camera moves
The auto-exposure fed its raw per-sample luminance straight in with a high gain, so
panning the camera across a bright streetlight or the sky made the whole scene
brightness snap. Now the MEASURED luminance is low-passed hard (tau ~1.6 s) BEFORE it
touches exposure, the gain is cut (1.4→0.6), and the output tau is slower
(eye_adapt_speed 1.2→2.0). Exposure now drifts gently like a real eye instead of
lurching — stable as you look around.

### Added — Realistic+ preset
The refined "best looking" grade: deep contrast, AO-like shadow depth (low ambient
fill), tight crisp shadows (ShadowSoftness 0.12), strong albedo-aware reflections,
gentle bloom on true lights only, and the new rock-stable slow exposure. Foliage wind
stays off so geometry is never touched. First in the Presets dropdown.

## [1.0.7] — 2026-06-23

### Changed — default look is now Sharp + Realistic
Retuned the default grade (and the matching Cinematic preset) toward deeper contrast,
tighter shadows, and stronger reflections — grounded, not oversaturated:
- **Contrast:** tonemap 0.14→0.2, grade 0.08→0.14, `EnvironmentDiffuseScale` 0.8→0.7
  (less ambient fill → deeper, punchier shadows).
- **Shadows:** `ShadowSoftness` 0.3→0.15 for tight, crisp shadow edges (Future).
- **Reflections:** `EnvironmentSpecularScale` 1.3→1.5, floor reflectance 0.55→0.65,
  Fresnel 0.7→0.8, global reflectance bias 0→0.03 — stronger, still albedo-aware so
  dark surfaces stay dark.
- **Sharper air:** atmosphere density 0.18→0.15, haze 0.5→0.35, bloom 0.5→0.45 (only
  genuinely bright highlights bloom). Grain 0.06.

## [1.0.6] — 2026-06-23

### Fixed — CRITICAL: world geometry was being deformed
The foliage wind-sway (`enhancers/Foliage`) rotated game parts via `CFrame` every
frame. Because the Scanner tags anything Grass-material or named "tree/plant/grass"
as foliage, **collidable road / ground / building parts got caught and rotated** —
turning flat floors into potholes/ramps (you couldn't walk or drive), displacing
structures, and making parts look "gone." The suite must NEVER move world geometry.
Now foliage sway:
- only ever touches a part that is **NOT CanCollide** (pure decoration — collision
  geometry is never moved) **and** small (≤10 studs — structures are never small),
- restores every part to its captured original CFrame the instant you toggle it off,
  and on unload (via Snapshot),
- is **off by default** (you opt in). An audit confirmed no other module moves,
  resizes, destroys, or reparents any game part — Foliage was the only offender.

If a world is already deformed from an earlier version: **rejoin** (or unload the
suite) to restore originals, then load v1.0.6.

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
