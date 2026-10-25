# Fortified area activity — design (draft for Kanta)

Status: **draft, waiting for Kanta's «да» on the rules** (numbers marked *guess*). Texture set chosen: Г. Thread «Сделать активность «Укрепрайон» из крепости», 2026-10-25.
Review page with sketches and texture renders: https://claude.ai/artifact/GNjvcTyiR3fhn3doF8Vzzp (stage 1), texture study: https://claude.ai/artifact/GS3AWzC9zxsNEK25y6eboH, set Г with our game models and destruction states: https://claude.ai/artifact/GLunKY4yCjT5npGcNeconG

## Kanta's brief (2026-10-25, verbatim points)

1. The AA-site activity stays as it is, separate.
2. The Highland ground fort (`o_fort`) becomes a new activity, «Укрепрайон» (fortified area).
3. New textures for the fort: search the web, offer options; several may be combined.
4. Keep the approximate size.
5. Keep the approximate form factor.
6. AA on the fort's high points (towers): the launcher taken from the SAM truck we made recently, with its animation — turn, lock, launch.
7. The fort is "conditionally destructible" when we attack it.
8. Look: variant 1 of the proposal page ("something like that, but in good quality").
9. Texture set Г (plaster over stone) chosen, quality to be raised; previews must use our real 3D game models.
10. On detection, announce «Обнаружена база противника» (enemy base detected).
11. Two machine-gun jeeps in the fort's yard.

## Rules impact

- Activities: 4 → **5** kinds (AA site, dogfight, transport, convoy, fortified area). The scale limit "4 activity types" (Kanta 17.10) is lifted by Kanta's 25.10 request; decision-log line on approval.
- Enemies: no new enemy *kind* — the tower launcher is the existing `sam` ground target (same missile, damage 24, flares divert half as often) on a fixed mount.
- Player-facing name: «Укрепрайон». The flying boss keeps «Крепость»; the two never share a word in UI text.

## How it plays

- **Where:** a real `o_fort` of the map. When the activity's turn comes, the spawner picks the fort nearest to a point ~1700 px ahead of the player within 3000 px (*guess*). No fort in reach → the activity is skipped this round (next one in the rotation starts), so no fort ever pops out of nothing.
- **Start:** arrow as other activities. Approach closer than 1150 px (as the AA site) → banner «Обнаружена база противника» (translation key), alarm, timer **90 s** (*guess*; optional-activity timers are allowed).
- **Defence:** 4 corner towers, each a SAM launcher on a turntable. Launcher logic = `GroundTarget` `sam`: lock `msl_sam_lock`, cooldown 5–6.5 s, range 900 px. Fort-wide cap: **at most 2 fort missiles in the air** (*guess*), so four launchers never salvo the player. Launchers don't drive; they rise, turn after the plane, lock, launch, kick (existing `_sam_launcher` animation).
- **Yard jeeps:** 2 convoy technicals (`fh_battle_e_convoy_technical.glb`) parked in the yard, same behaviour and HP as the convoy technical, but they never leave the yard (*guess*; Kanta may prefer pure decor). Not required for the goal.
- **Goal:** destroy the 4 launchers. Fort taken → garrison leaves, the fort burns. Optional bonus inside: fuel and ammo store (no weapons) that blows up in a chain.
- **Reward:** like the AA site — a pick of rare cards + parts; parts ×1.5 of the AA site (*guess*, harder fight). Timer out → fort stays, launchers go quiet when the player leaves 1500 px, no reward.
- **Kanta's principle check:** fixed launchers on towers are readable targets; missiles are capped; flares work; the payoff is big explosions and a burning fort.

## Conditional destructibility

The fort is not a physics object. It is split into **pieces with hidden HP**; player explosions (rockets, bombs, AoE skills) and hits on the launchers damage the piece they land in. Bullets do nothing to walls (no visible chip spam).

| Piece | Count | States | Trigger |
| --- | --- | --- | --- |
| Tower top with launcher | 4 | intact → damaged → crown collapsed | launcher HP 50 % / destroyed |
| Wall section | 8 (2 per side) | intact → breached | explosive damage pool per section (*guess*: 2 bomb hits) |
| Gate | 1 | intact → blown | explosive pool |
| Citadel / keep | 1 | intact → burning | fort taken |
| Store (fuel, crates) | 2–3 | intact → burnt-out | any explosive hit, chains to neighbours |

Each state swap plays a dust/debris burst (existing VFX atlas) and leaves scorch. After the fight the fort stays in its broken state for the rest of the sortie. Other forts on the map are the same model in a quiet, "abandoned" dressing.

## Model and textures

- Form factor of today's fort (square, 4 corner towers, gate in the south wall, citadel with keep), size `o_fort` 760 px; quality of the variant-1 sketch and the set-Г preview: round battered towers, sloped adobe walls with eroded tops, wooden beam ends, stone plinth, concrete repairs, sandbag nests.
- Built in Blender by code (like the convoy models), split into the pieces above, each with its broken variant. Battle budget 20–30k triangles for the whole fort (*guess*), matte.
- Materials (set Г): plaster_stone_wall_01 (walls, towers), old_stone_wall (plinth), brown_brick_02 and concrete_wall_008 (patches, breaches), old_planks_02 (gate), sandbag burlap from b10_sandbag_post; all Poly Haven CC0 except the sandbags (ours).
- Material mapping: world-space triplanar like `AdobeBuild.material()`, 3–4 tileable CC0 Poly Haven sets (texture study in the thread): wall plaster, exposed mud brick (breaches, crowns), stone plinth, concrete. Today the fort and the village use the cracked-riverbed **ground** texture on walls, so walls read as lifted ground.
- Tower launcher: the launcher subtree of `fh_battle_e_sam.glb` (`launcher_yaw` → `launcher_pitch` → `cell_*`) re-exported as its own GLB on a concrete turntable pad; animation code reused.

## Code touch points

- New `game/scripts/fort_area.gd` (activity node, like `aa_site.gd`), launcher reuse via `GroundTarget` with a `fixed` flag; pure placement and damage-state logic unit-tested (`game/tests/fort_area_test.gd`).
- `spawner.gd`: `ACTIVITIES` gains `"fort"`; picks a map fort.
- `render3d.gd`: the active fort renders as pieces instead of the single `AdobeBuild.fort()` mesh; launcher parts. **Coordinate first** with thread «Ускорить большие бои» (render3d typed-units refactor, plan 2026-10-25-render3d-typed-units).
- Translation keys for banner, hint, HUD.

## Size

Large (new system): spec → Kanta's «да» → implementation plan in `docs/superpowers/plans/` → PRs (model; activity logic; destructibility; polish). Estimate 4–6 days of thread work (*guess*).
