# Highlands map generation: analysis (2026-10-31, build s14)

Requested by Kanta on 31.10 (s14 list, items S14-04 and S14-05): "flat, levelled circles are left on the
ground, that must not be" and "activities (AA) still appear next to the player; they must not appear in view,
at least 2 screens away". This page walks the whole Highlands generation pipeline, names what made each
problem and what was changed. Code: `game/scripts/terrain3d.gd` (relief, pads, chunks),
`background.gd` (cell objects), `biome_props.gd` (models), `spawner.gd` + `aa_site.gd` + `fort_area.gd`
(activities).

## 1. Pipeline in one picture

1. **Cells.** The world is cut into 1400 px cells (`Background.CHUNK`). Each cell rolls at most one object
   (`Background._chunk_object_raw`, 62 % chance): rocks, mesa, fort (760 px), village (1650 px), oasis
   (420 px), crater, wreck.
2. **Object filter** (`Terrain3D.fix_object`, set as `Background.place_filter`): settlements (village, fort,
   oasis) move to a spot by the river (`_settle_spot`, next to the road), a lower-priority settlement closer
   than one screen to another is dropped (`_settle_crowded`), mesas never sit on a settlement, craters only on
   the valley floor, everything is pushed out of the river guard zone.
3. **Relief** (`Terrain3D._relief_prov`, RV-01…RV-04): the river field and side valleys give the valley
   floor; `ReliefProvinces` gives mountains by region, gullies, pillars, terraces, gorges; the river bed and
   village streams are cut in.
4. **Pads** (`Terrain3D._flat`): under every village, fort, oasis (and 30 % under a crater) the relief is
   multiplied by a weight that is 0 inside radius r = size/2 (times the settlement outline) and rises back to
   1 at 2r. Rock and scree masks are multiplied by the same weight.
5. **Ground marks** (`_compute`, `AdobeBuild.ground_mask`): trodden earth and fields round settlements,
   scorch and craters of battle scenes (`scenes`).
6. **Props** (`BiomeProps.plan/apply`, worker thread per chunk): trees, bushes, yurts, sandbag posts (forts),
   keeping out of settlements.
7. **Chunks**: built on the worker pool from a main-thread snapshot (`_ctx`), placed one per frame; hidden
   chunks are kept (`_spare`), heights cached (`_hgrid`) for `surface_fast`.
8. **Activities** (`Spawner.start_activity`): AA site, «Укрепрайон» fort, convoy, transport, ace, rescue.

## 2. S14-05: the flat circles

**What Kanta saw.** Round, dead-flat basins of ~1–1.5 km cut into mountains and mesas, with field patches
round them and nothing inside (screens 1, 2), and a lighter round disc round an oasis (screen 3).

**Cause 1, the main one: empty fort spots.** Since s13 (Kanta: "the fort is no scenery") a fort is drawn only
once the «Укрепрайон» activity takes it (`Background.forts_hit`). But only the 3D model was hidden. Every
other stage still treated each `o_fort` cell object as a fort:

- `_sides` kept the fort's **side valley**: every settlement except a village cuts a capsule of half-width
  0.375 × size from its centre to the nearest river point into the valley field (`valley()` drops to the
  floor inside it). Relief rises with the valley distance, so round the fort's centre this is a round basin
  ~600 px across plus its fans. This was the biggest part of the circles (found from frames: with only the
  pad removed the basin stayed).
- `_flat` kept the 760 px fort's pad: relief × 0 inside ~380 px, back to full height at ~760 px. Forts stand
  by the road at the edge of the valley floor (`_settle_spot`: road + fort radius), so the far half of the
  pad cuts into the valley wall: a round basin with a cliff rim.
- `_compute` kept the fort's ground mask (`AdobeBuild.ground_mask("o_fort")`): trodden earth and the
  ring of field sectors. These are the field patches round the empty basin.
- `BiomeProps` kept the fort's sandbag posts and the tree keep-out.

Most sorties take one or two forts, the map has many, so most fort spots were empty pads.

**Cause 2: pads are circles.** Even under a visible settlement the pad edge is a circle (village and oasis:
a circle with a mild low-harmonic wobble, `AdobeBuild.outline`, ±20 %; crater: a pure circle). Inside it the
relief is exactly zero (no bumps at all) and rock/scree masks are zero, so the ground shader paints plain
valley floor: a lighter disc where the pad runs into a hill (screen 3).

**Fix (PR for S14-05):**

