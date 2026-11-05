# Build depth, endless sortie and s15 balance: plan (2026-11-05)

Kanta 04.11: «тупо качай ракеты и не парься… не хватает собирательства», «хочется углубить билдостроительство». Kanta 05.11 on the proposal page (https://claude.ai/artifact/UtAJBVVAjweHHDMLXztXX1): «Давай все предложения, которые ты рекомендуешь, сразу. Не переживай насчет сроков до демо». The game-design thread wrote this plan, and it splits into four parts with one owner each:

| Part | What | Owner thread | Backlog |
| --- | --- | --- | --- |
| A | Б3 archetypes with rule ranks + Б4 trade-off cards | «Архетипы и карты плюс за минус» | PG-11 |
| B | Б1 synergies from two different things + Б5 build album | «Связки и альбом сборок» | PG-11 |
| C | Р1 «Долгий вылет» (endless after the Fortress) | Геймдизайн | MO-01 |
| D | Balance 21.1, 22.1, 23.2 | Геймдизайн | GD-14, GD-15, GD-16 |

All numbers below are first guesses for the balance run, not rules. Kanta's 05.11 «сразу» overrides the usual «one balance change per build» for this package. Each part still measures before and after on `tools/ci/balance.sh` (demo profile, 3 classes) and writes the result in its PR.

## Why the build collapses to missiles (verified in code, main c614cab)

- Tag «missiles» sits on 4 of 7 pool weapons (`aam rockets srm agm`) and 5 modules (`reload seeker msl_head msl_motor launcher`). «kinetic» has 2 modules and no pool weapon (`gunpod` is out of the game). See `Prog.WEAPON_TAGS`, `Prog.MODULE_TAGS`.
- 5 of 12 synergies use missiles as their main tag or second tag (`Cards.SYNERGIES`). `Player.missile_k()` also scales the wingmen's and skills' missiles.
- Missiles home in on targets and hit both air and ground, so the build needs no aiming.
- Every card only adds something. No card trades a plus for a minus, nothing rewards mixing weapons, and no list shows what has been found.
- PG-06 (profiles, second modernizations) gave forks *inside* one weapon. There is still no reason to take a *second* weapon.

## Rules for parts A and B

- Read `docs/game-context.md` («Правила игры сейчас») and use the account skill **flak-heaven-game-design** before setting numbers. Kanta's principle: the player enjoys, not overcomes. A minus must be a choice, never a punishment.
- Fictional world: no real names in titles. Player text goes through translation keys; append to `en.po` and `zh_CN.po`.
- New pure logic goes into `game/scripts/balance/<system>.gd` with unit tests (`game/tests/*_test.gd`, TDD). Run `smoke.sh all`, and `full.sh` once before the PR.
- Each part gets an F1 toggle so it can be compared and rolled back: `build_arch` (A) and `build_pairs` (B), both 0/1 with **default 1**, since Kanta approved them. When a toggle is 0 the s15 behaviour must come back.
- Shared files and who owns what:
  - A owns `Prog.PATCHES` and `PATCH_AT`, archetype code, and the archetype HUD panel.
  - B owns `Cards.cond_list`, `advances_course`, `course_options`, `SYNERGIES` conditions, and the album.
  - Both touch `cards.gd`. Keep your diffs to your own functions. Whoever merges second merges `main` in and re-runs the checks.
- Screens and HUD follow `docs/standards/ui-design-system.md`. Gamepad focus must work.

## Part A: archetypes (Б3) and trade-off cards (Б4)

### A1. Archetypes with rule ranks

Today the patches are small «+%» at 4 and 8 tag points, and the player doesn't see them. They become **archetypes with three ranks**. Each rank changes a *rule*, not only a number. The archetype names show in combat.

- Archetypes map to the existing tags:
  - «Ракетчик» (missiles)
  - «Бомбёр» (blast)
  - «Стрелок» (kinetic)
  - «Турельщик» (turrets)
  - «Командир звена» (wing)
  - «Манёвренный» (maneuver)
  - «Броненосец» (armor)

  Seven archetypes, or merge turrets into «Стрелок» if seven read as too many on the panel. The thread decides and writes down why.
- Ranks at tag points `ARCH_AT = [4, 8, 12]` (start values in `balance/archetypes.gd`):
  - Rank I is today's patch I.
  - Rank II is today's patch II, or a stronger rule.
  - Rank III is new and must visibly change how the plane fights.
- Rank effects must not repeat an existing synergy effect (`Cards.SYNERGIES`). Ideas:
  - «Стрелок» II: manual fire pierces 1 target.
  - «Стрелок» III: every 5th course-gun shell is HE (×3, burst 60 px), and «обороты» fill twice as fast. This closes GD-17.
  - «Командир звена» III: +1 wingman over the limit (today's wing patch II moves here).
  - «Бомбёр» III: a bomb hit leaves a 2 s fire pool.
  - «Ракетчик» III must not stack another «+% damage». Give it a behaviour instead, e.g. a missile that misses turns around once.
- Make every archetype reachable. Add 2–3 cards for kinetic and turrets (modules or a gun line) so that «Стрелок» can reach rank III in a focused sortie. Give each a tag and an icon.
- HUD:
  - A compact archetype strip in combat shows the top 3 archetypes by points, their rank, and points to the next rank.
  - Card hint: «▲ Стрелок 5 → 6 (ранг II на 8)».
  - Pause screen: all archetypes and their effects.
- Check:
  - In a focused sortie on each class, rank II arrives by about 8:00 and rank III by about 12:00. Measure with the bot and log the minute in telemetry (`arch_rank_<tag>_<n>`).
  - Equal by result: the best non-missile archetype build is within 20 % of the missile build's damage per minute in the bot, or the gap is written in the PR with a reason.

### A2. Trade-off cards (Б4)

There are 3–4 rare cards, each with a plus and a minus. The text shows them in two colours. They come from level 10, at most 2 per sortie, and take no module slot. Start set:

| Card | Plus | Minus |
| --- | --- | --- |
| «Без брони» | +25 % damage | repair ×0.5 |
| «Фанатик ракет» | missiles +40 % | course gun −50 % |
| «Облегчённый планер» | speed +15 %, turn +10 % | hull −20 % |
| «Тяжёлые пилоны» | +1 hardpoint group (if the class and model allow it; otherwise swap for «Двойной боезапас»: hardpoint reload −20 %, speed −12 %) | speed −12 % |

- Stacking check: the reload floor is 60 % (`RELOAD_FLOOR`), and the launcher floor and `CD_FLOOR` still hold. Run with three trade-offs at once and confirm none is useless or broken.
- Telemetry: how often each card is taken and the death rate after taking it.

## Part B: synergies from two different things (Б1) and the build album (Б5)

### B1. Every synergy needs two different things

Today a synergy unlocks from tag points, and missiles fill tags fastest. The new conditions for every synergy are **two different things**:

- weapon A + weapon B, or
- a weapon + a system (wingmen, class skill, a named module),

each at the slot's level (`SLOT_COST.lvl` and `mods` and `wing`).

- Tag points leave the synergy conditions; tags belong to the archetypes (part A). Keep `MAX_SYN = 3`, the course screen and the course hint. The hint now shows the recipe: «есть Ракеты В-В 4, нужны Ловушки 3».
- Existing synergies with one weapon get a second requirement:
  - `carousel` (aam)
  - `thermobaric` (rockets)
  - `salvo` (rockets)
  - `carpet_road` (bombs)
  - `hedgehog` (turret)
  - `mirror` (flares)
  - `gunner` (gunpod, out of the game: give it a new pair or retire it)

  Keep each effect. Choose the second thing so that it pairs a different family: missiles with defence, blast with kinetic, and so on.
- Add 6–8 new two-thing synergies, each with a new effect, a name, a colour and a visual. Ideas from the proposal page:
  - «Перекрёстный огонь»: course gun + turrets. A target hit by manual fire takes ×1.5 from turrets.
  - «Огненный коридор»: bombs + rockets. A rocket salvo sets a strip on fire, and bombs in it burst 3× wider.
  - «Разведчик»: «Ласка» wingman + `agm`. AA marked by the wingman is hit by `agm` at any range.
  - «Обманка»: flares + `srm`. Each flare launch also fires an `srm` at the enemy that locked on.
  - Pairs with the experimental weapons (railgun, EMP, laser, plasma) for plane level 2.
- Every class must have at least 4 reachable synergies with its allowed weapons (`PlaneClasses.allows`). Write a unit test for this.
- Check: in the bot, the share of sorties whose synergies use 2+ hardpoint weapon families goes up from s15. Measure with telemetry `syn_pair_<id>`.

### B2. Build album (Б5)

- Add a hangar tab «АЛЬБОМ» next to «НАГРАДЫ». It is a grid of every synergy, modernization (`Modernizations.all()`), weapon profile and archetype rank III. Found entries are lit and show the class and date. Unfound entries are silhouettes with the recipe as a hint.
- Save in `profile.json` as `album: {id: {"t": unix, "cls": id}}`, migrating old saves. The first find gives parts (`RewardBalance`, start 15) and a combat banner «Новое в альбоме: …», and shows on the result screen.
- Medal «Коллекционер» (`MedalBalance`) may switch to counting album entries. If it does, migrate the old counter so nobody loses a tier.
- The album is **on in the demo**: it is the reason to play again. Medals stay off in the demo.
- Check:
  - Unit tests for album save, load and migration (the pattern of `medal_profile_test.gd`).
  - A visual bench frame `--albumbench`, like `--medalbench`.

## Part C: «Долгий вылет» (Р1, game-design thread)

After the Fortress falls, the evacuation screen offers «Держаться дальше». If the player stays:

- The sortie goes on with no time limit.
- The HP cap of the pressure (`PRESSURE_MAX`) and the density cap (`DENS_MAX`) rise slowly, without an upper bound.
- `dmg_ramp` keeps growing.
- Aces come every 5 min.

Death ends the sortie and counts as an evacuation for rewards (100 % parts, not 50 %), plus a bonus per minute over 15:00. The hangar shows the record time per class and its build (weapons, synergies, archetype ranks).

- Unlock: after the first Fortress kill on that operation.
- Performance: the cloud has no GPU, so check enemy and projectile caps and judge FPS only from logs on Kanta's PC.
- Pure logic (caps after 15:00, rewards) goes into `balance/endless.gd` with tests.

## Part D: balance from the s15 review (game-design thread)

| Id | Was → now | Where |
| --- | --- | --- |
| 21.1 | post-hit invulnerability 0.7 → 0.55 s (campaign, not «Битва асов») | `player.gd` `damage()`, constant in a balance file |
| 22.1 | density cap `DENS_MAX` 1.5 → 1.8 | `spawner.gd` |
| 23.2 | from level 30, a card screen every second level. The level in between gives +2 % damage automatically, with a banner and no screen | `run_state.gd` / `XpCurve`, unit tests |

Log rows go in `docs/game-context.md`. After s16, check in Kanta's log:

- 21: hull minutes 5–15
- 22: FPS worst 1 % at 14:00, kills per minute
- 23: picks per sortie, minutes per pick after level 30

## Order

Parts A, B and D start now in parallel. Part C starts after D. A and B merge into `main` independently, with the toggles on, and land in the next test build that Kanta asks for.
