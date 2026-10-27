# Plane decals and personal markings — design

Status: **approved by Kanta 2026-10-27** with the recommended options (unlocks: starter set + milestones; kill tally: aces and bosses; «Вершина» stays on both wings; the ace claw moves into the tally row; a personal fin badge may replace the class mark), plus **free placement** (Kanta 27.10 14:32: «можем ли мы дать возможность их свободного нанесения? В т.ч. с изменением размера, поворотом и прочее»). Request of 27.10: «также проработай систему наклеек/кастомизации — черепа там всякие, номера, нейтральные символы».
Branches: `claude/plane-decals` (PR1, merged as #477), `claude/decals-core2` (PR2). Related: liveries `game/scripts/livery.gd`, insignia `game/scripts/insignia.gd` (V-07, Kanta 17.10), medals `game/scripts/balance/medals.gd` (lifetime counters), game-context line 137 «Кастомизация … — косметика за достижения».

## 1. Goal

Let the player make their own «Оса», «Грач» and «Кит» recognisable: skulls and mascots, a side number, nose art and a kill tally, the way squadron pilots personalise aircraft, placed freely anywhere on the plane, while the world stays fictional and the planes realistic and matte. Pure cosmetics: no effect on combat, balance or progression numbers.

## 2. Rules every decal follows

1. **Decals lie on the skin.** Wherever the player puts one, it is cut out of the plane's own surface (§5), so it bends round the nose, sits flat on an intake or a nacelle and never floats or cuts through. The fixed spots of the first proposal (nose sides, fin, side number aft of the cockpit, tally under the canopy) stay as one-tap **presets** (§4).
2. **Fictional and neutral only** (CLAUDE.md hard rule 1): no stars, real roundels, flags, eagles, unit badges or politically loaded signs, no real aircraft names. Skulls are a generic «danger/ace» sign without unit context. Every new picture passes the review question «does it resemble any real national, unit or political sign?».
3. **Matte and weathered:** decals are paint — roughness 0.82–0.92, chips and fading (`wear`), never glossy.
4. **«Вершина» stays on both wings** (decision 17.10, confirmed 27.10): it tells «ours» from enemies. A decal may overlap it but never hides it. A decal laid over the fin badge or the side claw hides that badge (27.10: a personal fin badge may replace the class mark).
5. **Wingmen and enemies get no player decals.**

## 3. Pictures (atlas)

| Kind | Pictures | Paints |
| --- | --- | --- |
| Skulls | winged, on crossed wrenches, flaming | bone / accent / ink |
| Neutral symbols | lightning disc, ace of spades card, dice, geometric chevrons, smiling sun, mountain peaks with sun | primary / secondary / ink |
| Mascots | wasp («Оса»), rook («Грач»), whale («Кит»), black cat | primary / secondary / ink |
| Nose art | shark mouth (two cells wide), angry eye | teeth / mouth / ink |
| Side number | digits 0–9, 1–3 digits typed by the player | fill / — / outline |
| Kill tally | air mark (fictional delta drone), ground mark, bomb mark — repeated by the count | fill / accent / ink |

Drawn by code (`game/tools/decal_atlas.py`, Pillow, no downloads; digits in PT Sans Bold, OFL) into one mask atlas `art/decals/decal_atlas.png` (8×4 cells of 256 px): R/G/B are the weights of the primary, secondary and ink paints, A the coverage. Release set: ~24–30 pictures, a second number font (stencil). Paints: 12 matte paints (`DecalCatalog.PAINTS`: bone, white, sand, ochre, orange, rust, red, olive, teal, blue-grey, black, gunmetal) and a fixed ink. No free RGB picker: the palette keeps decals plausible and is gamepad-friendly.

## 4. Free placement and presets

- The player picks a picture and puts it **anywhere on the plane**: the cursor (mouse, or the gamepad stick moving a cursor across the screen) casts a ray at the plane's hull; where it hits, a live preview of the decal lies on the skin. Then the decal can be **scaled** (0.8 … 25 cm at plane length 1 m — `DecalRecord.SIZE_MIN/MAX`), **rotated** around the skin normal, **mirrored**, **recoloured** (primary, secondary) and **moved** (pick it up again). A number takes 1–3 digits.
- Decals may overlap; later ones draw over earlier ones (list order = draw order; «вперёд / назад» in the list).
- **Cap: 12 decals per plane** (`DecalLoadout.MAX_DECALS`), plane 1 and plane 2 separately (their shapes differ).
- **Presets** (`DecalPresets`) = the spots measured in the first proposal: «нос», «номер», «счёт побед», «киль» (each on either side) and «крыло» (top of either wing), per plane (`DecalPresets.SPOTS`). `DecalPresets.record(hull, plane, spot, side, picture)` shoots a ray at the hull and returns an ordinary record, so the player can still move it. On the right side the nose picture and the tally are mirrored, so they face forward on both sides; a number is never mirrored and starts as «01». The debug samples (`--decals`) are these presets.
- **Symmetry helper** (`DecalPresets.mirrored`, button in the UI PR): «на другой борт» adds the mirror copy: position and normal z → −z, angle → −angle (a reflection turns rotations the other way), mirror flag flipped (a number stays readable), then snapped onto the skin by a short ray (the two sides of a model are not exactly alike). Unit-tested: the copy's basis is the reflected basis, and mirroring twice gives the original.
- The kill tally is one record: a mark picture repeated by the count; the row grows from the decal's position along its right axis (mirror reverses it, so on the right side it also grows aft), 10 marks per row, at most 20. **Count = rival aces + «Крепости» downed by this class** (option A, decided 27.10): `Medals.run_counters` adds the sortie's aces and «Крепости» to the medal counter `tally_<class>` (lifetime, saved with the medals; starts at zero with this update; the demo build keeps no medal counters, so its tally stays empty). The ace claw becomes the first mark of the row in a later PR (needs a claw picture in the atlas).

## 5. Rendering: projected mesh, one draw per plane

Decision (unchanged in principle from the first proposal, now generalised to any position): **geometry cut from the hull + one atlas + one small shader.** Godot `Decal` nodes stay rejected (absent in GL Compatibility; project through thin fins and wings).

- **Hull** (`PlaneHull.of`, shared with `SkinPatch` since PR2 — one cache, the hangar model is read once): the model's body mesh in model axes — its textured surfaces (no glass, no wheel wells), without moving parts (slats, flaps, bay doors) or add-ons (insignia, modules, wing kit, decals). Cached per body mesh. Two lookups: `in_rect_xz` + `top_hit` (highest skin under a point; SkinPatch's flare panels and fairings, a linear scan as before) and `near` + `raycast` (a uniform grid of 3 cm cells, built on first use; decal cutting and the editor's cursor). Hangar models ≈ 54–63k triangles: the grid takes ~0.4 s once on the cloud CPU (software, slower than a PC).
- **Turret fairings** («Грач» 2 wing turrets, `SkinPatch.turret_fairing`) are added to the model after its insignia, in the hangar and in combat. `PlaneDecals` watches the model (`child_entered_tree`) and, when a fairing arrives, rebuilds the decal mesh once at the end of the frame with the fairings as `extra` skin (`PlaneHull.with_extra`, which leaves the shared cache alone): a decal on that wing lies on the fairing too, instead of vanishing under it.
- **Stamp** (`DecalLoadout.stamps`): a record becomes one or more oriented rectangles — a picture is one, a number one per digit, a tally one per mark.
- **Cut** (`DecalMesh.Builder.project`): for each stamp, the triangles in the grid cells around its oriented box that face the decal (dot with its normal ≥ 0.25 — the far side of a fin or the underside of a wing gets nothing) are clipped against the box sides (Sutherland–Hodgman) and depth (±max half-size); the pieces keep the skin's smooth normals and are lifted 0.9 mm along them (no z-fighting); UVs map the box to the picture's atlas rect (mirror flips u); the paint indices ride in UV2.
- **Merge**: all decals of a plane are one `ArrayMesh` surface with one `ShaderMaterial` → one extra draw call per own plane, in the hangar, the title flight and combat; nothing for wingmen. Shadows off.
- **Shader** (`PlaneDecals.SHADER`): atlas weights × palette (uniform array, `SRGB()` so both renderers show the same colours), model-space chips and fading (`wear`), alpha scissor (opaque pass, no sorting). One sampler.
- **Combat**: the battle model shares the hangar axes, so the same records are cut from the battle hull at sortie start (Render3D builds the player's unit then; no work mid-combat). Every graphics preset, «Низкое» included, draws the player's plane as a 3D model, so decals show on all of them. Battle hulls are 7.6–9.2k triangles: 8 sample decals → 390–540 triangles, 30–100 ms per plane at sortie load on the cloud CPU. Measured frames (§10): at gameplay height side decals are a few pixels; the fin badge and the wing decals are what reads.
- **Cost** (cloud, software rendering, so only relative): 8 sample decals → 1.2–1.5k triangles; building them after the hull is cached ≈ 0.16 s in the hangar (the editor's live preview rebuilds only the dragged decal's stamps — UI PR). Real-PC timings go into the `l7` log with the UI PR.

## 6. Hangar UX (UI PR, with the «меню/ангар» thread, which owns `hud_hangar.gd` / `hangar3d.gd`)

- Tab «САМОЛЁТ», row «Окраска:» → button **«Знаки ›»** opens the decal editor in the same tab. The 3D view on the left grows to most of the panel; the node cards on the right give way to the editor panel; «‹ Назад» (Esc / B).
- **Editor panel**: the plane's decal list (up to 12, with «вперёд / назад», «удалить»); the picture grid (locked ones dimmed with «откроется: …»); presets; two paint rows; for a number — digit spinners; buttons «Отразить», «На другой борт».
- **Placing**: pick a picture → the cursor over the plane shows the decal on the skin; click / A puts it. Selected decal: drag to move; wheel or triggers — scale; Q/E or bumpers — rotate (15° steps, hold for fine); F / X — mirror. The camera orbits with the right mouse button / right stick, so the player can reach the fin and the belly.
- **Gamepad**: left stick moves the cursor across the view (it sticks to the skin and slows down over it), A — place / pick up, B — drop the selection / back, LT / RT — smaller / larger, LB / RB — rotate, Y — next paint, X — mirror, d-pad — the panel (list, grid, paints), right stick — camera. All panel elements are `HudKit` buttons with focus (CS-11 focus model).
- Changes apply instantly, are free and are saved with the profile on leaving the hangar.

## 7. Unlocks (decided 27.10: option 2)

Rules in `game/scripts/balance/decal_unlocks.gd` (`DecalUnlocks.is_open`, `Profile.decal_open`). **The list below is a proposal waiting for Kanta's «ок»** (made with the `flak-heaven-game-design` skill: cosmetics only, no parts cost, no balance change, every rule reads a counter the game already keeps). A picture once open stays open (counters only grow); saved decals are never re-checked.

| Picture | Opens | Source |
| --- | --- | --- |
| number, three tally marks, shark mouth, lightning, chevrons, sun | from the start | — |
| wasp / rook / whale | own class's mascot from the start; another class's after one sortie on it | medal counter `sorties_<class>` |
| eye | crew rank 5 of this class | `Profile.crew_lvl` |
| mountain peaks | crew rank 10 | `Profile.crew_lvl` |
| winged skull | crew rank 15 (the ace rank, where the claw appears today) | `Profile.crew_lvl`, `Insignia.ACE_RANK` |
| black cat | first evacuation | medal counter `evacs` |
| dice | 10 sorties | `sorties` |
| ace of spades | first rival ace downed | `aces` |
| flaming skull | first «Крепость» downed | `fortresses` |
| skull on wrenches | first operation cleared | `op_<id>` |

«15 minutes on each class» from the first proposal has no counter of its own; the first evacuation stands in for it. The demo build keeps no medal counters: there only the start set, the mascots of the own class and the crew-rank pictures open. The «откроется: …» captions come with the editor (translation keys).

## 8. Save format and migration

Profile `user://profile.json`, per class and plane: `classes.<class>.decals1`, `decals2` (plane 1 / plane 2):

```json
"decals1": {"v": 1, "items": [
  {"id": "shark_mouth", "p": [0.33, -0.032, 0.021], "n": [0.05, -0.2, 0.98], "a": 0.0, "s": 0.03, "m": true, "c1": "bone", "c2": "red"},
  {"id": "number", "p": [0.03, -0.035, -0.054], "n": [0.0, 0.0, -1.0], "a": 0.0, "s": 0.026, "c1": "bone", "c2": "red", "t": "07"}
]}
```

- `id` picture id (`DecalCatalog.IMAGES`), `p` centre on the skin and `n` outward normal in model axes (nose +X, up +Y, left wing −Z, length 1; the same for hangar and battle models), `a` turn around the normal (radians; 0 — top towards the sky, or towards the nose on a horizontal skin), `s` height, `m` mirror, `c1`/`c2` paint ids, `t` digits of a number. Ids, never atlas cells.
- `DecalRecord.from_dict` checks every field (code.md §9.5): unknown picture, broken or non-finite vectors, a zero normal or a position off the plane → the entry is dropped; size clamped; angle wrapped; unknown paint → default; number text → digits only, 1–3, else dropped. More than 12 entries → the first 12.
- **Versions** (`DecalLoadout.VERSION` = 1): no key (profiles before decals) → no decals; format 0 (a bare list of records, early editor builds) → migrated; v1 → read; **a newer version** (a save from a newer build, e.g. full game → demo) is not drawn and is written back untouched, so it is never lost. `Profile.load_profile` passes every `decalsN` through parse → save, so the file always holds a clean current format.
- Unit tests (`game/tests/decals_cases.gd`, 54 checks): record JSON round trip, basis, validation, cap, migrations (none / format 0 / future / broken items), stamps (digits order, tally count and cap, mirror, width), projection (stays inside the box and its atlas cell, lifted towards the viewer, back faces skipped), profile save → load, old profile load.

## 9. PR plan

| # | PR | Contents | Size |
| --- | --- | --- | --- |
| 1 | **Core** (merged, #477) | `DecalCatalog`, `DecalRecord`, `DecalStamp`, `DecalLoadout` (cap, versions, migration), `DecalMesh` (raycast, clip, merge), `PlaneDecals` (material, attach from `Insignia.attach` for the own plane in hangar, title and combat; debug samples `--decals`), profile fields; atlas tool and atlas; unit tests. No UI | M (~900 incl. tests and tool) |
| 2 | **Logic without UI** (`claude/decals-core2`) | `PlaneHull` shared by `SkinPatch` and `DecalMesh` (one cache), turret fairings in the decal hull, `DecalPresets` (presets, symmetry helper), per-class tally counter, `DecalUnlocks` (proposal for Kanta's «ок»), unit tests | M (~500) |
| 3 | Editor: free placement | «Знаки ›» editor in `hud_hangar.gd` / `hangar3d.gd` (cleared by the «меню/ангар» thread 27.10), cursor ray on the hull, live preview of the dragged decal, move / scale / rotate / mirror / recolour, list order, presets, symmetry helper, gamepad cursor and bindings, «откроется: …» captions, translation keys | L (~600) |
| 4 | Art set | final 24–30 pictures, stencil font, the claw picture, review sheet for Kanta's «ок» | S |
| 5 | Tally and badges | ace claw as the tally's first mark, side claw sticker dropped, tally count shown in the editor | S |

## 10. Prototype frames and findings

Frames (Forward+ via lavapipe and GL Compatibility; hangar and gameplay height on graphics presets 0 / 2 / 3) are on the thread's local page. Findings:

- Free-placed samples (shark mouth and mascots on the curved noses, numbers on intakes and nacelles, tallies under the canopy, fin badges, rotated wing symbols beside the «Вершина» roundel) cut cleanly: no stretching across the nose curve, no gaps at panel joints, no z-fighting, nothing leaking to the far side of a fin.
- A fin badge over the class badge hides it, as decided; wing roundels stay.
- Hangar: 8 decals → 1.2–1.5k triangles; 0.4–0.7 s on the first build of a model (hull read), 0.13–0.33 s once the hull is cached (cloud CPU, software rendering).
- At gameplay height the plane is ~40 px and banks, so side decals read only in the hangar, the title flight and screenshots; wing and fin decals show in combat as colour spots — the editor should hint that big top-side decals are the ones seen in battle.

## Appendix: debug

- `--decals` — sample decals on every own plane (the presets: nose, number and tally on both sides, a fin badge, a rotated wing decal), `--decaltally=N` marks, `--decalwear=0…1`; prints `DECALS <plane>: N decals, T triangles, hull H triangles, ms`.
- Frames: hangar `--visual --hangarbench --decals --hcam=…`; combat `--visual --tilt=28 --op=1 --gfx=0|2|3 --decals --only=desert`.
