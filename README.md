# 🎬 Cinematic Graphics Suite

A modular, client-side **visual-enhancement suite for Roblox** that pushes the
engine's built-in rendering stack as far as it will physically go — filmic
ACES-approximation tonemapping, realistic Future lighting, glossy/wet reflective
floors with budgeted real-time raycast reflection probes, deep atmosphere &
weather, and a cinematic camera with a photo mode — all driven by one central
config and a searchable [Rayfield](https://docs.sirius.menu/rayfield) UI.

> **It is a *composition* of Roblox's built-in stack, not a GPU shader.** Roblox
> exposes no programmable shaders. Everything here is honest about what it really
> is — see [Engine honesty](#-engine-honesty-read-this).

---

## 🚀 Quick start

Paste this one line into your executor (pinned to a release tag):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/EcoTopWoods/cinematic-shader/v1.0.0/dist/loader.lua"))()
```

> Replace `EcoTopWoods` and the `v1.0.0` tag with your fork/release. The
> loader fetches the manifest, warm-fetches every module in parallel, and boots —
> with retries, **CDN mirror fallback** (raw.githubusercontent → jsDelivr →
> Statically) and an optional disk cache. If anything fails to load it aborts
> cleanly with a notification and **no half-applied state**.

Prefer a single self-contained file (offline / deterministic)? Use the bundle:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/EcoTopWoods/cinematic-shader/v1.0.0/dist/cinematic.lua"))()
```

Press **Right Shift** (configurable) to toggle the control panel.

---

## ✨ Features

| Domain | What it does |
| --- | --- |
| **Lighting** | `Technology = Future` (capability-gated), `LightingStyle = Realistic` + `PrioritizeLightingQuality` when present, `ShadowSoftness`, ambient/outdoor-ambient, `ExposureCompensation`, brightness, ClockTime + geographic latitude, GI feel via `EnvironmentDiffuse/SpecularScale`. |
| **Tonemap (ACES approx.)** | A dedicated `ColorCorrectionEffect` tuned for a filmic toe/shoulder response, applied **before** the creative grade. There is no ACES node in Roblox — this is an approximation. |
| **Bloom (HDR-style)** | `BloomEffect` whose threshold **couples to live auto-exposure**, so blooming tracks perceived brightness. |
| **Eye adaptation** | Estimates scene luminance and eases `ExposureCompensation` toward a target with frame-rate-independent smoothing (slow tau). |
| **Creative grade** | A second `ColorCorrectionEffect` — graded blacks, warm tint, controlled saturation. |
| **Depth of field** | `DepthOfFieldEffect` with an auto-focus that raycasts what the camera looks at and pulls focus smoothly. |
| **Faked overlays** | Vignette, film grain, anti-banding dither, chromatic aberration, letterbox, motion blur — all GUI / `EditableImage` overlays (the engine has none of these as effects). |
| **Reflections** | PBR-aware Fresnel-driven glossy/wet floors (real environment reflection via `Reflectance` + `EnvironmentSpecularScale` under Future) **plus** an honest SSR *approximation* using roving `workspace:Raycast` probes — budgeted, temporally smoothed, camera-reprojected — with a cheap color-blend tier and an optional high-tier viewport hero mirror. |
| **Atmosphere / Sky / Clouds** | `Atmosphere` (Density/Offset/Color/Decay/Glare/Haze), curated `Sky` presets, and `Clouds` under `workspace.Terrain`. |
| **Weather + mood** | Smooth rain / snow / storm / lightning state machine with wet-surface coupling; named moods (Golden Hour, Blue Hour, Noon, Night, Overcast) and a day/night cycle. |
| **Cinematic camera** | Dynamic FOV kick, auto-focus DoF, faked motion blur, Perlin + impulse shake, **freecam** (WASD/gamepad), and a non-seizing **photo mode** with rule-of-thirds + level-horizon aids. |
| **Materials / PBR** | Material → roughness/metalness/F0 classification, global reflectance/roughness bias, optional author-flagged `SurfaceAppearance` (`ColorMap`/`NormalMap`/`MetalnessMap`/`RoughnessMap`). |
| **Enhancers** | Foliage wind, fire light, layered smoke, water polish, ambient dust, light flicker, and faked god-ray `Beam`s — all budget-aware, **zero per-frame sequence allocation**. |
| **Performance** | Startup micro-benchmark → initial tier, closed-loop adaptive quality with hysteresis, toggleable PerfHUD; graceful mobile degradation. |

---

## 🖼 Screenshots

_Placeholders — drop your own captures in `docs/` and update these links._

| Default cinematic grade | Wet floors + reflections | Storm + lightning | Photo mode |
| --- | --- | --- | --- |
| ![grade](docs/shot-grade.png) | ![floors](docs/shot-floors.png) | ![storm](docs/shot-storm.png) | ![photo](docs/shot-photo.png) |

---

## ⚙️ Settings overview

Every setting lives in [`src/core/Config.lua`](src/core/Config.lua) as typed metadata
and is **auto-generated** into the UI — change one slider and the owning module
updates live (no reload). Tabs mirror the feature groups:

- **General** — master enable, global quality, UI toggle key, notifications, log level.
- **Lighting** — core lighting, tonemap (ACES/Filmic/Reinhard/Neutral), eye adaptation, bloom, creative grade.
- **Reflections** — floor strength / wetness / Fresnel / glass overlay / tag; probe method, rays-per-frame, temporal frames, smoothing, reprojection, multi-bounce, buffer size.
- **Atmosphere & Weather** — atmosphere, sky preset, clouds, weather + intensity/wind/lightning/wet-boost, mood + day-night cycle, scene enhancers.
- **Camera & Cinematic** — base/kick FOV, auto DoF + aperture + focus speed, motion blur, shake, and the faked cinematic overlays.
- **Materials** — PBR pass, roughness/reflectance bias, metal reflectance, SurfaceAppearance.
- **Performance** — adaptive quality, target FPS, quality floor, PerfHUD, scanner budget.
- **Presets** — apply a look, plus JSON import/export.
- **About** — version, load source, last error, and the Unload button.

### Presets
`Cinematic` · `Realistic` · `Vibrant` · `Dreamy` · `Noir` · `Horror` · `Potato`.
Presets are **partial overlays** — they set only the keys they name, so they compose
with your own tuning. Author your own in [`src/presets/Presets.lua`](src/presets/Presets.lua)
or via JSON import.

### Config import / export
The **Presets** tab exports your full configuration as a schema-versioned JSON string
(copy/paste is the primary portable path; `writefile` is an executor convenience) and
imports it back, all `pcall`-guarded. Programmatically:

```lua
local suite = getgenv().__CINEMATIC_SHADER       -- or _G.__CINEMATIC_SHADER
local json  = suite.exportConfig()
suite.importConfig(json)
```

---

## 🧩 Programmatic API

The suite publishes a global handle (`getgenv().__CINEMATIC_SHADER` on executors,
else `_G.__CINEMATIC_SHADER`):

```lua
local suite = getgenv().__CINEMATIC_SHADER
suite.get("lighting_brightness")        -- read a setting
suite.set("lighting_brightness", 3.0)   -- write a setting (validated/clamped)
suite.applyPreset("Noir")               -- switch the whole look
suite.toggleUI()                        -- show/hide the panel
suite.setQuality(0.6)                   -- 0..1 global quality
suite.reBenchmark()                     -- re-tier performance
suite.exportConfig() / suite.importConfig(json)
suite.kill()                            -- full restore + unmount + global clear
```

Loading the suite a second time **surfaces the existing instance** instead of
stacking a second pipeline (double-load guard).

---

## 📦 Distribution model

Three consumption modes from one source tree:

1. **Network loader** — `dist/loader.lua`, the only file users paste. Pinned to a tag,
   fetches the manifest then lazily/eagerly fetches each module with retries + mirror
   fallback + optional disk cache.
2. **Single-file bundle** — `dist/cinematic.lua`, generated by `build/bundle.lua`
   (wraps every `src` file as `__modules["name"] = (function() … end)()`, inlines the
   require-shim, ends with `return __require("init")`). Offline & deterministic.
3. **Rojo project** — `default.project.json` maps `src/` → `ReplicatedStorage.CinematicShader`
   as ModuleScripts for Studio development.

Rebuild the bundle after editing `src/`:

```sh
lua build/bundle.lua      # writes dist/cinematic.lua and syncs dist/loader.lua constants
```

CI ([`.github/workflows/release.yml`](.github/workflows/release.yml)) regenerates the
bundle on push and publishes a GitHub Release on a `v*` tag.

### Studio (Rojo) note
Because modules are dependency-injected factories (`return function(require) … end`),
running under Rojo needs a tiny bootstrap `LocalScript` that builds a shim mapping
logical names to the ModuleScripts under `ReplicatedStorage.CinematicShader` and calls
`require(init)(shim)`. For most users the network loader or the bundle is simpler.

---

## 🔬 Architecture

```
src/
├── manifest.lua      module registry + boot order
├── init.lua          entry: double-load guard, builds ctx, boots controllers
├── core/             Config, State, Signal, Maid, Snapshot, Util, Logger, Platform
├── detection/        Scanner (streaming-aware, budgeted part classifier)
├── materials/        PBR (material → roughness/F0 + reflectance pass)
├── lighting/         Lighting, Tonemap, Atmosphere, Sky (+ Clouds)
├── postfx/           Pipeline, Bloom, DepthOfField, ColorGrade, Vignette, FilmGrain, Dither
├── reflections/      Reflections (strategy), OverlayReflection, RaycastProbe, ViewportMirror
├── weather/          Weather, Rain, Snow, Storm, Lightning
├── timeofday/        Mood
├── camera/           CameraFX, FOV, DoFAuto, MotionBlur, EyeAdaptation, Shake, Freecam, PhotoMode
├── enhancers/        Enhancers, Foliage, Fire, Smoke, Water, Particles, Lights, Beams
├── perf/             AdaptiveQuality, Benchmark, PerfHUD
├── presets/          Presets, Serializer, ConfigStore
├── ui/               UI, Schema, Controls, Notify, FallbackUI
└── api/              API, Teardown
```

Every module is a factory taking the injected `require`. Controllers own a child
**Maid** (every connection/instance/thread tracked, cleaned in reverse) and mutate
foreign state only through **Snapshot** (capture-once → exact restore; created
instances tagged `__cinematic=true` and destroyed on unload). Result: **zero residue**
on `kill()`.

---

## 🧪 Engine honesty (read this)

This suite never claims capabilities Roblox doesn't have:

- **No GPU shaders.** "Shader" = composing `Lighting` + the five real post-effects
  (`BloomEffect`, `BlurEffect`, `ColorCorrectionEffect`, `DepthOfFieldEffect`,
  `SunRaysEffect`) + `Atmosphere`/`Sky`/`Clouds` + materials + `EditableImage` +
  `Beam`/`ParticleEmitter`.
- **Tonemap is an approximation** of an ACES/filmic response via a tuned CCE +
  `ExposureCompensation`, not a real operator.
- **Reflections** are real environment-mapped reflection (`Reflectance` +
  `EnvironmentSpecularScale` under Future, plus Glass) **plus** an SSR *approximation*
  from roving raycasts. There is **no** true SSR / ray tracing on arbitrary parts; the
  raycast probes are temporally accumulated and honestly framed as an estimate.
- **Vignette / grain / dither / chromatic aberration / letterbox / motion blur** are
  **faked** GUI / `EditableImage` overlays. None of them anti-alias the 3D scene.
- **EditableImage** requires an ID-verified 13+ creator in published experiences — it
  is feature-detected and degrades gracefully when unavailable.
- **Client-side only.** No server access. `loadstring`/`HttpGet`/`writefile`/
  `setclipboard`/`gethui` are executor-injected and every one is capability-checked +
  `pcall`-guarded. The suite respects your graphics quality; Future lighting/clouds/
  shadows silently degrade on low-end and mobile.

---

## 🎮 Supported environments

- **Executors** with `loadstring` + `HttpGet` (most mainstream injectors). `writefile`/
  `setclipboard`/`gethui` are used opportunistically and degrade when absent.
- **Roblox Studio** (Future lighting, EditableImage typically available) via Rojo or the bundle.
- **Mobile / low-end**: heavy paths (viewport mirror, multi-bounce, motion blur) default
  off via the same config keys; overlay reflections + adaptive quality keep it smooth.

---

## ⚠️ Disclaimer

This is a **client-side visual tool**. It only changes how the game looks *on your own
screen* — it does not modify the server, other players' views, or game logic, and it
grants no gameplay advantage. Use it where third-party scripts are permitted. You are
responsible for complying with the rules of any experience you run it in. Provided
**as-is** under the [MIT License](LICENSE), with no warranty.
