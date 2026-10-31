# Weapon profiles, second modernization, hangar link (PG-06) Implementation Plan

**Goal:** more variety in a sortie: a fork at weapon level 3 («профиль»), a second modernization per weapon plus modernizations for `srm` / `agm` / `hebomb`, hangar branches for the new weapons with tier 2 unlocking the third profile, mastery after level 35 as ranks of the chosen profile.

**Decision:** Kanta 31.10.2026 («Ну делай, давай пробовать») on the proposal `docs/progression/upgrade-variety-2026-10-31.md` with the recommended answers: package А (options 1 + 2 + 6), fork at weapon level 3, two profiles in the sortie and the third from the hangar, mastery 3b, doctrine and aces draft after the demo. Journal line in `docs/game-context.md`, backlog PG-06 (PG-07 folded in).

**Architecture (ADR-04 data split):** profile data and numbers in new `game/scripts/balance/profiles.gd` (`WeaponProfiles`); `Hardpoint.profile` (string id); firing branches in `hardpoint.gd` (`aam`, `rockets`) and `weapon_fire.gd` (`srm`, `agm`); projectile options (`splash_k`, `armor_k`, `burn`) in `projectiles.gd`; card kind `profile` in `cards.gd` offered as an «or-or» pair screen like the mastery branches; hangar gate in `Profile.profile_open`. Second modernizations: `Prog.EVOS2` with the same catalyst rules; `Hardpoint.evo_id`. Numbers are first guesses, measured with `tools/ci/balance.sh` per pair.

**Status:** in work 31.10, branch `claude/project-thread-3i09cf`, three PRs in this order.

## PR 1 — profiles for `aam`, `srm`, `agm`, `rockets`
- [ ] `balance/profiles.gd`: `LEVEL = 3`, `DEFS` per weapon (id → title, desc, vs, multipliers dmg/cd/range/spd, behaviour keys), `ORDER` (third = hangar), helpers `has(w)`, `k(w, id, key)`, `third(w)`.
- [ ] Unit tests `game/tests/profiles_test.gd` + `profiles_cases.gd` (TDD): every weapon of stage 1 has 3 profiles with text; multipliers of an unknown profile are 1; `profile_due(level, profile, weapon)`; third profile gated by hangar tier 2; `Hardpoint.dmg()` / `reload_time` / `range_px` take the profile factor.
- [ ] `Hardpoint`: `profile` field, factors in `_dmg`, `reload_time`, `range_px`, label with the profile title; `_fire_aam` / `_fire_rockets` branches; `WeaponFire.fire_srm` / `fire_agm` branches.
- [ ] `projectiles.gd`: missile `splash_k`, `armor_k`; rocket `armor_k`, `burn`; anti-radar targeting via `GroundTarget.variant`.
- [ ] `cards.gd`: no plain `weapon_up` for a group that is due a profile; `offer` returns the profile pair (or three) when due, before the mastery pair; `apply` sets the profile and raises the level by one; `finalize` text: effect, «против кого», «или-или» line, hangar hint for the locked third.
- [ ] `hud_cards.gd`: pair layout for kind `profile` (header «ПРОФИЛЬ ОРУЖИЯ / ИЛИ-ИЛИ», colour per profile), title and level line.
- [ ] Autotest flag `--wprofile=<weapon>:<id>` sets the profile at start; smoke all classes; one `tools/ci/full.sh`.
- [ ] `en.po` / `zh_CN.po` entries (`tools/i18n/check_po.py --sync`), docs (`game-context.md` rules), backlog.

## PR 2 — modernizations
- [ ] `Prog.EVOS` entries for `srm` («Шершни» roll ×2 / «Сторож» armor ×2), `agm` («Кувалда» warhead ×2 / «Кассета» frag ×2), `hebomb` («Землетрясение» frag ×2 / «Напалм» warhead ×2); alternatives «Стая» (`aam`, msl_motor ×2) and «Молот» (`rockets`, warhead ×2).
- [ ] `Hardpoint.evo_id` (which modernization), firing code per id, card offer picks the recipe completed first (both ready → both cards), icons/models reuse of the tier-3 models.
- [ ] Tests for recipes and offer rules; smoke; full once.

## PR 3 — hangar and mastery
- [ ] `Profile.WBRANCH` tiers 1–2 for `srm`, `agm`, `hebomb`; tier 2 of a weapon unlocks its third profile (`Profile.profile_open`).
- [ ] Mastery after 35 = ranks of the profile: `BRANCHES` replaced for weapons with a profile by one card «Профиль: ранг n → n+1» (+12 % to the profile's own feature), old pairs stay for weapons without profiles.
- [ ] Hangar text on the branch panel: which profile the tier opens.

## Checks
`tools/ci/unit.sh`, `tools/ci/smoke.sh all` after every change, `tools/ci/full.sh` once per PR (combat code). Balance: one profile pair at a time on the demo profile, «before → after» in the PR; corridors of `docs/balance-method.md` hold.
