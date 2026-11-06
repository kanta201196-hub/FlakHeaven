# Art and 3D quality bar (from the Highlands work)

The graphics and 3D-model rules the project reached on biome 1 «Нагорье Шахрисанг» by 2026-11-06, in one place.
Every new or reworked model, texture and effect, starting with biome 2 «Архипелаг Таласора», meets this bar
before it is shown to Kanta. Sources are linked per rule; the decision log `docs/game-context.md` wins where they differ.

Short version for Kanta (Russian): the page linked from the 06.11 message in the thread «Запустить второй биом Архипелаг».

## 1. Look and renderer

| # | Rule | Source |
| --- | --- | --- |
| L1 | Renderer is **Forward+**; GL Compatibility is only the fallback / lowest quality. Judge every visual in Forward+ (lavapipe in the cloud). | VIS-01, PR #392 |
| L2 | Look = **realistic, detailed models** (Kanta's flight-sim references) under **EVERSPACE-style vivid light and colour**. Gameplay camera unchanged (top-down). | VIS-01, 2026-10-24 |
| L3 | Colour constants in shaders go through `SRGB()` (`game/shaders/srgb.gdshaderinc`) or `source_color`; vertex colours need `vertex_color_is_srgb`. Effect shaders are tuned as rendered in Forward+ and are not wrapped. | CLAUDE.md, PR #392 |
| L4 | Exposure: `Render3D.FP_EXPOSURE_K` 1.5 and effect `FX_EXP = 1/FP_EXPOSURE_K` change together. | PR #393 |
| L5 | The player's own plane stays readable: effects fade over it (`fx_clear`), thin outline (`own_plane_read`). | #466, #560 |
| L6 | Fictional world: no real countries, flags, insignia, letters, hull numbers, real aircraft or ship names in models, textures or prompts. Real prototypes are used only as internal reference (scratchpad, never in the repo). | CLAUDE.md rule 1 |

## 2. Surfaces and paint

| # | Rule | Source |
| --- | --- | --- |
| S1 | **Matte, realistic paint, no gloss**, big objects especially (the glossy AA site, 19.10). | Kanta 2026-10-19 |
| S2 | **No model ships with flat, even paint**: edge wear, cavity grime and dust, seams or panel lines where they fit, soot near engines and guns, rust/salt where it fits, and a **roughness map with variation**. Bake approach: `game/tools/blender/turret_paint.py`. | Kanta 2026-10-26 (Fortress domes), `working-rules.md` |
| S3 | **Every combat or scenery model has colour + normal + ORM (roughness) maps**, not a single albedo. Highlands props (`models/biome`, `models/village`) and all Highlands enemies already do. | measured 2026-11-06, see §7 |
| S4 | No torn or "mouse-chewed" texture edges, no zigzag paint across sharp ridges, no dark specks from bakes; check close-ups yourself before showing. | Kanta 2026-11-01, `docs/tasks/3d-models-handoff.md` |
| S5 | Camouflage: no blotches where the prototype has none (e.g. `CAMO_CLEAR`); liveries that Kanta removed stay removed. | #544, #551 |
| S6 | Natural textures (ground, rock, plaster, stone, wood) come from CC0 libraries (Poly Haven, ambientCG), licence line in `game/art/LICENSES.md`. Ground texture is never reused on walls (walls then read as lifted ground). | 2026-10-15, «Укрепрайон» 25.10 |
| S7 | Wrecks: burnt look (render3d `BURNT_SHADER`), sit on the ground (`_wreck_on_ground`), furrow colour in the GLB; ships sink in `SINK_TIME`. | #338, #448 |

## 3. Shape and geometry

| # | Rule | Source |
| --- | --- | --- |
| G1 | **Reference first**: for any part, collect real photos or a model of a similar object, list its features, then build clean geometry from that. Smoothing or remeshing generator output is not a fix. | Kanta 2026-11-01 (`model-reference-first`) |
| G2 | **Everything mounted on a model follows its structure**: panel lines, load paths, sweep and skin curvature; flush or faired. No flat boxes on top of the skin. Write in the report why each part sits where it does. | Kanta 2026-10-27 («Крепость» hatches) |
| G3 | **Stores sit where they would on the real type**: on «Оса» only rail missiles on the wingtip rail, rocket pods under the outer wing (`PlaneArt.OUTER_PAIR`); shots leave from the stores as seen; pods stay after a salvo. | Kanta 2026-11-06 («НАР на Осе 2»), PR #582 |
| G4 | Proportions checked against references and against the player's plane and the Fortress at gameplay camera height ("техника размером с крепость"). | Kanta 2026-10-19, 2026-10-24 |
| G5 | Intakes, nozzles, nacelles: built geometry after the prototype (oval lip, splitter, dark duct, no fake engine face); ray-leak test from inside (no ray escapes). | #537, #540, #556 |
| G6 | Silhouette and detail must read from the gameplay camera; detail that only shows in the hangar goes into the hangar shaders (`plane_detail.gdshaderinc`), not geometry. | PR plane-detail 01.11 |
| G7 | Nature and rocks: layered, broken shapes (strata, cracks, ledges), never "inflated balls"; trees with real crowns, not PS1-style cards. Prefer CC0/CC BY scans reworked over primitive code shapes. | weak-models review 2026-10-28 |

## 4. Budgets and technical

| # | Rule | Source |
| --- | --- | --- |
| T1 | Combat models ≤ 30k triangles (big player bombers up to 36k); props 1–8k; hangar models full quality. `battle_bake.py` does not simplify the outline: feed it a coarse source. | `3d-handoff-progress`, #556 |
| T2 | Model axes: length 1 along +X nose, +Y up in Godot; moving parts are named nodes with the pivot at the node origin (`turret`, `launcher`, `antenna`…). | `3d-models-handoff.md` §0 |
| T3 | Combat/biome textures import **BC7** (`compress/mode=2`, `high_quality=true`) with mipmaps; hangar-only textures stay lossless. Force-add gitignored `.import` files. | #543, #570 |
| T4 | Never key a static cache by a hangar Mesh/Texture; clear such caches in `Hangar3D.release`. | #549 |
| T5 | Constants read by cell-generation worker threads are packed arrays / `Vector2`, warmed on the main thread; never call RenderingServer getters on worker tasks. | #234, #488 |
| T6 | Sketchfab: only CC BY / CC0, candidate list with large previews, link and licence approved by Kanta **before** download; rework; line in `game/models/CREDITS.md`. Meshy is a reserve and spends credits only with Kanta's yes; nature in biome 2 is never Meshy. | 2026-10-18, 2026-10-24 |

## 5. Effects and feel

| # | Rule | Source |
| --- | --- | --- |
| F1 | New feel/effect changes go to `main` **behind an F1 toggle, off until Kanta's «ок»** (R-22). Pure model/texture fixes that Kanta already asked for do not need a toggle. | Kanta 2026-10-31 |
| F2 | Effects anchor to the model (nozzles, gun anchors, 3D barrels), not to sprite points. | #448 |
| F3 | GPU effects (`GpuFx`) in Forward+, `Boom3D` in Compatibility; Forward+ omni lights `omni_attenuation 0.5`. | VFX-01…06 |

## 6. Review and proof

| # | Rule | Source |
| --- | --- | --- |
| R1 | Every model is shown as a frame **from the game camera**, plus a close-up studio view (side, 3/4, top). | `working-rules.md`, Kanta 2026-10-19 |
| R2 | Frames on **3 graphics presets** (`--gfx=0`, `2`, `3`) side by side, **before/after**, large, each opening full screen with zoom, on an HTML page (Kanta does not open file paths). Add a gameplay-height frame with the player plane when size matters. | Kanta 2026-10-24 |
| R3 | One model (or one tight group) per PR with its frames; game rules and hitboxes unchanged by model work. | weak-models decision 2026-10-28 |
| R4 | Checks: `tools/ci/pick.sh`, `smoke.sh` (+ `full.sh` if combat code changed); after `git pull` a full import before tests. | CLAUDE.md |

## 7. Biome 2 audit snapshot (2026-11-06)

Measured from the GLBs in `main` (triangles / maps):

- **All 41 scenery props in `game/models/biome2`** carry a single colour map; only `a28_wreck_plane_sea` and `a40_shrub` add a
  normal map; none has an ORM/roughness map. Highlands props have colour + normal + ORM (rule S3 fails).
- Weakest geometry: `a37_pine_b` 100 tris (card), `a03_radar_mast` 404, `a21_terrace_wall` 624, `a12/a15/a19` houses 600–800.
- Sea enemies: `e_ship_battery` 1.35k tris, 9 flat-colour materials, no textures (replace); `e_ship_bulk` 2.7k, colour only;
  `e_leviathan` 33k, 7 materials, no ORM. Others (`e_ship_*`, `e_ekranoplan`, `e_seaplane`, `e_drone_sea`, `e_albatross`,
  `e_cruiser`, `e_lev_*`) have colour + normal + ORM.
- Kanta's 2026-10-28 list for biome 2 (deferred until now): replace `e_ship_battery`, cliffs `a31`/`a33`, `a03` radar mast,
  `a21` terrace wall; improve cruiser «Сторож», landing barge, «Крачка», «Левиафан» launcher and ZSU (light vertex-colour
  stripes), seaplane, tanker, bulk carrier, wrecks `a26`/`a27`, trees `a37`/`a38`, coastal gun `a01`; per-part wear bake on the
  «Левиафан» hull; the `SeaProps.plan()` worker-thread race on const arrays (rule T5).

Fix order and status live in `docs/backlog.md` (tasks `B2-Q*`).