1. `Terrain3D.shown(o)`: a fort not in `forts_hit` marks nothing. The chunk snapshot (`_ctx`) drops it from the
   objects (so no ground mask, no props), `_flats_near` drops it from the pads and `_sides` cuts no side valley
   for it. Its spot is plain land.
2. When the activity takes a fort, `FortArea.setup_fort` calls `Terrain3D.rebuild_area(fort, 2.5 × size)`:
   cells round the fort are rebuilt with the pad, earth, fields and posts. Per-cell epochs (`_epoch`) drop
   results computed before the change; a cell that is on the screen keeps its old mesh until the new one is
   placed (`_redo`), so no hole opens. The activity takes forts two screens away (S14-04), so the swap is not
   seen.
3. Natural pad edges (`pads_natural`, F1 slider `map_pads`, `--pads0` for "before" frames): the fade
   distance of a pad changes with the direction (noise sampled on a ring round the pad, so along each ray the
   ground still only rises): from 0.7× to 1.6× the old fade speed. The flat core under the buildings is
   unchanged. The side-valley edge of a settlement (oasis, village tributary) is scaled by 1 ± 0.3 of
   low-frequency noise (`SIDE_WOBBLE`) the same way. The edge is ragged instead of a circle.

**Not changed (and why):**

- The flat core itself: buildings, the fort walls and the village mesh need level ground.
- Craters keep their small 30 % dent: they only stand on the valley floor and fans (`fix_object`), 170 px.
- S14-15 (light patches on the ground from combat height) is likely the same thing as cause 2 (rock and
  scree masks are zero inside every pad, so the floor texture shows); *guess*, to check on the next build.

## 3. S14-04: AA sites next to the player

**Cause.** `Spawner.start_activity` put the AA site at 1700 px from the player, ±1 rad off the heading. The
screen at the default zoom is 1920 px wide, so the centre was inside one screen of the player. Then
`AASite.place` searches level dry ground: `find_floor` within 900 px, then rings up to ~2.9 km round the
wanted point. A site could end up even closer than 1700 px and inside the view. The fort activity had the
same 1700 px "ahead" point (it skipped forts on screen, but not near ones).

**Fix:**

- `ActivityBalance` (`game/scripts/balance/activity.gd`): minimum distance = 2 × the longer side of the
  visible screen (world px; 3840 px at 1920×1080, more when the camera zooms out). Every point of the site
  (bunker and all vehicles) must be at least that far and outside the camera's view rect (with the 3D tilt
  margin, `Render3D.view_now`).
- AA site: up to 6 tries, centres at min + 900 px ahead and turned ±0.6, ±1.2 rad, then 900 px farther. The
  first one that passes is used; if none passes, the try whose nearest point is farthest.
- Fort: `FortArea.pick_fort` skips forts whose walls come within the minimum distance of the player; the
  wanted point moves to min + 900 px ahead.
- Convoys already start off screen and drive in (A-06), the transport and the ace fly in; they were not
  changed. The rescue beacon (1500 px) is not a hostile site; not changed.

**Cost.** At 390 px/s cruise the player needs ~10 s more to reach a site. Activity timers start only on
approach (`ACTIVATE_R` 1150 px), so they are not shortened.

## 4. Other findings in the pipeline (no change now)

- `_flat` multiplies the whole relief, rock and scree masks by the pad weight; a pad that runs into a mesa
  leaves a scarp. Settlements sit by the road, so the scarp is rare for villages and oases now that empty fort
  pads are gone.
- `rebuild_area` is the first mid-sortie ground change. Any future "terrain reacts to the game" feature
  (craters from bombs, burnt fields) can use it.
- `_flats` and `_objs_cache` are cleared together when the object cache grows past 400 cells; harmless.

## 5. S14-10: a "piece of explosion texture" stuck in a mountain

**Cause.** Map craters (`o_crater`, 170 px) were the last cell objects still drawn as a 2D picture: a level
`PlaneMesh` with the crater image at the ground height of the crater's centre (`Render3D._sync_objects`).
The ground under it was flattened only 30 % (`FLAT_OBJS`), and `fix_object` keeps craters off slopes by the
raw river field only, which does not see RV-01 mountains, terraces and banks. On any slope the uphill half of
the picture went into the ground and the rest stuck out as a floating slab with a straight cut edge.

**Fix.** `o_crater` has no 3D picture (`OBJ_SKIP_3D`) and no pad; the chunk build paints it as the same
ground mark as a battle-scene crater (`burns`, radius 0.4 × size), so it lies on the relief at any slope.

The "slab in the sea" on Leviathan (PC autotest, 31.10) is not this: the Archipelago has no cell objects; that
is a SeaProps model and was not changed.
