# Design: deeper upgrades, stage 1 (PG-01)

Date: 2026-10-24. Decision: Kanta 24.10 (variant 3, all 7 weapons, 3rd group via hangar node, GD-02/03 first) — `docs/game-context.md` log, backlog PG-01. Proposal with the reasoning and genre references: https://claude.ai/artifact/DtMZeT9ujQ4nYTW4HTZEYF (Russian). Plan: [../plans/2026-10-24-progression-depth-stage1.md](../plans/2026-10-24-progression-depth-stage1.md).

## Goal

Make sorties of one class differ from each other in the demo (Нагорье, plane lvl 1, nodes ≤ 2, branch tier 1, crew ≤ 5). Today the card pool has 4 standard hardpoint weapons and every lvl-1 plane has 2 hardpoint groups, the first one pre-filled — a player decides one cell per sortie. Stage 1 adds a slot, three standard weapons (one per class first) and a choice of course gun. Stages 2–3 (PG-02, PG-03) add the other four weapons, modernizations, hangar «комплектация» and behaviour-changing branch tier 1.

## What changes for the player

1. **Third hardpoint group.** Hangar node «Узлы подвеса» lvl 2 adds a third group to that plane (lvl 1 and lvl 2 each by their own nodes; lvl 2 keeps its heavy hardpoint). The node card says so at lvl 1 → 2. The 6-module limit and the heavy hardpoint rules do not change.

   | Class | Third group (name in game) | Slots | Mount |
   | --- | --- | --- | --- |
   | «Оса» | «Законцовки крыла (пара)» | 2 | wing, frac 0.85 |
   | «Грач» | «Под фюзеляжем» | 1 | belly, centre line |
   | «Кит» | «Внешняя пара» | 2 | wing, frac 0.82 |

2. **Three new standard weapons** (fictional, "inspired by"; numbers are starting points, measured with `tools/ci/balance.sh` before the build):

   | id | Name (RU source string) | Classes | Behaviour | cd / dmg / range | Defence role (EX-04) |
   | --- | --- | --- | --- | --- | --- |
   | `srm` | «Ракеты ближнего боя» | fighter, attacker | 1 light heat-seeking missile per slot at the nearest air target ≤ 600 px; faster turn than `aam`, no retarget | 4.0 s / 22 / 600 | source class `homing`: no penalty vs agile; jammed ×0.4 as all homing |
   | `agm` | «Управляемая ракета "воздух-земля"» | attacker, bomber | 1 missile per slot at ground targets ≤ 900 px, priority: armored > big > nearest | 7.0 s / 90 / 900 | new source class `ap`: armor ×1.3 |
   | `hebomb` | «Фугасная авиабомба» | bomber | 1 heavy bomb per slot, same auto / button trigger as cluster bombs, ground only, ×2 vs ground like bombs, screen shake | 9.0 s / 110 / 200 (blast radius) | `blast` |

   Level 2–5 per weapon: `srm` +25 % dmg, −8 % cd; `agm` +25 % dmg, −6 % cd; `hebomb` +25 % dmg, +8 % radius. Reload floors: `srm` 2.0 s, `agm` 3.5 s (same reason as `MSL_CD_MIN`: stacking reload cards). Ground burst cap 70 % per salvo (`Enemy.GROUND_BURST`) applies unchanged.

   Class lists become: fighter `aam, rockets, flares, srm`; attacker `aam, rockets, flares, bombs, turret, srm, agm`; bomber `rockets, flares, bombs, turret, agm, hebomb`. Signature weapons (★) do not change. `start2` (hangar second weapon at crew 5) may offer the new weapons of the class.

   Tags (course points): `srm` → missiles, maneuver; `agm` → missiles, armor; `hebomb` → blast, armor. Modules that check "has missiles" (`seeker`, `msl_head`, `msl_motor`, `launcher`) count `srm` and `agm`; `frag`/`warhead` already generic. No modernization in stage 1 (stage 2), so at lvl 5 they keep offering mastery branches (S9-15) like other weapons.

3. **Course gun choice** — hangar, per class, before the sortie; free to switch, a new gun is bought once for parts.

   | id | Name | Rate × | Damage × | Bullet speed × | Spread | Other | Price |
   | --- | --- | --- | --- | --- | --- | --- | --- |
   | `std` | «Стандартная пушка» | 1.0 | 1.0 | 1.0 | 0° | — | owned |
   | `twin` | «Спарка» | 1.6 | 0.65 | 1.0 | ±3° | — | 250 |
   | `heavy` | «Крупнокалиберная» | 0.55 | 2.0 | 1.15 | 0° | source class `gun_ap`: armor ×0.8 (instead of ×0.5), agile ×1.15 | 400 |

   Multipliers stack with class `gun_dmg` / `gun_rate`, modules, crew traits, «обороты», «на хвосте», combat turn and «Дятел» exactly as today (they act on the result). Each gun has its own tracer width and `gun_fire` pitch (twin higher, heavy lower).

