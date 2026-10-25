# Fortified area («Укрепрайон») — implementation plan

Spec: `docs/superpowers/specs/2026-10-25-fortified-area-design.md` (Kanta «да» 2026-10-25, cap 4 missiles).
Backlog: FA-01…FA-04. Thread «Сделать активность «Укрепрайон» из крепости».
Preview scene (three.js, the look to match): `/mnt/project-files/visual/fort_rework/hq/hq_scene.html`.

## Facts the plan relies on (checked in code 2026-10-25)

- Map forts are `Background.chunk_object(cx, cy)` entries `{"name": "o_fort", "pos", "size" (≈760 ±15 %), "rot", "var"}`.
  Render3D draws them with `AdobeBuild.fort()` (unit mesh) scaled by `size`, basis `Basis(UP, -rot)`,
  so a unit-mesh point `(x, z)` sits at world `pos + Vector2(x, z).rotated(rot) * size`.
- Unit mesh: wall line `half = 0.42`, towers at `±(0.42 − 0.17·0.4) = ±0.352`, tower height `0.17`, gate in +z.
- `AASite` + `GroundTarget` already give: alarm radius, timer, `site.active`, SAM lock → launch, `launcher_up()`,
  `launches`, `launch_at`, and the 3D launcher animation in `render3d._sam_launcher`.
- `GroundTarget.mobile()` decides driving; `kind()` is the missile's `who` string.
- Rewards: `Rewards.ACTIVITY[kind]` + `Events.activity_succeeded(kind)` → `Main._on_activity_succeeded`.
- Player-facing text: `Loc.t()` / msgid = Russian text, `locale/en.po`, `locale/zh_CN.po`.

## PR 1 — activity logic (FA-01), no new art

Uses today's fort mesh and the normal SAM truck model parked on the tower tops; enough to play it.

1. **Pure placement and cap, TDD** — `game/scripts/fort_area.gd` (`class_name FortArea extends AASite`):
   - `static func pick_fort(objs: Array, want: Vector2, reach: float) -> Dictionary` — nearest `o_fort` to `want`
     within `reach`; `{}` if none. Test: none, one out of reach, nearest of two.
   - `static func tower_points(fort: Dictionary) -> PackedVector2Array` — the 4 tower tops in world px from
     `pos`, `size`, `rot` (unit point ±0.352). Test: rot 0 and rot PI/2 against hand-computed points.
   - `static func yard_points(fort) -> PackedVector2Array` — 2 jeep spots inside the walls, clear of the citadel.
   - `static func can_lock(in_air: int, locking: int, cap: int) -> bool` — `in_air + locking < cap`. Test cap 4.
   - Tests: `game/tests/fort_area_test.gd`, run by `tools/ci/unit.sh`.
2. **Balance file** `game/scripts/balance/fort_area.gd`: `MISSILE_CAP := 4` (Kanta), `ACTIVATE_R := 1150.0`,
   `LIMIT := 90.0` (*guess*), `REACH := 6000.0` (measured, 94 % find rate), `AHEAD := 1700.0`, jeep count 2.
3. **GroundTarget**: `fixed := false` flag — `mobile()` returns false when fixed; SAM lock asks
   `site.can_launch()` (AASite: always true; FortArea: the cap); `kind()` returns `"укрепрайон"` for fort
   pieces so the fort can count its own missiles in `Projectiles.missiles`.
   Jeeps: variant `"jeep"` on `GroundTarget` (gun bursts like the convoy technical, `fixed`, model
   `e_convoy_technical`), because `ConvoyVehicle` is bound to a `Convoy` and a road.
4. **FortArea node**: `setup(fort, hp_k, dps)` — 4 fixed `sam` launchers at `tower_points`, 2 jeeps at
   `yard_points`; no bunker. Done when the 4 launchers are down (jeeps optional). Alarm banner
   «Обнаружена база противника» (+ timer text), fail banner, sound `aa_alert`. Same cleanup distance as AASite.
5. **Spawner**: `ACTIVITIES` gains `"fort"`; Highland only (`not Biome.sea()`); no fort within `REACH`
   of the point `AHEAD` px along the heading → skip to the next kind this round. Recon banner, `Story.say`,
   `Hints.show("act_fort", …)`.
6. **Rewards**: `&"fort"` — like `&"ground"`, parts ×1.5 (60 / 90), `reason` «ЗА УКРЕПРАЙОН»;
   `Main.ACTIVITY_TITLE` entry; all strings into `en.po` / `zh_CN.po`.
7. **Render (minimal)**: launchers of a `fixed` SAM drawn at tower-top height; the truck body hidden,
   only the `launcher_yaw` subtree shown. Touches `render3d.gd` → message thread «Ускорить большие бои» first
   with the exact functions (`_sam_launcher`, the ground-target model setup).
8. Checks: `unit.sh`, `smoke.sh all`, `full.sh` (combat code), autotest forcing the fort activity.

## PR 2 — fort model, set Г (FA-02)

Procedural in Godot (`game/scripts/fort_build.gd`, like `AdobeBuild`), ported from the preview scene, so the
same code builds intact and broken pieces at load time; no Blender round trip.

1. Textures: Poly Haven CC0 1k–2k jpg (plaster_stone_wall_01, old_stone_wall, brown_brick_02,
   concrete_wall_008, old_planks_02) into `game/art/fort/`, rows in `game/art/LICENSES.md`.
2. Triplanar material with the preview's grime/bleach/streak terms (`game/shaders/fort.gdshader`, colours via
   `SRGB()`/`source_color`).
3. Pieces: 8 wall sections, 4 towers (shaft + crown + pad), gate, citadel/keep, rooms, store; each an
   `ArrayMesh`; budget 20–30k tris for the whole fort (*guess*). All map forts use the new model; quiet
   (no launchers, no props) when not the active activity.
4. Tower launchers: `launcher_yaw` subtree of `fh_battle_e_sam.glb` on a concrete pad + sandbag ring.
5. Frames on 3 presets (low/medium/high) next to each other for Kanta → «ок».

## PR 3 — conditional destructibility (FA-03)

1. Pure `FortDamage` (TDD): pieces with hidden HP pools; `apply_blast(local_pos, dmg, radius)` →
   pieces that changed state. Bullets ignored. Launcher HP 50 % / 0 drives the tower state.
2. Broken variants from `fort_build.gd`: jagged shaft with brick core, crumbling rim, snapped beams,
   stepped breach ends, sagging lintel, burnt leaves, rubble cones, decals (cracks, soot, pits).
3. State swap plays the existing dust/debris VFX and leaves scorch; fort stays broken for the sortie.
4. Frames on 3 presets: intact, mid-fight, taken.

## PR 4 — polish and frames (FA-04)

Burning store, burnt jeep/truck variants, smoke columns; final frames page for Kanta; play test notes.

## Open numbers (*guess*, tuned after the first play test)

Timer 90 s, reach 6000 px (measured), parts ×1.5, wall section pool (2 bomb hits).
