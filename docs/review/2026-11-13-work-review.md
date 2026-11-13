# Work review: Kanta and Claude on Flak Heaven (06.11–13.11.2026)

Weekly review, task R-15 (Kanta's decision 22.10.2026). Format follows `docs/review/2026-11-06-work-review.md`.
Nothing in the game, settings or rules was changed by this review: rule changes below are proposals only, Kanta decides.

**Sources:** `main` 06.11 14:10 → 13.11 15:31 (`fec0d25b`), merged PRs #590–#624 (GitHub list), `docs/game-context.md`
decision log 06–11.11, `docs/backlog.md` («Where we are» 13.11, R-15…R-33, build lists s14–s16), `docs/status-log.md`
(s17, s18, s18 rebuild), `docs/owner-checklist/kanta-now.md` (13.11), `docs/marketing/content/2026-W46.md`, the thread list
since 06.11 and the threads «Маркетинг и реклама», «Собрать тестовую сборку 3.5-s18», «Пересобрать тестовую сборку
3.5-s18», «Подтянуть слабые сборки оружия», «Сделать капсулы и скриншоты для Steam», «Составить дорожную карту релиза в
Steam», «Сделать красочные сюжетные заставки», project memory. The project chat itself was not read page by page this time
(the history is too long to page from the start), so Kanta's words below come from the threads. Guesses are marked.

---

## 1. Short version

A calmer week on code and a much better one on delivery: **33 PRs merged** (#590–#624, last week 89), two builds
(3.5-s17 06.11, 3.5-s18 08.11, rebuilt 09.11), **both delivered from the cloud with no PC step** (R-26 works: last week
14 asks in 52 minutes, this week 0). Plane tiers 1–5 with their own models, living comic cutscenes, Archipelago rounds 2–4
and the coastal battery, the genre research and five build-depth items (PG-12…PG-17) merged within one day of Kanta's
answers. The GD-18 bot measurement found a real bug (patrol columns stop spawning for «Кит»).

Five things hurt the most:

1. **Work now waits for Kanta, not the other way round.** `kanta-now.md` holds 7 dated items plus **15 undated
   decisions**; the oldest are 7 days old (Steam art R-29, PR #600 two editions). Five threads are «blocked» on him.
   On 12–13.11 no code PR was merged at all.
2. **The Telegram channel stopped.** After the new style (10.11) every post needs Kanta's «ок»: **1 of 5 planned posts**
   went out 09–13.11 (last post 25, 10.11), against one a day last week. R-25 numbers (subscribers etc.) were never
   measured: three Sundays, no line.
3. **Builds are not played, and «проверено» became a formality.** No Kanta remarks on s17 or s18 in the backlog; s18 waits
   for a check for 5 days. The build thread marked s17 «проверено» by the 24 h silence rule (R-30) without anyone playing
   it. Lists s14–s16 (66 items) still have **0 lines «проверено в sN»**; four merged PRs (#619–#622) wait for «a look in
   the next build».
4. **A bug fix is stuck behind a balance decision.** GD-18 found that patrol columns stop spawning after one is left
   untouched (4–7 columns per sortie instead of ~25), but the fix sits in draft PR #623 together with the balance numbers,
   so it waits for the balance «да». Same shape last week with fixes inside feel toggles.
5. **The Steam path has three dates close and two loose ends.** Valve's review ~16.11 (3 days), content survey + AI
   disclosure S6 by **20.11 (7 days)** with V-08 (Meshy and Hunyuan commercial terms) still unchecked and marked «ждёт
   Kanta» although it is reading work; the demo date is 18.01 in Steamworks but **25.01 in `docs/process/early-access.md`
   for the third review in a row**; Steam integration (GodotSteam, achievements, cloud saves) has no task or plan;
   РКН notice overdue 20 days.

Main recommendation: **answer the two Steam items this weekend (proposal 1), and let Claude unblock what does not need
Kanta (proposals 2, 3, 5).**

---

## 2. What works well (keep it)

- **R-26: builds without the PC.** s17, s18 and the s18 rebuild went cloud → `butler push` to itch.io → Yandex Disk
  «upload by URL», checksums from the Disk. Zero «Разрешить», zero .bat, zero PowerShell lines for Kanta.
- **Answers → code in hours.** Genre research decisions 11.11 (06:50 UTC) → PG-17, PG-13, PG-16, PG-12/14 merged by
  11:40 the same day (#619–#622), each with tests.
- **Measure before balance (R-28 in action).** GD-18 ran 48 bot sorties on six variants, found the upper bound
  (+85 % parts is too much) and the real cause (a spawn bug, not bomb damage), and sent one package «было → стало».
- **Stand-up keeps status files fresh (R-21).** `kanta-now.md`, backlog «Where we are» and `status-log.md` are
  updated daily since 08.11, with day counts and guesses marked.
- **Self-check (R-23)** ran on s18: 406 frames, 0 findings, 0 errors.
- **Thread hygiene.** Old threads were resolved in bulk on 08.11 and 13.11; build threads close themselves.

---

## 3. What hurts: facts

### 3.1 Work waiting for Kanta (13.11)

| Waits since | What | Thread / link | Needs |
| --- | --- | --- | --- |
| 24.10 | РКН notice PD-02 | `kanta-now.md` №1 | Kanta files it |
| 06.11 | 7 capsules + 8 screenshots (R-29) | «Сделать капсулы и скриншоты для Steam» | «ок» or list of fixes |
| 06.11 | PR #600 two editions (ED-03/04/08) | GitHub | merge decision |
| 08.11 | Купол and Гром redraw, 2 Figma generations | «Сделать красочные сюжетные заставки» | «да» (credits) |
| 08.11 | cloud GPU for the video render | «Подобрать облачную видеокарту» | «считай» after the animatic |
| 08–09.11 | build 3.5-s18 | `builds/3.5-s18/WHATS_NEW.md` (15 items) | play and list remarks |
| 10.11 | Steam roadmap, early access option B | «Составить дорожную карту релиза в Steam» | choose A / B / C |
| 11.11 | 5 posts in Word (Diary №4, №5, «Оружие в ангаре» …), reel «Оса» | «Маркетинг и реклама» | «ок» or fixes |
| 11.11 | in-combat album frames (PG-16) | «Сделать альбом сборок в бою» | look and fixes |
| 12.11 | «Кит» bomb package + spawn bug fix (GD-18, PR #623) | «Подтянуть слабые сборки оружия» | «да» on the package |
| — | S6 content survey (due 20.11), Next Fest, demo | Steamworks | Kanta types it in |

Code PRs merged per day: 06.11 (evening) 13, 07.11 8, 08.11 3, 09.11 2, 10.11 1, 11.11 5, 12.11 0, 13.11 0 (docs only).
Guess: the drop is not lack of work; most open work now ends in a question to Kanta.

Last week's proposal 2 (one daily list of asks) was not adopted («не критично»). The list exists anyway in
`kanta-now.md`, but it has no order: a 7-day-old Steam item sits next to a camouflage «ок».

### 3.2 Marketing

| Week | Planned posts | Out | Why not |
| --- | --- | --- | --- |
| W45 (02–08.11) | 8 | 8 | R-19: posts by plan unless «стоп» |
| W46 (09–13.11) | 5 | 1 («Кишлак и река», 10.11, late, on Kanta's command) | new style 10.11: every text waits for «ок» |

- Kanta 10.11: «посмотри исправленные тексты в канале и сделай выводы, пишешь херню, как будто мне комментарии даешь».
  Then «еще раз: изучи как минимум 15 каналов…» — the first answer was a summary of his own edits, not the study he asked
  for. The style study (23 channels) was done the same evening.
- Kanta 10.11: «стоп, ты че вслух читаешь посты…» — a Remote Control session on the PC played speech while studying
  channels; the cloud thread could not stop it, Kanta had to.
- R-25 (weekly numbers on Sunday): the W45 and W46 plans have the heading, no numbers. Not done for the third week.

### 3.3 Builds and checks

| Build | Ordered (UTC) | Kanta remarks in backlog | «проверено в sN» |
| --- | --- | --- | --- |
| 3.5-s17 | 06.11 11:44 | none | set by silence (R-30) on 08.11, nobody played it (guess from the s18 thread) |
| 3.5-s18 | 08.11 06:16 | none | — |
| 3.5-s18 rebuild | 09.11 14:05 («не успел проверить» s18) | none so far | — |

- Sections «Правки по сборке 3.5-s14 / s15 / s16» (66 items) are still in the live backlog, 0 marked «проверено».
- The R-30 rule «silence 24 h = проверено» turns «not played» into «checked». That makes the stand-up number «закрыто X
  из Y» look better than it is.

### 3.4 Fixes tied to decisions

| Fix | Found | Waits for |
| --- | --- | --- |
| Patrol columns stop spawning after one is left untouched (GD-18) | 12.11 | balance «да» on the same PR #623 |
| Column vehicles take the drone cap, cannon «Кит» loses ~45 % damage (GD-18) | 12.11 | same |

Both are bugs (the game does not do what the rules say), not balance. Hard rule 2 covers balance numbers; a bug fix
that restores the written rule does not need to wait. Guess: the thread bundled them to keep one PR.

### 3.5 Kanta's words this week (from threads)

| Words | When | Repeat of | What was done |
| --- | --- | --- | --- |
| «пишешь херню, как будто мне комментарии даешь» | 10.11 | 17.10 «простыми словами»; 06.11 «непонятные описания» | style study, new rule: caption for the viewer, no notes to Kanta |
| «еще раз: изучи как минимум 15 каналов…» | 10.11 | same evening, first ask | 23 channels studied |
| «стоп, ты че вслух читаешь посты» | 10.11 | — | PC session stopped |
| «Картинка и лицо "Купола" слишком реалистичное» | 08.11 | 06.11 art bar | redraw proposed, waits for credits «да» |
| s18 «не успел проверить», rebuild under the same number | 09.11 | — | rebuilt as s18 |

---

## 4. Game and marketing against the goals

| Goal | Date | Where we are | Risk |
| --- | --- | --- | --- |
| Steamworks S1–S4 | done 01.11 | Valve review ~16.11 (tax check up to 30 days, ~01.12) | low |
| S6 content survey + AI disclosure | **20.11 (7 days)** | drafts ready; V-08 terms not checked | **high** |
| РКН notice (PD-02) | 24.10 | overdue 20 days | medium |
| Steam page «Coming Soon» | end of November | texts draft, capsules and screenshots v1 ready 06.11, wait for «ок» 7 days; English trailer not made | **high** |
| Steam integration (GodotSteam, achievements, cloud saves) | before the demo | no task, no plan | medium (the roadmap thread flags it as one of two date risks) |
| Highlands visuals (priority 1) | — | tiers 1–5 models in, comic cutscenes in; s17/s18 not looked at by Kanta | medium |
| Archipelago | — | rounds 2–4 + coastal battery merged; «one doc of all models» ready for review | low |
| Build depth (priority 04–05.11) | — | PG-12…PG-17 merged 11.11, first look in the next build | low |
| Next Fest registration | 10.01.2027 | after Valve | 58 days |
| Demo + page to Valve | 18.01.2027 (Steamworks) | `early-access.md` still says 25.01 | 66 days |
| Next Fest | 22.02.2027 | — | 101 days |
| Wishlists 2 000 | 22.02.2027 | 0 (no page) | depends on the page |
| Telegram | — | 1 post this week; no subscriber numbers | medium |
| YouTube series | — | episodes 1–2 animatics ready, episode 1 on Kanta's own voice waits for «одобряю» | — |

---

## 5. Proposals from the 06.11 review: status

| № | Proposal 06.11 | Task | Status 13.11 |
| --- | --- | --- | --- |
| 1 | Builds never go through the PC | R-26 | **done**, s17 and s18 delivered from the cloud |
| 2 | One list of asks a day | R-27 | not adopted (Kanta); the asks pile up anyway, see 3.1 |
| 3 | Balance = one package per build | R-28 | **done**, rule changed; GD-18 is the first package |
| 4 | Steam page art now | R-29 | **made 06.11**, waits for Kanta's «ок» 7 days |
| 5 | Build cycle you can count | R-30 | **partly**: rule written, used once (s17) as «silence = checked» without play; s14–s16 not closed |
| 6 | Clean-up of routines and statuses | R-31 | **done** 06.11 |
| 7 | Russian-language guard | R-32 | **done**; no English reply seen this week |
| 8 | Opus for weapons and numbers | R-33 | **done**; no filter stop this week |
| 30.10 №1 | PC allowlist | R-17 | no longer needed for builds (R-26); line for `tools/pc/*.ps1` still on Kanta's list |
| 30.10 №9 | Weekly marketing numbers | R-25 | **not done**, third week |
| R-16 | Superpowers: repo or plugin | R-16 | open, no decision (guess: no longer relevant, skills live in the repo and work) |

---

## 6. New proposals

Numbers are continuous so Kanta can answer «1, 3 — да». Each: what changes, effect, what is needed from Kanta.

**1. Two Steam answers this weekend.** (a) «ок» or fixes on the capsules and screenshots
(https://claude.ai/artifact/DHNSFkG2NJg1oBb66WDbiH); (b) Claude checks V-08 itself by Monday 16.11 (public terms of
Meshy and Hunyuan 3D, which models in the game came from which, one page with the S6 answers ready to paste), so Kanta
only types S6 in before 20.11. Effect: the page can go to Valve the day the review passes; no miss on 20.11.
From Kanta: (a) «ок»; (b) «да».

**2. A bug fix does not wait for a balance «да».** If a measurement finds that the game breaks its own written rule (a
spawn that stops, a cap that eats another system's budget), the fix is merged at once as a separate PR; only the new
numbers wait in the balance package. First case: split PR #623 — the two column fixes now, the 20 s / 2 columns /
5 vehicles package after Kanta's answer. Effect: bugs stop riding on decisions. From Kanta: «да» (adds one line to
CLAUDE.md hard rule 2: «a fix that restores a written rule is not a balance change»).

**3. Posts go out again without «ок» for two formats.** «Было/стало» pairs and reels with only a build tag and 1–3 lines
of what is in the frame (the 10.11 style) go out by plan at 12:00 МСК unless «стоп» by 11:00 (R-19 as it was).
Diaries and anything in Kanta's voice keep waiting for «ок». The marketing thread also posts the R-25 numbers itself on
Sunday (subscriber count through the bot, tester applications from the bot log, posts out vs plan). Effect: the channel
does not stand for a week while texts wait; numbers exist. From Kanta: «да».

**4. «Проверено» only after play.** Change R-30: 24 h of silence after a build means «не проверено», not «проверено».
Each build gets a 10-minute list of 5 things to look at (not 15) with a one-word answer «всё ок» or numbers. The old
s14–s16 sections move to `backlog-archive.md` with «перенесено без проверки» except items Kanta names. Effect: the
backlog tells the truth; the next build list is short enough to be checked. From Kanta: «да», then «всё ок» or numbers
on the s18 list when he has played it.

**5. Ordered list instead of a pile.** Not a daily message (that was declined): the stand-up sorts the «Ждёт решения
Kanta» part of `kanta-now.md` by deadline and cost of waiting, shows only the top 5 with one-word answers and Claude's
default, and moves the rest under «можно позже». Effect: one look tells what matters today; the 7-day-old Steam item is
never below a camouflage «ок». From Kanta: «да» (Claude changes the stand-up section; the routine prompt needs a paste
only if the coordinator cannot edit it).

**6. Plan for Steam integration now.** Brainstorming → plan for GodotSteam on Godot 4.4.1 (achievements, cloud saves,
overlay, demo App ID), shown to Kanta before any code; code starts after the App ID. Also fix the demo date to 18.01 in
`docs/process/early-access.md` (Steamworks is the source). Effect: the second date risk named in the roadmap thread gets
an owner; one date in all docs. From Kanta: «да» on the plan work (the plan itself comes later for its own «да»).

**7. PC sessions stay silent.** A Remote Control session never plays audio, video or speech on Kanta's PC unless the
task is a sound check he asked for, and says so before it starts. Effect: no repeat of 10.11. From Kanta: «да» (one
line in `docs/process/working-rules.md` and in the Remote Control briefs).

**What to take first:** 1 (two Steam dates in 3 and 7 days), 2 (the bug fix is ready), 3 (the channel is silent).
4–7 are cheap and Claude can do them the same day.

---

## Decisions

(filled in after Kanta's answer)
