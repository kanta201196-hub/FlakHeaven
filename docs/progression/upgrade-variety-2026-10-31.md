# Upgrade variety: analysis and proposals (2026-10-31)

Thread «Расширить варианты прокачки» (Fable). Kanta 31.10: «не хватает разнообразия» in progression; allow some fantasy and forks in the missile upgrades. Status: **proposal, waiting for Kanta's choice** (numbered options on the Russian page, link in the thread). Nothing here is a rule until it is in `docs/game-context.md`.

Related: PG-01 (stage 1, merged), PG-02 / PG-03 (stages 2–3, idea), S9-15 (mastery after level 35), S14-09 (duplicate «Калибр» names — naming fix in the Прокачка thread; option 3 below removes the cause).

## 1. What the player chooses today (verified in code, main 971650a)

Layer 4, the sortie (`cards.gd`, `prog.gd`, `weapons.gd`):

| Piece | Count | Changes behaviour? |
| --- | --- | --- |
| Hardpoint weapons in the card pool | 7 (`aam rockets flares bombs srm agm hebomb`) + built-in turrets; 4 experimental only on plane lvl 2 after campaign ops | yes, but each has one fixed line of 5 levels: «+25 % dmg, −8 % cd» per level (exceptions: `aam` lvl 4, rocket count, `flares` lvl 4) |
| Modules | 19 ids, 6 slots per sortie | 14 are pure «+%»; behaviour only in `seeker`, `msl_head` lvl 3 (submunitions), class skill levels |
| Synergies | 12 weapon + 9 skill, 3 slots, via the «course» | yes |
| Modernizations (evolutions) | 7 defined, 6 live (`gunpod` is out of the game); **none for `srm`, `agm`, `hebomb`, nor for the 4 experimental weapons** | yes, one fixed form per weapon, fixed catalyst module |
| Mastery after level 35 | 2 generic branches «Скорострел» / «Калибр» for every weapon (own names only for `flares`, `emp`) | no, numbers only; produces S14-09 |
| Class mastery | 1 card per class | yes |
| Patches (tag thresholds 4 / 8) | 7 tags × 2 | small |
| Reserve cards | 5 | no |
| Wingmen | 3 types × 3 levels | yes |

A 15-minute sortie reaches about level 35 (`XpCurve`), so roughly 35 picks. Of them the picks that change *how* the plane fights: new weapon (1–2), course (1, at level 3), modernization (0–2 from 7:00), mastery (0–1, at the very end). Everything else is a level or a percentage. Estimate, not measured.

Layer 2, hangar weapon branches (`Profile.WBRANCH`, `WBRANCH3`): tiers 1–2 exist for the 6 old weapons only (one of them `gunpod`, removed); 18 of the 20 live options are «+15…25 %»; behaviour only in `flares` tier 2 and the bomb fuse. The three PG-01 weapons have no hangar branches (the hangar says so). Tier 3 only on plane lvl 2 after operation 2.

Layer 1 (6 nodes × 5 levels) and layer 3 (crew: 3 perks × 2 tiers, 5 callsign traits, 3 class skills) are numeric by design; medals (38, cap 10 %) too. «Битва асов» drafts 8 + 1 per ace from the same pool.

**Diagnosis.** Weapon growth is a straight line, so a lvl-5 missile is the lvl-1 missile ×2. The only forks are the course (3 slots) and one modernization per weapon, and three of seven weapons have no modernization at all. The mastery «or-or» comes after level 35, which in a 15-minute sortie is the last minute. End forms per weapon today: 1 (plus 2 numeric masteries).

## 2. Genre references

- *Vampire Survivors*: evolution = max weapon + passive (we have it); unions (two weapons merge); arcanas (run-wide rule changers, one at start, more at 11:00 and 21:00).
- *Hades*: boon tiers, duo boons; **Daedalus Hammer** — 2 per run, each changes how the weapon fires (fork, not a number). Closest to «развилки в прокачке ракет».
- *Deep Rock Galactic: Survivor*: at weapon levels 12 / 18 a choice of **overclocks** that change behaviour; meta-progression unlocks more overclocks per weapon.
- *Nova Drift*: weapon + body + shield, mods that branch deeper; «super mods» replace the weapon's behaviour.
- *Brotato*: items with a plus and a minus; set bonuses by tag count (our patches).
- *20 Minutes Till Dawn*, *Halls of Torment*: per-weapon upgrade trees with branch points at mid levels.

