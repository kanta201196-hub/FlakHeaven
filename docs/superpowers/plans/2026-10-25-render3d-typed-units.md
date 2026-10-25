# Plan: render3d units as a typed class

Status: approved by Kanta 2026-10-25 (option «Б» in «Ускорить большие бои»). Work starts only after the
3D-models thread merges kanta/s11-turrets, kanta/s11-mech and kanta/s11-mounts, because those
branches may touch render3d.gd.

## Why
Cloud profile after #403, about 60 enemies, frame about 14.5 ms headless: `render3d` takes 5–5.5 ms.
Of that, `r3d.u.enemies` takes 2.3–2.8 ms, which is about 40 µs per enemy.

The split of that per-enemy time:
- air `_place`: about 1.3 ms. The shadow inside it is about 0.75 ms; the transform write itself is only 0.14 ms.
- `_relief_alt`: about 0.4 ms.
- `sprite_info` and `_ensure`: about 0.5 ms.
- overlay: about 0.1 ms.

Engine calls are a small share. Most of the cost is GDScript overhead: about 60 string-keyed
Dictionary lookups per unit (`u["node"]`, `u.get("bm")`, `u.has("sh")`, ...), Variant boxing,
and repeated `Tuning.g()` calls. Caching the shadow sliders alone gave no measurable gain, which
is why the change has to be structural and not spot fixes.

## What
1. Add `class_name Unit3D extends RefCounted` (game/scripts/unit3d.gd).
   - Typed fields for every key used in render3d.gd, plane_fx.gd, leviathan_parts.gd,
     title_flight.gd, visual_bench.gd and fortress.gd. Main fields: node, mi, kind, tex, k, bm,
     ph, bank, alt, alt_to, alt_next, sh, shb, sh_n, sh_b, sh_off, sh_y, sh_f, cs, cs_n, weapons, plus the parts fields.
   - Rare part data (Leviathan, convoy, tanker boom, mech, modp, detail) stays in one typed
     `parts: Dictionary` field, so the class does not grow by 30 fields used by one unit each.
2. `_units: Dictionary[int, Unit3D]`, and the pool holds Unit3D.
   - `_ensure` returns Unit3D.
   - The helpers take Unit3D: `_place`, `_place_shadow`, `_relief_alt`, `_turn_bank`, `PlaneFx.*`, `LeviathanParts.update`, and the parts helpers.
3. Per-frame constants are read once per frame and not once per unit: Tuning sliders, the sun
   direction, camera height and `unit_scale`.
4. Shadow slope basis is cached with its sample (every 4th frame), not rebuilt every frame.
5. `_relief_alt` returns its pair through fields (`u.alt`, `u.pitch`) instead of allocating an Array per call.

No visual or gameplay change. Same order of operations, same numbers.

## Checks
- `tools/ci/smoke.sh all` after each step. Steps 1–2 are one mechanical commit; 3–5 are separate commits.
- Perf: the same headless command as in the memory note, 2 runs before and 2 after, comparing
  `r3d.u.enemies` and `render3d` at t=200–300. Target: −1 ms or more on `render3d`.
- `--visual` screenshots (Compatibility, gfx 0/2/3) of a big fight, before and after, compared by eye.
- `tools/ci/full.sh` once before merge (render3d is combat visuals).
- Code review skill on the diff.

## Risks
- Large diff in a file other threads edit. Rebase right before the PR, and keep the mechanical
  commit separate so conflicts are easy to redo.
- Missed key → runtime error only on that unit type. Smoke runs all three classes; full.sh covers
  bosses, convoy and the tanker. Grep for `\["` on unit variables must come back empty at the end.
