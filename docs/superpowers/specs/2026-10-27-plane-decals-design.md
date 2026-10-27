# Plane decals and personal markings — design (proposal)

Status: **proposal, waiting for Kanta's decision** (request 27.10: «также проработай систему наклеек/кастомизации — черепа там всякие, номера, нейтральные символы»). Nothing here is merged into `main`; the prototype lives on branch `claude/plane-decals` behind the debug flag `--decals`.
Page with frames (Russian, local): see the thread report. Related: liveries `game/scripts/livery.gd` (test 3.5-s4, п. 35), insignia `game/scripts/insignia.gd` (V-07, Kanta 17.10), game-context line 137 «Кастомизация: позывной, портрет, эмблема, окраска, голос — косметика за достижения».

## 1. Goal

Let the player make their own «Оса», «Грач» and «Кит» recognisable: a skull or mascot, a side number, nose art and a kill tally — the way squadron pilots personalise aircraft — while keeping the world fictional and the planes realistic and matte. Pure cosmetics: no effect on combat, balance or progression numbers.

## 2. Rules every decal follows

1. **Placement follows the airframe** (Kanta's rule). Every slot is a place a real ground crew would paint: nose sides for nose art, fin for a badge, wing upper surfaces for roundels, fuselage sides aft of the cockpit for the number, kill markings under the canopy. Decals are shot onto the actual skin of each model (§4), so they bend with the nose and sit flat on the intake or nacelle.
2. **Fictional and neutral only** (CLAUDE.md hard rule 1). No stars, real roundels or flags, eagles, unit badges, real squadron or national symbols, swastika-like or other politically loaded signs, no real aircraft names. Skulls are generic «danger/ace» skulls without military unit context (no crossed bones under a cap, no SS-like Totenkopf proportions). Every new decal goes through a short checklist in review: «does it resemble any real national, unit or political sign?».
3. **Matte and weathered**: decals are paint, not stickers — matte (roughness 0.82–0.92), they fade and chip with the paint (`wear`), never glossy or neon.
4. **The air-force roundel «Вершина» stays fixed on the wings** (decision 17.10): it tells «ours» from enemies in combat. The fin keeps the class mark by default; the player may replace it with a personal badge.
5. **Wingmen and enemies get no player decals**: wingmen keep «Шевроны», enemies stay clean (catalog decision 16.10).

## 3. Decal kinds (prototype set, 18 pictures + 10 digits)

| Kind | Pictures in the prototype atlas | Slot | Colours |
| --- | --- | --- | --- |
| Skulls | winged skull, skull on crossed wrenches, flaming skull | fin, nose | bone / accent / ink |
| Neutral symbols | lightning disc, ace of spades card, dice, geometric chevrons, smiling sun, mountain peaks with sun | fin, nose | primary / secondary / ink |
| Mascots (animals) | wasp («Оса»), rook («Грач»), whale («Кит»), black cat | fin, nose | primary / secondary / ink |
| Nose art | shark mouth (two cells wide, faces the nose on both sides), angry eye | nose | teeth / mouth / ink |
| Side number | digits 0–9, 2–3 digits picked by the player | number | fill / — / outline |
| Kill tally | air mark (fictional delta drone), ground mark (tracked vehicle), bomb mark | kills | fill / accent / ink |

All art is drawn by code (`game/tools/decal_atlas.py`, Pillow, no downloads; digits use PT Sans Bold from `game/fonts`, OFL). Style follows the existing insignia: flat, bold ink outline, three paints. Release set: about 24–30 pictures (the prototype's 18 + more skull stylings, more animals, a second number font — stencil), still one 2048×1024 atlas.

**Colours**: one palette of ~12 matte paints (bone, off-white, sand, ochre, orange, rust, red, olive, teal, blue-grey, black, gunmetal) shared by all decals; per decal the player picks the primary and secondary paint, ink stays near-black (an option for «ink = primary» for silhouette decals). No free RGB picker: the palette keeps decals plausible, matte and readable, and is gamepad-friendly.

## 4. Slots per plane

Slots come from the models themselves: `game/tools/blender/decal_slots.py` shoots a 16×6 grid of rays at the hangar model from the side at the slot's position, keeps only skin that faces sideways (rays pass through wings and pylons), nudges the slot up to ±4 cm / ±1.6 cm and shrinks it until all rays land on one smooth surface, and exports a tiny GLB `models/mech/fh_dec_<class>_<lvl>.glb` (like `fh_ins_*`). Battle models share the hangar axes, so the same GLB fits both. Measured on the hangar models (units: plane length = 1, x from tail −0.5 to nose +0.5, z up):

| Plane | Canopy glass x | Nose art (x, z, w×h) | Kill tally, under the canopy | Side number, aft of the cockpit | Fin | Wings |
| --- | --- | --- | --- | --- | --- | --- |
| «Оса» 1 | 0.174…0.274 | 0.325, −0.032, 0.061×0.028 | 0.225, −0.022, 0.065×0.014 | 0.030, −0.035, 0.060×0.030 (intake side) | badge on both fins (fh_ins) | «Вершина» |
| «Оса» 2 | 0.215…0.361 | 0.405, −0.036, 0.060×0.030 | 0.290, −0.008, 0.080×0.014 | 0.160, −0.050, 0.035×0.014 (intake front, small) | both fins | «Вершина» |
| «Грач» 1 | 0.177…0.311 | 0.365, −0.067, 0.044×0.022 | 0.245, −0.030, 0.080×0.016 | −0.120, −0.034, 0.051×0.022 (engine nacelle) | fin | «Вершина» |
| «Грач» 2 | 0.091…0.402 | 0.395, −0.064, 0.050×0.025 | 0.250, −0.070, 0.080×0.016 | −0.180, −0.027, 0.065×0.026 (engine nacelle) | fin | «Вершина» |
| «Кит» 1 | 0.226…0.357 | 0.380, −0.066, 0.041×0.021 | 0.300, −0.053, 0.060×0.014 | −0.200, −0.058, 0.072×0.032 (rear fuselage, aft of the wing) | fin | «Вершина» |
| «Кит» 2 | 0.253…0.378 | 0.405, −0.046, 0.041×0.021 | 0.330, −0.025, 0.060×0.014 | 0.230, −0.026, 0.035×0.017 (forward fuselage aft of the cockpit) | fin | «Вершина» |

Findings and fixes for the release version:
- «Оса» 2 and «Кит» 2 number slots came out small (the intake lip and the wing glove leave little flat side). Release: «Оса» 2 number on the intake side under the wing leading edge, larger, and «Кит» 2 number on the rear fuselage under the fin (tested later by frame). Every slot gets Kanta's «ок» on a hangar frame per plane, like models.
- The existing ace mark «Коготь» (`side_*` in `fh_ins_*`) sits where the kill tally and the number go on some planes. Proposal: the claw becomes the first glyph of the kill tally row (an ace's tally starts with the claw), and the `side_*` sticker is dropped.
- Nose art on «Кит» 1 sits right behind the glazed navigator nose; on «Грач» the nose is narrow, nose art stays small (≈4 cm at plane length 1).
- Prototype frames show that the nose slots are long and low (made for the shark mouth): a square picture (mascot, skull) letterboxes into a small square. Release: two nose shapes per plane — «mouth» (long, low, on the chin) and «badge» (square, higher, under the windscreen) — and each picture says which it uses.
- Combat frame (`--visual --tilt=28 --op=1 --gfx=2`, Forward+): at gameplay height the whole plane is ~40 px and banks; only the fin badge shows as a coloured dot, side decals are invisible. Decals are a hangar, title-flight and screenshot feature; the combat read of «my plane» stays with the livery and the wing roundel.

## 5. How decals render (decision: sticker meshes + one atlas)

Three options were compared:

| Option | Cost in combat | Renderers | Fit to the shape | Verdict |
| --- | --- | --- | --- | --- |
| **A. Sticker meshes shot onto the skin (as insignia) + one mask atlas + a small shader** | +6 tiny meshes (≈120 vertices each) on the own plane only; pixel cost only where a decal is drawn; alpha scissor, opaque pass, no sorting | Forward+ and GL Compatibility | exact (shot onto the real skin offline) | **chosen** |
| B. Projection inside the livery shader (per-slot box projection, sample the atlas) | every pixel of the plane's skin pays N slot tests + 1 sampler; the default paints today have no shader at all, so it would have to be always on; touches the livery owner's shader | both | good on flat parts, smears on curved noses | rejected |
| C. Godot `Decal` nodes | clustered decals: every pixel inside the decal box pays, including the wing behind a fin; cost grows in the busy combat clusters | **Forward+ only** — GL Compatibility has no decals (`code.md` §1), so fallback PCs would lose them | projects through thin parts (fin both sides, wing under the slot) | rejected |

Details of A:
- **Atlas** `art/decals/decal_atlas.png`, 8×4 cells of 256 px. Pixels store paint weights, not colours: R = primary, G = secondary, B = ink, A = coverage, RGB normalised so mipmaps keep weights. Imported lossless with mipmaps (`detect_3d` off), ~200 KB on disk, 8 MB in VRAM with mipmaps — release can drop to 2048×1024 BPTC.
- **Shader** (`PlaneDecals.SHADER`, one `Shader` shared by all materials): mode 0 — one picture letterboxed to the slot's aspect; mode 1 — 2–3 digits from the digit cells; mode 2 — tally row repeating one mark `count` times; `flip_u` makes directional art (shark mouth) face the nose on both sides. One sampler (budget 8, `code.md` §7.7).
- **Weathering**: model-space value noise (does not swim with UV stretch): chips cut holes through which the paint shows (`wear` 0…1, default 0.35), colour fades towards dusty grey, grime blotches darken it; roughness 0.82–0.92, metallic 0. Release: `wear` follows the plane — a fresh decal after a change, more worn with sorties (cosmetic only).
- **Combat**: the own plane only. From the combat camera (tilt 28°) side decals are 2–6 px — the fin badge is what reads; nose, number and tally are mainly for the hangar, the title flight and close-ups. On graphics preset «Низкое» (flat sprites) there are no decals; on «Среднее» only the fin. Materials are created when the plane model is built (sortie start), never mid-combat; the shader is warmed with the other plane materials (CS-09).
- **Release optimisation** (if `perf.gd` logs ask for it): merge the 6 slot stickers into one mesh with the slot id in `CUSTOM0` and per-slot parameters in a uniform array → one draw call per plane.

## 6. Hangar UX

Coordinated with the «меню/ангар» thread, which owns `hud_hangar.gd` and `hangar3d.gd`; the UI PR is theirs or done with them.

- **Where**: tab «САМОЛЁТ», the row «Окраска:» gets a button «Знаки ›» at its end. It opens the decal editor in the same tab: the 3D view on the left stays (the camera flies to the selected slot — focus, yaw, pitch, distance per slot, the same as the `--hcam` bench views), the node cards on the right are replaced by the editor panel; «‹ Назад» (Esc / B) returns.
- **Editor panel** (top to bottom): slot list (Нос · Номер · Счёт побед · Киль) with the current choice; grid of pictures for the slot (locked ones dimmed with the condition as a caption, `ui-design-system.md` disabled state); two rows of paint swatches (primary, secondary); for the number — three digit spinners and «2 / 3 цифры»; for the tally — mark type and «показывать / скрыть»; «Без знака» in every grid.
- **Gamepad focus**: LB / RB switch slot (camera follows), d-pad moves in the grid, A applies, Y switches focus to the swatch rows, X «Без знака», B back. Default focus — the current picture of the first slot. Every element is a `HudKit` button, so mouse and focus share one list (CS-11 focus model).
- Applying is instant and free (no confirm dialog); the choice is saved with the profile like the livery (`Profile.save()` on leaving the hangar).
- Per class, shared by plane 1 and 2 (slot names are the same; positions differ per model).

## 7. Unlocks — open question for game design

Game-context line 137 (10.10) already says customisation is «косметика за достижения». Two options; neither changes balance, economy or progression numbers:

1. **Everything open from the start.** Simple, no new rules; customisation is a creative toy from minute one. Minus: nothing to chase, and the decision of 10.10 is not followed.
2. **Starter set open, the rest earned by milestones (recommended).** Open at start: numbers, kill tally, the class mascot, 3 neutral symbols, shark mouth. Earned, one picture per milestone the game already tracks: operations cleared (`Campaign.cleared`), crew rank (5 / 10 / 15 — the claw at the ace rank 15 as today), first rival ace downed, first boss, 15-minute sortie survived on each class. No spare parts cost (no new economy), shown in the hangar as «откроется: …». Follows the decision of 10.10 and gives the Steam achievements later a visible reward.

The milestone list and kill-tally source are game-design calls and go through the `flak-heaven-game-design` skill and Kanta before PR-5.

**Kill tally source** (needs a decision too): A) one mark per rival ace or boss downed with this class (rare, meaningful, fits 6–15 marks); B) one mark per 100 kills of this class (grows fast, needs a cap and a «×» counter). Recommended: A.

## 8. Save format and migration

Profile `user://profile.json`, per class in `classes[<class>]` (beside `livery`):

```json
"decals": {
  "nose":  {"id": "shark_mouth", "c1": "bone", "c2": "red"},
  "fin":   {"id": "skull_winged", "c1": "bone", "c2": "rust"},
  "num":   {"text": "07", "font": "block", "c1": "sand"},
  "kills": {"mark": "air", "show": true}
},
"tally": {"aces": 0, "bosses": 0}
```

- Ids, not atlas cells (`code.md` §4): `decal_catalog.gd` maps id → atlas cell, kind, allowed slots, unlock; paints are ids from the palette table. Re-ordering the atlas never breaks saves.
- `fin.id == ""` — the class mark (today's look); missing `decals` — no decals (today's look). An old profile loads unchanged: `Profile.load_profile` copies only keys present in `_default_class`, so the new keys simply start with defaults — no data is lost and no conversion is needed.
- Validation on load (`code.md` §9.5): every field type-checked; unknown id or paint → slot cleared; `num.text` → digits only, length 2–3, else «»; tally numbers → `int`, ≥ 0.
- Tally counters cannot be back-filled for old profiles (sortie history is not saved): they start at 0 from the update; the decal still works.
- `Profile.VERSION` goes 1 → 2 only if SaveIO (CS-02) is merged by then, with an empty migration step; otherwise no bump is needed.
- Unit tests (TDD, `game/tests/decals_test.gd`): load an old profile, load garbage values, digit and id validation, tally increments on `Events` ace and boss kills.

## 9. PR plan

| # | PR | Contents | Size |
| --- | --- | --- | --- |
| 1 | Decal art | `decal_atlas.py`, final set (~24–30 pictures, second number font), `art/decals/`; review sheet for Kanta's «ок» | S (~350 lines of tool, 1 PNG) |
| 2 | Slots and rendering | `decal_slots.py` with per-plane fixes from §4, 6 GLBs; `plane_decals.gd` + `decal_catalog.gd`; attach in hangar, combat and title flight; LOD by graphics preset; hangar `--hcam` frames of every slot for Kanta | M (~400) |
| 3 | Profile and tally | `decals` and `tally` fields, validation, tally counting from `Events`; unit tests first | S–M (~200) |
| 4 | Hangar editor | «Знаки ›» editor, camera fly-to-slot, gamepad focus, translation keys; with the «меню/ангар» thread | M–L (~450) |
| 5 | Unlocks | after the game-design decision (§7): catalog unlock fields, «откроется: …» captions | S (~120) |

Total ≈ 1500 lines including the tools — a «large» task (`working-rules.md`): starts after Kanta's «да» on this design and §7. Not on the Next Fest critical path; fits after the demo build or between builds.

## 10. Open questions for Kanta

1. Rendering option A (sticker meshes + atlas) — agree?
2. Unlocks: option 2 (starter set + milestones) or option 1 (all open)?
3. Kill tally: A (aces and bosses) or B (per 100 kills)?
4. The ace claw moves into the kill tally row (frees the side spot) — agree?
5. May the fin badge replace the class mark («Стрела» / «Перо» / «Винт»), or should the class mark stay and the personal badge go elsewhere (e.g. the nose only)?
6. Wing roundels stay fixed «Вершина» on both wings — or allow a personal symbol on one wing (the only decal clearly visible in combat)?
7. Which pictures of the prototype set to keep, drop or add (e.g. more animals, more skull stylings)?

## Appendix: prototype

- Flags: `--decals` (demo loadout per class), `--decalset=2` (second loadout), `--decalwear=0…1`.
- Hook: one line in `Insignia.attach` (`insignia.gd`) — no hangar UI file touched.
- Frames: hangar `--visual --hangarbench --decals --hcam=…` (free close-ups), combat `--visual --tilt=28 --op=1 --gfx=2 --decals`, Forward+ via lavapipe.