Common pattern: a **fork at a mid level** of the weapon, chosen in the run, with 2–3 forms, and a second, rarer fork at the end (evolution). We have the end fork only, and only one branch of it.

## 3. Options (numbers are first guesses for the balance run; ★ = recommended)

### 1 ★ Weapon profile: a fork at weapon level 3
When a hardpoint weapon goes 2 → 3, the upgrade card offers **2 profiles** (the third is unlocked in the hangar, option 6). The profile stays to level 5 and into the modernization. Rule «or-or»: same expected damage per second on the typical target ±10 %, different feel and different defence class (EX-04) so each profile has a target it is best against. Icon and one line on the card: «Профиль: …».

Stage 1 (missiles and rockets, Kanta's ask):

| Weapon | Profile A | Profile B | Profile C (hangar) |
| --- | --- | --- | --- |
| `aam` | «Двойной пуск»: 2 missiles per slot, ×0.55 each — groups | «Дальний захват»: lock 1050 → 1500 px, speed +30 %, ×0.9 — hits first | «Осколочная»: air burst 90 px, ×0.5 to neighbours — dense groups (tag +blast) |
| `srm` | «Рой»: 3 mini-missiles ×0.4 at different targets ≤ 400 px — drones | «Гончая»: turn ×2, range 600 → 800, ×0.85 — aces, interceptors (agile) | «Перехватчик»: also shoots enemy missiles ≤ 300 px from the player (tag +armor) |
| `agm` | «Кассетная»: splits over the target into 4 ×0.35, radius 80 — convoys | «Бетонобой»: ×1.6, armour ×1.5 — bunkers, «Крепость» | «Противорадарная»: homes on AA / radars from 1 400 px — PG-04 hook |
| `rockets` | «Веер»: 6 rockets ×0.75 in a 40° cone — area | «Кумулятив»: 3 rockets ×1.8, armour ×1.3 — armour | «Зажигательные»: ×0.8 + burn 50 % over 2 s (as incendiary ammo) — convoys |

Stage 2: `bombs` («Зажигательные» / «Мины» 8 s on the ground / «Бетонобойные»), `hebomb` («Объёмная» radius ×1.5 ×0.7 / «Сейсмическая» two blasts / «Напалм»), `flares` («Ложная цель» decoy drone / «Дымзавеса» −30 % gun damage 3 s / «С подрывом»), `turret` («Зенитная» anti-missile / «Крупнокалиберная» / «Спарка»).

Why level 3: with the demo XP curve a weapon reaches level 3 around minutes 2–5, inside the demo window; level 2 is too early (the player has not felt the weapon yet). Size: L (new system: `weapon_fire.gd` / `hardpoint.gd` profile branches, card UI, icons, EN/ZH, unit tests for the numbers, balance run per profile). Brainstorming → plan → Kanta's «да».

### 2 ★ Second modernization, and modernizations for `srm`, `agm`, `hebomb`
Every pool weapon gets two modernizations with different catalyst modules; the first recipe completed is offered (both ready — a choice). Profiles × modernizations = 6 end forms per weapon instead of 1.

| Weapon | Existing | New (catalyst) |
| --- | --- | --- |
| `aam` | «Шмель» (reload ×2) | «Стая» (`msl_motor` ×2): 4 light missiles every 3 s, 35 each, each retargets twice |
| `srm` | — | «Шершни» (`roll` ×2): salvo of 4 on every dodge and every 3 s, turn ×2; «Сторож» (`armor` ×2): missiles also kill enemy missiles |
| `agm` | — | «Кувалда» (`warhead` ×2): 300 dmg, blast 160, armour ×1.5, cd 8 s; «Кассета» (`frag` ×2): 6 submunitions along a convoy |
| `rockets` | «Ливень» (engine ×2) | «Молот» (`warhead` ×2): 2 heavy rockets ×4, armour ×1.3 |
| `bombs` | «Бабушкин ковёр» (frag ×2) | «Наковальня» (`armor` ×2): one bomb 250, radius 220, shake |
| `hebomb` | — | «Землетрясение» (`frag` ×2): blast + shockwave 300 px, AA silent 2 s; «Напалм» (`warhead` ×2): burning pool 6 s |
| `flares` | «Салют» (roll ×2) | «Миражи» (`engine` ×2): 2 decoy drones fly alongside 8 s and take bullets and missiles |
| `turret` | «Дикобраз» (armor ×3) | «Зенитка» (`servo` ×2): turrets shoot missiles every 1 s (80 %), drones ×2 |

Size: M–L (10 new behaviours; `srm`/`agm`/`hebomb` ones close the PG-02 gap). Can ship in halves: first the three missing ones + `aam`/`rockets` alternatives.

### 3 Mastery after level 35 per weapon
3a: own pairs per weapon instead of generic «Скорострел / Калибр» (as `flares`, `emp` already have): e.g. `aam` «Залп парой» / «Пробой щита» (×1.5 vs ace shield). Fixes the cause of S14-09. Size S–M.
3b ★ (after option 1): mastery = ranks of the chosen profile (+12 % to the profile's own feature per rank, up to 5). One system instead of two. Size S once profiles exist.

### 4 Modules with a level-3 feature
Each «+%» module gets one behaviour line at level 3, as `msl_head` already has: `armor` — ramming drones costs no HP; `engine` — 2 s of afterburner after a dodge; `wing` — «на хвосте» cone wider; `gun_dmg` — every 10th shell ×3; `gun_rate` — «обороты» grow twice as fast; `reload` — a kill of an ace or a big target reloads all hardpoints; `frag` — blast edge 70 %; `warhead` — blasts set fire 1 s; `msl_motor` — a missed missile turns around once; `launcher` — first launch after reload is doubled; `radio` — a lost wingman returns in 8 s; `servo` — turrets shoot missiles; `magnet` — repair kits fly to the player too. Makes the 6-slot choice a build choice. Size M. After options 1–2.

### 5 Sortie doctrine (VS arcana)
At the course screen (level 3) also one of three «доктрины» that change the sortie's rules: «Налёт» (XP ×1.25 to 7:00, enemies ×1.15 HP after 10:00), «Одиночка» (no wingmen, +25 % damage, +1 module slot), «Снабжение» (repair kits ×2, pickup ×1.5, damage −10 %), «Охота на асов» (aces ×0.8 HP, others ×1.1), «Старая школа» (gun ×1.6, hardpoints ×0.7). Size M; changes rules broadly. Recommended after the demo.

### 6 ★ Hangar link: branches for the new weapons, tier 2 unlocks the third profile
Tier 1 for `srm`, `agm`, `hebomb` (missing today). Tier 2 of any weapon unlocks its profile C (meta-progression discovers forms, as DRG Survivor). Layers stay separate: the hangar unlocks, the sortie chooses. Replaces the «tier 1 changes behaviour» line of PG-03. Size S–M.

### 7 «Битва асов» draft from its own pool
The 8 pre-sortie picks start at weapon level 3 so the first pick is a profile; mode pool without ground weapons. Size S, after option 1.

## 4. Recommendation and order

Package **PG-06 = options 1 (stage 1) + 2 (missing three + `aam`/`rockets` alternatives) + 6**, then 3b and 4, then 1 stage 2 and the rest of 2; 5 and 7 after the demo. Reason: all of PG-06 lands inside the 15-minute demo window (minutes 2–5 and 7+), and the player sees a real fork three times per sortie instead of once at the end.

Checks before «done» (game-design skill): one profile pair at a time on `tools/ci/balance.sh` (demo profile, «before → after»); stacking with `reload` floor 60 %, `launcher` floor 0.4, `CD_FLOOR`; every profile has a defence class and an icon over the enemy it is good against; «or-or» equal by result, different by feel.

## 5. Questions for Kanta (answered on the page or in the thread)

1. Package: А = 1 + 2 + 6 (recommended) / Б = only 1, missiles and rockets / В = 1 + 2 + 4 + 6 at once.
2. Fork at weapon level 3 (recommended) or level 2.
3. Choice of 2 profiles with the third from the hangar (recommended) or all 3 at once.
4. Mastery after 35: 3a own pairs now / 3b ranks of the profile after option 1 (recommended).
5. Doctrine (5) and the aces draft (7): after the demo (recommended) or into PG-06.
