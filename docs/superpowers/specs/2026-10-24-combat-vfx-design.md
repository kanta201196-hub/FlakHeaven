# Combat VFX on the GPU (VFX-01…06) — design

Status: **approved by Kanta 2026-10-24** (variant 2 of the proposal, thread «Улучшить эффекты боя»).
Proposal with frames: https://claude.ai/artifact/VsvviH2N2ENoPJso6ZKEtL · close-up gallery: https://claude.ai/artifact/EVJupPRcU1FrN8hf7peqy7.

## Goal

Kanta's priority 4 (24.10): quality of explosions, smoke, gunfire and water effects in the first biome (Нагорье). Size budget is large (game ~400 MB, genre norm 5–10 GB), so pre-rendered high-resolution textures are fine.

## What is wrong today (measured on the boom bench, 24.10)

- `Boom3D` simulates every particle on the CPU (~5 ms in heavy fights) and draws procedural noise puffs: fire reads as a brown blob, smoke has no volume or sun lighting.
- With Forward+ and no other change, dark smoke turns near-white (unshaded effect colours are tuned for Compatibility).
- From the combat camera an explosion is 40–100 px. Kanta asked for smaller explosions in s10 (S10-11, `BOOM_K`, `SMOKE_K`). Quality must come from detail, brightness and light, not size.
- No muzzle flash in 3D, no impact dust, no water splash or ripples on the river, craters are flat sprites that ignore slopes.

## Decision

A new GPU effect system, `GpuFx`, built on `GPUParticles3D` with particles emitted from code (`emit_particle`, Forward+/Mobile only), pre-rendered flipbooks baked top-down, decals and a larger light pool. The current `Boom3D` stays as the fallback for Compatibility and as the reference until the last step.

Rejected: variant 1 (flipbooks on the CPU system — keeps the CPU cost, no trails, collisions, decals); variant 3 (volumetric — GPU cost, invisible gain at our camera height).

## Architecture

- `Boom3D` stays the only entry point for gameplay code (`Fx.explosion`, `Fx.blast`, `launch`, `smoke_screen`, `emp`, `sonic`, `black_smoke`). Each public method forwards to `GpuFx.I` when `GpuFx.active()`, else runs the current CPU code. Callers do not change.
- `GpuFx.active()` = Forward+ renderer (`RenderingServer.get_current_rendering_method() == "forward_plus"`) and `Tuning.g("fx3d") > 0.5` and no `--nofx`/`--oldfx`. Switching the project renderer (project.godot) belongs to the thread «3D-модели по плану Kirill»; until then GpuFx is tested with `--rendering-method forward_plus`.
- `game/scripts/vfx/gpu_fx.gd` (`class_name GpuFx`, Node3D under `Render3D`): owns one emitter per layer and the recipes (which layers each explosion kind emits, with sizes, lifetimes, colours). Recipes read numbers from `game/scripts/balance/vfx.gd` (ADR-04: numbers out of logic).
- `game/scripts/vfx/fx_layer.gd` (`class_name FxLayer`): one `GPUParticles3D` with a fixed `amount` (ring buffer, oldest particle recycled), its process material and draw material; `emit(pos, vel, size, life, color, frame0)`.
- Layers: `fire` (flipbook), `smoke` (lit flipbook), `dust` (lit flipbook, Нагорье colour), `spark` (velocity-aligned streak, heightfield collision, bounce), `debris` (mesh, collision, shadow), `flash` (additive disc), `shock` (sphere shell), `splash` (water flipbook), `muzzle` (flipbook, 2–3 frames).
- Ribbon trails: missile smoke as `GPUParticles3D` trails (`RibbonTrailMesh`) instead of chains of puffs.
- `GPUParticlesCollisionHeightField3D` following the camera, so sparks and debris land and bounce on the relief.
- `game/scripts/vfx/fx_decals.gd`: pool of `Decal` nodes for craters, scorch and bullet marks, oldest recycled; replaces flat crater sprites under Forward+.
- Light pool: 16 `OmniLight3D` (Forward+ clusters lights; Compatibility limit of 8 per mesh no longer applies), short flashes that light the relief and nearby planes.
- Water: `splash` layer plus expanding ripple rings (one MultiMesh of rings on the water plane, shader-driven) wherever `Render3D._on_water()` is true: bullets, bombs, debris, crashes.
- Glow: Environment glow for HDR fire and flashes. Environment values are agreed with the 3D thread first and live in one place in `render3d.gd`, behind the renderer check, so Compatibility keeps today's look.

## Flipbooks

- Baked by us in Blender (Mantaflow smoke/fire), orthographic camera from above at the combat tilt (`cam_tilt` 28°), rendered to frames and packed into atlases by a script in `game/tools/vfx_bake/`. Channels: colour+alpha, plus a lighting pass (normals or 6-way light) for smoke and dust so the sun direction matches the scene.
- Sources allowed: own bakes, CC0 packs (Unity Labs VFX, JangaFX free VDBs). No paid tools (EmberGen) without Kanta's yes.
- Resolution 2K–4K per atlas, VRAM-compressed (BPTC/ASTC via import); total budget ~150–400 MB on disk (estimate).
- The Unity Labs CC0 `Explosion01` sheet is a temporary placeholder in step 1 only.

## Performance

- CPU: target ≤ 1 ms for effects in the 30-explosion stress scene (today ~5 ms).
- GPU and fps: measured only on Kanta's PC via Remote Control, boom bench `--boomonly=stress` and one real sortie log, before step 1 and after each step. Target: fps in the stress scene not lower than today.
- Quality presets (`Settings.gfx` 0–3) scale layer amounts, atlas resolution and decal/light counts.

## What does not change

Damage, blast radii, timings and every gameplay number. Explosion screen size stays as decided in S10-11. Compatibility path keeps working (old `Boom3D`).

## Review

Each step ends with a close-up zoomable gallery (rule 24.10: every frame opens full screen with zoom, variants switch on the same spot) sent to Kanta before merge, and fps numbers from Kanta's PC.

## Tests

- Unit (`game/tests/vfx_test.gd`): pure helpers — flipbook frame/UV math, ring-buffer slot reuse, quality scaling of layer amounts, explosion kind selection by size (`Boom3D` rules), decal pool recycling.
- Visual: boom bench in Forward+ on lavapipe in the cloud (`docs` memory: cloud Forward+ renders) for frames; `tools/ci/smoke.sh` in both renderers; `tools/ci/full.sh` once before each PR is ready (combat code).
