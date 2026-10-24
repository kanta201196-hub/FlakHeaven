# Combat VFX on the GPU (VFX-01…06) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** replace the CPU particle explosions with a GPU effect system and add the missing effects (smoke lighting, missile trails, muzzle flash, impacts, water splashes and ripples, decal craters), Forward+ only, Compatibility keeps the old path.

**Architecture:** `Boom3D` public API forwards to `GpuFx` when Forward+ is active; `GpuFx` owns `FxLayer`s (one `GPUParticles3D` each, particles via `emit_particle`), `FxDecals`, a light pool and the recipes; numbers in `balance/vfx.gd`; flipbooks baked in Blender by `game/tools/vfx_bake/`.

**Tech Stack:** Godot 4.4.1 Forward+, GDScript, GPUParticles3D + ParticleProcessMaterial / particle shaders, Decal, Blender (Mantaflow) for bakes, Python + Pillow for atlases.

**Spec:** [../specs/2026-10-24-combat-vfx-design.md](../specs/2026-10-24-combat-vfx-design.md)

Status: **planned 2026-10-24**. Executor: thread «Улучшить эффекты боя». One branch and PR per step (VFX-01…06), merged in order. Probe code from branch `claude/project-thread-4jgjai` (`--vfx2`) is reference only and is not merged.

## Global Constraints

- No gameplay number changes: damage, radii, timings, explosion screen size (S10-11 `BOOM_K`, `SMOKE_K` kept as the size reference).
- Compatibility path must keep working unchanged (`tools/ci/smoke.sh` headless and Compatibility screenshots).
- Environment values (glow, tonemap, exposure) are sent to the thread «3D-модели по плану Kirill» before the change and live in one block in `render3d.gd` behind the renderer check.
- Assets: own bakes or CC0 only; license note next to every third-party file; ASCII file names; no `.blend` or raw bake output in git (sources go to `/mnt/project-files/vfx_src/`).
- `##` docstring on every new class and public function; English identifiers and comments.
- Every step ends with a close-up zoomable gallery to Kanta (rule 24.10) and fps from Kanta's PC via Remote Control before merge.
- fps is never judged from the cloud (lavapipe is CPU rendering).

## Review Focus

1. `emit_particle` behaviour: emitter `emitting`/`amount_ratio` setup so only code-emitted particles appear; ring-buffer recycling under the 30-explosion stress.
2. No double effects: when GpuFx is active, `Boom3D` CPU code must not also run.
3. Render order and transparency sorting of fire, smoke and dust against clouds and planes.
4. Decal and light pools at the cap: oldest recycled, no node churn per frame.
5. Quality presets 0–3 actually scale cost.

## Tasks

### Task 0 — Environment and baseline
- [ ] Godot 4.4.1 into `/usr/local/bin/godot`; `apt-get install -y mesa-vulkan-drivers` for Forward+ renders (`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --rendering-method forward_plus …`).
- [ ] `tools/ci/unit.sh`, `tools/ci/smoke.sh fighter` green on `main`.
- [ ] fps baseline on Kanta's PC (Remote Control): boom bench `--boomonly=stress,battle` and one 5-minute autotest sortie, Compatibility and Forward+; save the numbers to `docs/playtest/vfx-perf.md`.

