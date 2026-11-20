# Work review: Kanta and Claude on Flak Heaven (13.11–20.11.2026)

Weekly review, task R-15 (Kanta's decision 22.10.2026). Format follows `docs/review/2026-11-13-work-review.md`.
Nothing in the game, settings or rules was changed by this review: rule changes below are proposals only, Kanta decides.

**Sources:** `main` 13.11 15:55 (`d838bd34`) → 20.11 16:59 (`235844c`), 60 commits, PRs #623–#641; `docs/game-context.md`
decision log 17–20.11; `docs/backlog.md` («Where we are» 18.11, R-15…R-33, S19-11, S19-13, V-08); `docs/status-log.md`
(3.5-s19); `docs/process/build-remarks/3.5-s19.md`; `docs/owner-checklist/kanta-now.md` (20.11);
`docs/process/task-observer-trial.md`; threads «Собрать правки по сборке 3.5-s19», «Починить модели самолётов»,
«Маркетинг и реклама», stand-ups 16.11 and 20.11, the 13.11 review thread; the thread list since 13.11; project memory.
The project chat was not read page by page (the history pages from 16.10 and is too long), so Kanta's words come from
the threads. Guesses are marked.

---

## 1. Short version

Two very different halves. **13–16.11: no game code at all** (8 commits, all stand-ups, marketing plans and one
task-observer review). **17–19.11: one build and a burst** — 3.5-s19 built 17.11 on Kanta's command, he sent 15 remarks
in two evenings, and **16 code PRs** were merged in about 50 hours; 7 of the 8 first remarks were fixed in code the same
night. Steam art (R-29) is finished, the «Кит» bomb package (GD-18) is in, earshot became a standing check.

Five things hurt the most:

1. **The 13.11 review was never answered** (7 proposals, 7 days, listed in every stand-up). Two of its points became
   real costs this week: V-08 is still unchecked (proposal 1b), and the channel published 1 post (proposal 3).
2. **Plane models go round and round.** «Грач» 2/3 changed in **5 merged PRs in ~30 hours** (#634, #635, #637, #638,
   #641), each announced as «смотри в следующей сборке». The model that stuck came only after Kanta asked «сделай коллаж,
   как ты меня понял». Kanta had to point at defects himself: «он капец как выбивается, ты тупо взял истребитель с 2
   килями», «и вот тут у Кит 5 тебя ничего не смущает?».
3. **Bugs from the second batch of remarks have waited 2 days for «готово».** Items 9 (hangar text overlap), 10 (weapon
   upgrade «Взять — 400» does nothing), 12 (marks stay after a convoy) and 14 (result screen overlap) are «Not started»
   since 18.11. Decided items S19-11 and S19-13 (plans by Claude) have not started either.
4. **Stand-ups say less than they claim.** 16.11: «треды и модели — по памяти», links of the form `project?thread=` that
   do not open (Kanta 17.11: «при переходе на капсулы и ревью — вот такое»). 20.11: three sections «не сверял», and S6
   is shown as «срок 20.11, сегодня» although it was moved to «after App ID» on 17.11.
5. **Steam: three loose ends, no owner moves them.** Valve's review was due ~16.11, nobody has looked (only Kanta can
   see Steamworks); V-08 (Meshy and Hunyuan commercial terms) still «ждёт Kanta» though it is reading work; the demo date is
   still 25.01 in `docs/process/early-access.md` against 18.01 in Steamworks (**fourth review in a row**). New: at least two plane
   models now come from CC BY Sketchfab sources, which require the author's name in the credits; no check that the credits have it.

Main recommendation: **proposals 1 and 3 first** (Steam and bugs, Claude can start today), then 2 (models).

---

## 2. What works well (keep it)

- **One remarks file per build.** `docs/process/build-remarks/3.5-s19.md`: every remark numbered, with owner thread,
  cause and PR. Kanta said «готово» 17.11 18:57 UTC; items 2, 7, 8 were merged by 20:40 and 4–6 by 07:00 next morning.
- **Fixes with causes, not guesses.** Pickups were 0.5 of the truck instead of the decided 0.66 (#629); the «bumps» on
  «Кит» 5 were 32 open generator blocks (#632); round fields came from the side-valley floor (#631).
- **R-29 closed.** v1 rejected 17.11, v2 «композиция ок» the same day, Kanta picked the final set 18.11; files in
  `marketing/steam-art-final/`.
- **Balance by package (R-28).** GD-18 went in as one package with Kanta's «да» 17.11 (#623), measured on 48 bot sorties.
- **New tool in an hour.** Earshot: installed, tested on our samples, honest limits («не годится для клона голоса»),
  `check_reel.sh` and the rule in the journal within ~70 minutes on 20.11.
- **Builds still need no PC** (R-26): s19 went cloud → itch.io → Yandex Disk.

---

## 3. What hurts: facts

### 3.1 Work by day

| Day | Commits | Code PRs merged | What happened |
| --- | --- | --- | --- |
| 13.11 (after review) | 0 | 0 | — |
| 14.11 | 2 | 0 | stand-up, marketing status |
| 15.11 | 2 | 0 | stand-up, marketing status |
| 16.11 | 4 | 0 | stand-up, W47 plan, task-observer review (#625) |
| 17.11 | 31 | 7 (#623, #626–#631) | build s19, remarks 1–8, fixes |
| 18.11 | 10 | 3 (#632–#635) | remarks 9–15, models |
| 19.11 | 7 | 5 (#637–#641) | models, fields, cockpits |
| 20.11 | 4 | 0 | earshot, W47, stand-up |

Guess: 14–16.11 was quiet because everything open ended in a question to Kanta (same pattern as 12–13.11). The burst
came the moment he played a build. So the build is the real trigger of work, and remarks are the input that moves the
game fastest.

### 3.2 «Грач» 2 and 3: rounds

| PR | When (UTC) | What | Why the next round |
| --- | --- | --- | --- |
| #634 | 18.11 13:50 | both tiers from Sketchfab «model 4» | further remarks 18.11 (guess from the PR titles) |
| #635 | 18.11 20:01 | «Грач» 3 apart from «Грач» 2 | further remarks 19.11 |
| #637 | 19.11 12:20 | «Грач» 3 fatter, hump | Kanta asked for another source |
| #638 | 19.11 14:14 | «Грач» 3 on a twin-fin canard model | «капец как выбивается… ты же видишь 2 и 4, собери что-то между ними» |
| #641 | 19.11 23:33 | new tier 2 (straight wing), old tier 2 → tier 3, 1.3× wider | after the «как понял» collage; waits for the build |

Each round was a full model pipeline (download, strip insignia, paint, battle model, anchors, tests, PR). The collage
of the whole line «now / as I understood» took ~10 minutes and settled it. Guess: if the lineup collage had come before
#634, two or three rounds would not have happened.

Same week, same shape: «Кит» 5 cockpit (Kanta found the seat boxes himself, #640), «Кит» 1 nose (#632 → #634 → #637).

### 3.3 Remarks on 3.5-s19 (20.11)

| Status | Items |
| --- | --- |
| Fixed in code, wait for the next build | 2, 3, 4, 5, 6, 7, 8 (7 items, 16 PRs incl. rechecks) |
| Handed over, options being prepared | 1 (recipes; #628 merged 17.11 as card-icon formulas) |
| Decided by Kanta 18.11, plan not started | 11 (manoeuvres by crew level), 13 (convoys path-find, AA stands still) |
| Not started, no «готово» for the second batch | 9, 10, 12, 14 |
| Waits for Kanta | 15 (the 18.11 recording is 4.6 s, 104×150 px; a new one is needed) |
| Checked in the game | 0 of 15 |

Item 10 is a broken purchase button: a player in the demo would hit it. It is a bug, not a design question.

### 3.4 Stand-ups

| Day | What was wrong | Effect |
| --- | --- | --- |
| 16.11 | «Треды и модели (не сверял по всем, по памяти)»; links `claude.ai/code/project/...` that open «Не удалось найти этот проект» | Kanta reported it 17.11; links fixed in `kanta-now.md` (16feedd) |
| 20.11 | S6 shown as due «сегодня» although moved to after App ID on 17.11 (04abed90); «решения без исполнителя: не проверял», «модели тредов: не сверял», backlog «Где мы сейчас» not updated (still 18.11) | the first item of the stand-up is a false alarm |

Stand-ups run on the light model (rule of 17.10). Guess: the light model does not have room to read the backlog and the
journal, so it skips the sections the prompt asks for and says so.

### 3.5 Marketing

| Week | Planned | Out | Why not |
| --- | --- | --- | --- |
| W46 (09–15.11) | 5 | 1 (10.11) | every text waits for «ок» |
| W47 (16–20.11) | 5 | 1 (Diary №5, 19.11, after Kanta rewrote it himself) | «Оса» reel, Diary №4, «Оружие в ангаре», «Подвесы и винты» wait for «ок»; previews sent to Kanta's Telegram 19.11 |

- Channel: posts 26–27 never existed between 10.11 and 19.11; last week's proposal 3 (formats without «ок») unanswered.
- R-25 (Sunday numbers): fourth week without numbers.
- YouTube episode 1: animatic waits for «ок», then a RunPod quote (~$1, guess) for «да».

### 3.6 Kanta's words this week (from threads)

| Words | When | Repeat of | What was done |
| --- | --- | --- | --- |
| «при переходе на капсулы и ревью — вот такое» (broken links) | 17.11 | — | links replaced (16feedd) |
| «you already fixed them, didn't you?» («Грач», via coordinator) | 17.11 | 05.11 fixes were partial | thread found only intakes/nozzles had been fixed, not hulls |
| «we discussed they can't hang like that» (bombs on a beam, via coordinator) | 17.11 | no record found in the repo | fixed #632; the decision was never written down |
| Kanta insists the recording is in «Записи экрана» | 18.11 | — | only a 4.6 s file found; asked to record again |
| «т.е. ты считаешь, что эта модель логично ложится…?», «капец как выбивается, ты тупо взял истребитель с 2 килями» | 19.11 | 06.11 «модели должны выглядеть идеально» | collage «как понял», #641 |
| «и вот тут у Кит 5 тебя ничего не смущает?» | 19.11 | — | cockpit rebuilt, #640 |

Two of these («we discussed», «you already fixed») mean a decision or a fix that Kanta remembers and the repo does not.

---

## 4. Game and marketing against the goals (days from 20.11)

| Goal | Date | Where we are | Risk |
| --- | --- | --- | --- |
| Valve review of S1–S3 | ~16.11 | 4 days past, status unknown (only Kanta sees Steamworks) | medium |
| S6 content survey + AI disclosure | after App ID (moved from 20.11 on 17.11) | drafts ready; V-08 unchecked | medium |
| РКН notice (PD-02) | 24.10 | overdue 27 days | medium |
| Steam page «Coming Soon» | end of November | art done 18.11; texts drafted; trailer not made; page waits for App ID | medium |
| Steam integration (GodotSteam, achievements, cloud saves) | before the demo | no task, no plan (second week) | medium |
| CC BY credits for plane models | before the page | at least two Sketchfab CC BY models in the game («Грач» 2 and 3); credits not checked | low, but legal |
| Highlands visuals (priority 1) | — | s19 played, 15 remarks, 7 fixed in code | low |
| Build depth | — | PG-12…PG-17 in s19; recipes reworked (#628) | low |
| Next Fest registration | 10.01.2027 | after Valve | 51 days |
| Demo + page to Valve | 18.01.2027 (Steamworks) | `early-access.md` still says 25.01 | 59 days |
| Next Fest | 22.02.2027 | — | 94 days |
| Wishlists 2 000 | 22.02.2027 | 0 (no page) | depends on the page |
| Telegram | — | 1 post a week, no numbers | medium |

---

## 5. Proposals from the 13.11 review: status

All seven were left without an answer. Status of what happened anyway:

| № | Proposal 13.11 | Status 20.11 |
| --- | --- | --- |
| 1a | «ок» on Steam art | **done** another way: Kanta picked v3 on 18.11 (R-29 closed) |
| 1b | Claude checks V-08 | **not done** (waits for a «да» that never came) |
| 2 | Bug fixes apart from balance | **moot for #623**: Kanta said «да» to the whole package 17.11; the rule itself not adopted |
| 3 | Posts without «ок» for two formats, Sunday numbers | **not done**; 1 post this week |
| 4 | Silence = «не проверено», 5-item check list | not adopted; s19 uses a remarks file instead (works, see 2) |
| 5 | Stand-up shows top 5 asks | not adopted; `kanta-now.md` has 6 dated + 19 undated items |
| 6 | Steam integration plan, demo date 18.01 everywhere | **not done** (fourth review) |
| 7 | PC sessions stay silent | not adopted; no repeat seen this week (guess) |
| R-25 | Sunday marketing numbers | not done, fourth week |
| R-17 | PC allowlist line | still on Kanta's list; builds do not need it any more (R-26) |

---

## 6. New proposals

Numbered so Kanta can answer «1, 3 — да». Each: what changes, effect, what is needed from Kanta.

**1. Steam: Claude closes what is reading work, Kanta takes one look.** Claude (Steam thread) checks V-08 from the
public terms of Meshy and Hunyuan 3D and lists which models in the game came from which tool, writes the S6 answers
ready to paste, and checks that every CC BY model author is in the credits (adds the missing lines). Claude also fixes
the demo date to 18.01 in `docs/process/early-access.md`. Kanta: open Steamworks once and say what the review status is
and whether there is an App ID. Effect: S6 can be typed the day the App ID comes; no legal gap on CC BY.
From Kanta: «да» and one line about Steamworks.

**2. Lineup check before a model PR.** Any new or replaced plane model first goes to Kanta as one collage: the whole line
of that class, tiers 1–5 side by side, top and side, «now / as I understood», and only after his «да» is the model built
and merged. Before saying «ready» the thread also shoots the cockpit and the glass close up (the two places Kanta caught
this week). Effect: one round instead of five; Kanta stops being the inspector. From Kanta: «да» (one line in
`docs/process/working-rules.md` and in the 3D threads' brief).

**3. Bugs from remarks start without «готово».** A remark that is a bug (a button that does nothing, text overlap, a
leftover mark, a hole in a model) goes to its owner thread as soon as it is written down; only design and taste questions
wait for «готово». Start now with s19 items 9, 10, 12, 14, and start the plans for the decided S19-11 and S19-13.
Effect: no two-day wait on a broken purchase button. From Kanta: «да» (changes the project rule «работу начинай после
моего «готово»» for bugs only).

**4. Stand-up on the medium model, with fewer sections.** Move the daily stand-up from the light to the medium model, use
only GitHub and artifact links (no `project?thread=` links), and drop the sections it cannot check (thread models) instead
of writing «не сверял». Effect: the first item of the stand-up is true; Kanta does not chase dead links. Cost: a little
more limit per day (guess: small, one short thread). From Kanta: «да» (changes the 17.10 rule «статусы — лёгкая модель»
for the stand-up).

**5. Remove the task-observer trial.** 9 days, 0 observations, 0 accepted changes; the 19.11 trial review recommends
removal; this review spent 4 tool calls on its protocol. Removal steps are in `docs/process/task-observer-trial.md`.
Effect: less load in every thread, one rule less in `CLAUDE.md`. From Kanta: «да» or «оставь».

**6. Write down what Kanta remembers.** When Kanta says «мы же обсуждали» or «ты же уже исправлял» and the repo has no
record, the thread adds the decision to the journal in the same turn, with «Kanta, restated 17.11». First case: bombs
never hang on a beam under the fuselage; modernised bombs go in the bay (#632). Effect: the next model thread finds the
rule. From Kanta: «да».

**7. Close the 13.11 list.** Keep two items alive: posts without «ок» for «было/стало» and reels (13.11 №3) and the
GodotSteam plan (13.11 №6); close the rest as «не принято». Effect: the review list stops growing. From Kanta: «да» or
the numbers to keep.

**What to take first:** 1 and 3 (Claude can do both today; Steam and a broken button), then 2 (cuts the most rework).
4–7 are cheap.

---

## Decisions

(filled in after Kanta's answer)