## Architecture

- **Data** stays where it is: `Weapons.DEFS` (title, short, desc, cd, dmg, range, flags) and `PlaneClasses.DATA` (weapons, groups). New: per-group optional keys `"frac"` and `"unlock": "pylons2"` in `PlaneClasses.DATA[cls]["groups3"]` (a separate list so the first two group indices and the turret / heavy indices never shift: card ids, 3D layout and saves use group indices).
- **Balance numbers** (level scaling, floors, gun variants, prices) go to new `game/scripts/balance/weapons.gd` (`class_name WeaponBalance`), per ADR-04. Existing weapons' numbers are not moved in this stage.
- **Firing code** for new weapons lives in a new file `game/scripts/weapon_fire.gd` (`class_name WeaponFire`, static functions `fire_srm`, `fire_agm`, `fire_hebomb`, each `(hp: Hardpoint, p: Player, manual: bool) -> bool`). `Hardpoint.update` dispatches to them; `Hardpoint._dmg`, `reload_time`, `range_px` read the level factors from `WeaponBalance` for these ids. `hardpoint.gd` (883 lines) is not grown by three more firing functions.
- **Bomb family:** code that is keyed on `weapon == "bombs"` for aiming, bay doors and the trigger (`_bomb_aim`, `aim_zones`, `render3d` bay doors, `uses_trigger`) checks `Weapons.is_bomb(id)` (`bombs`, `hebomb`).
- **Defence classes:** `Enemy.src_class` learns `"УР В-З"` → `ap` and `"курсовое: крупнокалиберная…"` → `gun_ap`; `DEF_K` gets `ap` (armor 1.3, agile 1.0) and `gun_ap` (armor 0.8, agile 1.15). Hint text for armor mentions the guided missile and heavy gun.
- **Profile:** class keys `"gun": "std"`, `"guns": ["std"]` added in `Profile._default_class` (otherwise load drops them — see memory note). `Profile.gun(c)`, `Profile.buy_gun(c, id) -> bool`, `Profile.set_gun(c, id)`, `Profile.third_group(c, lv) -> bool` (`node(c, "pylons", lv) >= 2`).
- **Player:** `setup` appends the third group after turrets and heavy when `Profile.third_group` is true. `PlayerGuns` takes the variant from `Profile.gun(cls_id)` once at setup (`pl.gun_variant`).
- **3D:** `PlaneArt.slot_points` uses `group.mount_frac` when set; belly group with 1 slot uses the existing single-slot point. Weapon models for `srm`, `agm`, `hebomb` — Blender by code in `game/tools/model_lab/` like `aam_*`/`bombs_*` (3 tiers each, glb), flat icons for cards and HUD. Kanta approves each model on an in-game frame (frames page, full-screen zoom — rule of 24.10).
- **Hangar:** node card text for pylons lvl 2; a «Курсовая пушка» row in the plane tab next to «второе оружие» (`_hg_start2` pattern): three buttons, price on locked ones.
- **Localization:** every new player string through `Loc.t` and entries in `game/locale/en.po`, `zh_CN.po` (ZH draft).

## Testing

- Unit (`game/tests/progression_test.gd`, TDD): class weapon lists and card pool filter (no `hebomb` for fighter, `srm` never on the heavy hardpoint); third group appears only with pylons ≥ 2 and keeps indices of groups 0–1, turrets, heavy; level scaling and reload floors of the three weapons; gun variant multipliers and `gun_ap` defence factor; profile defaults, buy (not enough parts → false, parts unchanged), set to an unowned gun → ignored, save/load round trip keeps `gun`/`guns`.
- Autotest flags for coverage: `--weapon=srm|agm|hebomb` puts the weapon on the first empty group at start; `--gun=twin|heavy`; `--group3` forces the third group. `tools/ci/smoke.sh all`, then `tools/ci/full.sh` once.
- Balance: `tools/ci/balance.sh` on the demo profile, before (main) / after; report M1–M7 and the share of damage by weapon; corridors from `docs/balance-method.md` must hold. The demo profile has pylons lvl 2, so the third group is in the baseline after the change — expected.

## Out of scope (later stages)

Anti-radiation missile, incendiary tanks, air mines, jammer pod, modernizations of new weapons (PG-02); «комплектация», branch tier 1 behaviour, hangar branches for new weapons, synergies (PG-03); a fourth group on plane lvl 2 (after the demo).

## Order

Merge only after GD-02 and GD-03 are in a build (Kanta 24.10, answer 4a). Code may be written on the branch before that.