### Task 1 — VFX-01 Foundation: GpuFx, layers, routing (TDD for helpers)
Files: new `game/scripts/vfx/gpu_fx.gd`, `game/scripts/vfx/fx_layer.gd`, `game/scripts/vfx/fx_math.gd` (pure helpers), `game/scripts/balance/vfx.gd`, `game/tests/vfx_test.gd`; changed `boom3d.gd` (routing), `render3d.gd` (glow behind renderer check), `tools/ci/smoke.sh` (`SMOKE_RENDER=forward_plus` runs under xvfb + lavapipe).
- [ ] Spike: one `GPUParticles3D`, `emit_particle` with `emitting=false` vs `true` + `amount_ratio=0`; confirm on a lavapipe frame which setup shows only code-emitted particles. Record the answer in `fx_layer.gd` docstring.
- [ ] Write failing tests in `vfx_test.gd`: `FxMath.flip_uv(frame, cols, rows)`, `FxMath.frame_at(age01, frames)`, `FxMath.layer_amount(base, gfx)` (0.45/0.7/1.0/1.25 as today's `_q`), `FxMath.kind_for(size, air)` (same rules as `Boom3D.spawn`: ground, flak < 18, big ≥ 50, else air).
- [ ] Implement `FxMath`; `tools/ci/unit.sh` green.
- [ ] `FxLayer`: fixed amount, process material (gravity/buoyancy, damping, wind, scale curve, colour ramp), draw pass quad with billboard flipbook material and proximity fade (soft particles); `emit(...)` packs lifetime and start frame into `custom`.
- [ ] `GpuFx`: layers fire, smoke, dust, spark, flash, shock; recipes `air`, `flak`, `big`, `ground`, `blast`, `plasma` mirroring today's `Boom3D` layer mix, numbers in `balance/vfx.gd`. Temporary fire sheet: Unity Labs CC0 `Explosion01` (license file).
- [ ] Routing: `Boom3D.spawn`, `launch`, `ground_launch`, `smoke_screen`, `black_smoke`, `emp`, `sonic` call `GpuFx` when `GpuFx.active()`; `--oldfx` forces the CPU path for comparisons.
- [ ] Glow in Environment (values agreed with the 3D thread first).
- [ ] Boom bench `--boomonly=air,ground,blast,battle,stress` with `--zoom=4`: Compatibility, Forward+ old path (`--oldfx`), Forward+ GpuFx; gallery to Kanta.
- [ ] Checks: unit, `smoke.sh all` (Compatibility) and `SMOKE_RENDER=forward_plus smoke.sh fighter`, `full.sh` once; fps on Kanta's PC vs baseline. PR, merge after checks and Kanta's look.

Status 2026-10-24 (PR #351): VFX-01 was done as a parity-first port. Boom3D keeps its recipes and draw shaders, and the GPU layers (`FxLayer` particle shader) reproduce `Boom3D._tick`/`_write`, so the change can be compared frame to frame with `--oldfx`. Tested helpers: `FxMath.kind_for`, `FxMath.quality`, `FxCounter`. Moved to VFX-02: `FxMath.flip_uv`/`frame_at`/`layer_amount` tests, `balance/vfx.gd`, flipbook draw material with proximity fade (the temporary CC0 sheet is skipped, own bakes go straight in). Debris, burning spots and lights stay on the CPU until VFX-06.

### Task 2 — VFX-02 Own flipbooks (bake pipeline)
Files: new `game/tools/vfx_bake/` (`bake_fire.py`, `bake_smoke.py` for Blender `--background --python`, `pack_atlas.py`), `game/assets/vfx/*.png` + `.import` (VRAM compressed).
- [ ] Blender bake scenes: fireball with soot, dark smoke puff, dust burst in Нагорье colour (`Boom3D.DUST`/`DUST_D`), plasma burst (blue-white), small flak burst; orthographic camera at 28° tilt, transparent background, 64 frames.
- [ ] Lighting pass for smoke and dust (normal map or 6-way) so the shader lights them from the scene sun.
- [ ] `pack_atlas.py`: frames → 8×8 atlas 4096² (2048² for small effects), straight alpha, sRGB colour, linear lighting.
- [ ] Replace the placeholder sheet; smoke shader uses the lighting pass and `Render3D.sun` direction.
- [ ] Gallery (close-up, zoomable), checks, PR.

### Task 3 — VFX-03 Smoke and trails
- [ ] Missile and rocket smoke as GPU ribbon trails (`RibbonTrailMesh`, `trail_enabled`) for player and enemy missiles (replace puff chains in `projectiles.gd` / `render3d.gd` when GpuFx active).
- [ ] Burning targets and damaged engines: rising smoke column from `_emit` equivalents on the GPU; black smoke of damaged planes (`black_smoke`).
- [ ] Smoke screen of the convoy (`smoke_screen`) with the new lit smoke.
- [ ] Gallery, checks, PR.

### Task 4 — VFX-04 Gunfire
- [ ] Muzzle flash flipbook at player guns (`player_guns.gd` muzzle point) and enemy guns/AA, 2–3 frames, plus a tiny light on heavy guns.
- [ ] Tracers: HDR core so glow picks them up (enemy `_eglow_mm`, player tracers).
- [ ] Hit sparks on planes and armour (`Fx.hit_spark` → GpuFx spark burst), dust kick-ups on ground hits.
- [ ] Gallery, checks, PR.

### Task 5 — VFX-05 Water
- [ ] Splash flipbook (column of water and spray) when a bullet line, bomb, debris or crash lands where `Render3D._on_water()` is true.
- [ ] Ripple rings on the river: MultiMesh of rings on the water plane, ring shader with foam noise, lifetime 2–3 s.
- [ ] Gallery, checks, PR.

### Task 6 — VFX-06 Marks of battle and light
- [ ] `FxDecals`: decal pool (cap by quality preset) for craters, scorch and bullet marks that follow slopes; replaces crater sprites under Forward+ (`render3d.gd` crater code stays for Compatibility).
- [ ] Light pool to 16 omni lights with short flashes; burning spots flicker.
- [ ] Heightfield collision (`GPUParticlesCollisionHeightField3D`, follow camera) for sparks and debris; debris mesh layer with shadows.
- [ ] Final fps on Kanta's PC (stress, battle, 5-minute sortie) vs baseline in `docs/playtest/vfx-perf.md`; gallery; PR.
