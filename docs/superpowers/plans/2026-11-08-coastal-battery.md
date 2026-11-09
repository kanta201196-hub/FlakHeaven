# Coastal battery activity «Береговая батарея» (B2-A01) — plan

Decision: `docs/game-context.md`, log line 2026-11-08 (Kanta: option 1, 4 guns, heavy flak only).
Status: Kanta «да» 2026-11-09 with two changes — item 7: no ring cap; item 10: plus a repair kit. Placement strip 60–260 px (frames showed the berm over the water at 40). Done in PR #615.

## What exists (read 2026-11-08)
- `Spawner.start_activity`: the «fort» slot of the queue is skipped at sea (`Biome.sea()`), the next kind is taken.
- `FortArea` (extends `AASite`): 4 fixed SAM launchers, `ACTIVATE_R` 1150 px, timer 150 s, `Events.activity_succeeded(&"fort")`.
- `GroundTarget` "sam": `HP_ARMOR` 135 × hp_k, floor `SITE_FLOOR_S` 6 s of player DPS, defense "armor", xp 5.
- `Warship._shore_salvo/_tick_shells`: shells with a ground circle, burst after `SHELL_T`, damage `gun_dmg("big") × 2.5` = 30 at base.
- SAM missile damage `msl_sam_dmg` 24. Player hull: Оса 120, Грач 160, Кит 250.
- Model: `b2_shore.py::_gun_site` builds the whole site (pit, parapet, mount) as one joined mesh `body`; broken site exists.
- `Render3D._ground_parts` already turns a child node named `turret` of a battle GLB toward the target.

## Rules and numbers (proposal; *guess* = to tune after the first play)
| # | What | Value | Reference |
| --- | --- | --- | --- |
| 1 | Gun HP | 135 × enemy growth, floor 6 s of player DPS, defense «armor» (as a fort launcher) | `GroundTarget.HP_ARMOR`, `SITE_FLOOR_S` |
| 2 | Shell damage | 20 × campaign dmg (*guess*) | SAM missile 24, «Сторож» salvo 30 |
| 3 | Burst radius | 110 px (*guess*) | «Сторож» circle 200 px |
| 4 | Ring before burst | 1.0 s; shell aims at the player's predicted point at burst time | Kanta 08.11 «~1 s» |
| 5 | Reload per gun | 5–6 s random (*guess*) | SAM 5–6.5 s |
| 6 | Range | 1100 px from the gun (*guess*) | SAM 900 px |
| 7 | Cap | ~~at most 2 rings~~ no cap (Kanta 09.11: «пусть стреляют активно») | fort: 4 missiles |
| 8 | Placement | centre as the fort (AHEAD 1700 px along heading, out of view, ≥ 2 screens); 4 guns on land 60–260 px from water, level pad, 300–600 px apart, within 900 px of the centre; no spot → slot skipped as today | Kanta 08.11 |
| 9 | Alarm and timer | 1150 px from the centre, 150 s | `FortBalance` |
| 10 | Reward | as the fort: 60 parts, rare pick every 2nd activity, else +90 parts and 20 % repair; plus 1 repair kit (Kanta 09.11); label «ЗА БЕРЕГОВУЮ БАТАРЕЮ»; xp 5 per gun | `Rewards.ACTIVITY[&"fort"]` |
| 11 | Medal | «Укрепрайон взят» counts batteries too (otherwise unreachable at sea) | `medals.gd` fort_area |
| 12 | Wreck | a destroyed gun becomes the broken site model and stays for the sortie | Kanta 08.11 |

## Steps
1. **Model split** (`b2_shore.py`): emit the mount as two extra objects, `turret` (shield, breech, cradle, sights, platform, rack) with a child `barrel` (tube, brake, mantlet, recoil) pivoted at the trunnions; base keeps pit, parapet, pedestal. Export a battle GLB `models/battle/fh_battle_e_coast_gun.glb` and a top sprite `art/enemies/e_coast_gun.png`; scenery `a01_battery_gun.glb` stays as it is (look unchanged).
2. **Logic** (`coast_battery.gd` extends `AASite`, `balance/coast_battery.gd`, `GroundTarget` variant "coast_gun"): placement pure function with unit tests (`game/tests/coast_battery_test.gd`: spacing, distance to water, fallback); shells with a ring (as `Warship._shells`); cap; `Events.activity_succeeded(&"battery")`, `Rewards`, banner/hint/radio text via `Loc`.
3. **Spawner**: at sea the «fort» slot becomes «battery»; `--battery` check flag; autotest trace.
4. **3D**: barrel elevation from distance (Render3D, next to `_ground_parts`); muzzle flash and recoil; broken model on death.
5. **Checks**: `unit.sh`, `smoke.sh all`, `full.sh` once (combat code), frames on 3 presets for Kanta.
