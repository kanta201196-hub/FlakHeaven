# Work review: Kanta and Claude on Flak Heaven (23–30.10.2026)

Weekly review, task R-15 (Kanta's decision 22.10.2026). Format follows `docs/review/2026-10-22-work-review.md`.
Nothing in the game, settings or rules was changed by this review: rule changes below are proposals only, Kanta decides.

**Sources:** `main` history 22.10 20:00 → 30.10 (`a44e8c5`), `docs/game-context.md` decision log, `docs/backlog.md`,
`docs/status-log.md`, `docs/owner-checklist/kanta-now.md`, the project chat 22.10–30.10 (all pages), the thread list
(states), the 30.10 stand-up thread, project memory, `docs/marketing/content/2026-W44.md`, the Telegram bot
(`getChatMemberCount`). Where a number is approximate or a conclusion is a guess, it says so.

---

## 1. Short version

The week shipped a lot: about 180 PRs (#320–#497), five test builds (3.5-s9 on 22.10 evening, s10 23.10, s11 25.10,
s12 26.10, s13 27.10), Forward+ renderer, GPU combat effects, varied Highland relief, new combat HUD and menu, the
«Укрепрайон» activity, the «Битва асов» test mode, 38 medals, decals with an editor, 12 liveries, and the whole
«weak models» list of the Highlands replaced (28–29.10). Backups run twice a week, a code review on 30.10 found and
fixed real bugs (#497).

Five things hurt the most:

1. **Work stops on clicks only Kanta can make on the home PC.** «Разрешить (Allow)» and the permission mode switch
   were asked for on 25.10 (benchmark, three times), 28.10 07:08 and 29.10 13:57 (build s14), 29.10 20:05 (reels).
   Build s14 was ordered on 27.10 19:35; all its work was in `main` by 29.10 13:57, and it is still not built on 30.10.
2. **Builds still outrun verification.** Five builds in five days; s12 → s13 was less than 12 hours apart. Every build was
   ordered by Kanta, so this is not a rule breach by Claude, but nothing tracks what was actually checked in the game:
   EX-01…EX-12, S10-xx and CR-01/02/05 still say «на проверке в следующей сборке» four builds later.
3. **A build went out unchecked once and it cost a day (26.10).** s12: weapon upgrades missing in the hangar, flame in
   the middle of the two-engine «Оса», models «on bricks», bomb tails, the archive reported as uploaded but missing,
   20 minutes and ~25 messages to get a download link. Kanta: «Ты конечно меня разочаровал сегодня…». The self-check
   before a build was promised the same evening and is now part of the s14 thread.
4. **Marketing waits on «ок».** Since 27.10 the plan is one Telegram post a day (Kanta's decision); the last post is
   the trailer of 26.10. Four days of the plan (27–30.10) are missed, all waiting for Kanta's «ок» on captions. The
   devlog (11 issues) waits since 25.10. Telegram: 10 subscribers on 30.10 (9 on 21.10).
5. **The Steam critical path is quiet, and the status files are stale.** Steamworks registration, bank account and tax
   form (S1–S3) are due 01.11, in two days; the last known status is «ищет способ оплаты» from 22.10. The РКН notice was
   planned for 24.10 with no mark since. `kanta-now.md` was not updated for 8 days, `status-log.md` stops at s10, the
   backlog's «Где мы сейчас» is dated 22.10.

Main recommendation: **remove the PC clicks from the build path (proposal 1) and close Steamworks this weekend
(proposal 4)**. Everything else Claude can keep doing at today's pace.

---

## 2. What works well (keep it)

- **Kanta's lists → distribution → PRs within hours.** The 30-item s11 list (25.10 09:45) was distributed in 6 minutes,
  13 items merged by 11:36, 15 by 13:00.
- **«Do it yourself first» is visible.** Threads find the cause before asking: «сено» after blasts was straw in the scorch
  texture, the NAR pulse was «Термобарика», the «teleporting» Fortress was a hit flash.
- **Frames on a page before «ок»** for models (gallery, three graphics presets side by side, «было / стало»). The weak
  models list (10 replace + 18 rework) was done in two days with pages for every step.
- **Rollback is cheap.** Turrets #430 were reverted next day by #448 keeping what Kanta liked (barrel flash).
- **Docs without PR work.** This week about 54 direct doc commits against 21 doc PRs (the week before: almost all docs
  went through PRs).
- **Code review by a second model** (30.10) found a real data bug before it hit profiles: medals and decal tallies
  counted fortresses as aces.
- **Backups** (26.10, #449/#496) twice a week to Google Drive, the project folder and the PC.

---

## 3. What hurts: facts

### 3.1 Waiting on the home PC

| When (UTC) | What waited | For what |
| --- | --- | --- |
| 25.10 04:20–06:51 | FPS benchmark on three presets | «разрешаю запуск», then permission mode «Авто» → «Спрашивать» |
| 25.10 17:20 | big-fight benchmark | Kanta runs a command in the terminal, ~25 min |
| 28.10 07:08 | s14 self-check and export | permission mode + «Разрешить» for Godot |
| 29.10 13:57 → now | s14 self-check and export | «Разрешить» on the home PC (asked again 29.10 18:15) |
| 29.10 20:05 | 4 new reels on the PC | «Разрешить» for `E:\Claude\FlakHeaven` |

Root cause (guess, not verified on the PC): the Claude app on the PC runs in «Авто» mode, which refuses running
`godot.exe` and PowerShell scripts without a prompt, and the prompt only shows when Kanta has the app open.
A one-time allowlist in the PC's Claude settings would remove most of these.

### 3.2 Builds and verification

| Build | Built (approx.) | Gap | Ordered by | Backlog items still «на проверке» after it |
| --- | --- | --- | --- | --- |
| 3.5-s9 | 22.10 19:56 | — | Kanta | EX-01…EX-12 (except EX-05) |
| 3.5-s10 | 23.10 08:49 | 13 h | Kanta «собирай новую сборку» 08:29 | S9-xx |
| 3.5-s11 | 25.10 08:23 | 2 days | Kanta «давай мне тестовую сборку» | S10-01…S10-16, CR-01/02/05 |
| 3.5-s12 | 26.10 ~15:40 | 1 day | Kanta «сливай … и делай сборку» 14:51 | S11 list (30 items) |
| 3.5-s13 | 27.10 night | < 12 h | Kanta «к утру часам к 7 собери» 26.10 20:33 | s12 list |
| 3.5-s14 | not built | — | Kanta 27.10 19:35 | s13 list (19 items) + CR2-01…06 |

- `docs/status-log.md` has no entries for s11, s12, s13. The backlog does not record «checked in the game» for any item.
- Balance «once per build» (rule since 22.10): the s11 cycle carried GD-02, GD-06, GD-08, S11-30 and the Fortress share
  together; the s12 cycle GD-09, ace flares 0.5 and the Fortress phases. Most were Kanta's picks on cards, so allowed,
  but the «one change, then measure» idea of `balance-method.md` did not happen in practice.
- New systems this week while older lists were unverified: «Укрепрайон», «Битва асов», medals, decals + editor,
  liveries round 2. None of them is in the demo scope (DM-01) except possibly medals (guess).

### 3.3 Communication: what repeated (Kanta's own words)

| Complaint | When | Repeat of | What was done |
| --- | --- | --- | --- |
| «Куча тредов в неактивном хотя там есть задачи. Почему?» | 24.10 18:57 | 17–18.10 «треды останавливаются» | hourly push by the coordinator; rule «after a report take the next item» |
| «Только делай сразу качественно… чтобы мы не тратили время на переделки» | 24.10 09:30 | 19.10 «не халтурь» | — |
| Edited a step-by-step message while Kanta was following it | 25.10 08:02 | — | memory `feedback-no-edit-live-instructions` |
| «оборванные скобки в описаниях это вообще как?!!!» | 25.10 09:21 | — | fixed in s11 list |
| «Давай быстро чисть. Ты еще позавчера получал эту задачу» | 26.10 17:34 | — | storage rule ≥ 3 GB free |
| «ты сам проверь есть там сборка в папке» / «дай мне ссылку… цельного» | 26.10 17:41 | 21.10 «уверен, что это тот текст?» | delivery straight to the PC folder (27.10) |
| «ты че мне задачи ставишь… Я тебе говорю что сделать — ты делаешь» | 26.10 17:41 | 21.10 extra question | memory and instructions |
| «Ну ты когда делаешь — думаешь?» (flame between two engines), «Братан проверь ВСЕ кадры сам» | 26.10 18:02–18:05 | 19.10 «не халтурь» | self-check before every build |
| «А зачем ты пытался уложиться в 512?» | 27.10 06:06 | — | full-quality build to the PC folder |
| «Ты о чем вообще» (a tester request read as the build prompt) | 29.10 18:16 | — | — |

Pattern (guess): the repeats are not about missing rules — the rules exist — but about a reply sent before a check
(«build is in the folder», «I'll fix that line») and about the first thing Kanta sees in a build being a visible
defect Claude could have caught by looking at its own frames.

### 3.4 Documents and memory

- `docs/owner-checklist/kanta-now.md`: last update 22.10 (the 30.10 stand-up says so itself).
- `docs/status-log.md`: last entry s10 (23.10). Backlog «Где мы сейчас» is dated 22.10 and still says «все EX пока не начаты».
- Backlog R-10 says «идея» although `balance-method.md` v1 was accepted on 23.10; R-14 says «ждёт запуска» although
  EX shipped in s9 and DM-02…DM-05 were done on 22.10.
- Project memory index `MEMORY.md` is 9.3 KB; recall shows only the first 4 KB (memory rules), so the thread list and
  the marketing section at the end may not reach new threads (guess). Duplicate memories about Russian menu names
  (`menu-names-russian-with-english`, `ui-names-in-russian`) are still both there.

### 3.5 Load and limits

- Commits per day: 23.10 — 73, 24.10 — 114, 25.10 — 104, 26.10 — 87, 27.10 — 76, 28.10 — 30, 29.10 — 7, 30.10 — 5.
  The drop on 29–30.10 matches the s14 wait (3.1) and the end of the models list, not a limit stop (no limit stop was
  reported in the chat this week).
- About 45 new threads this week (several one-off: Meshy key, itch.io key, two threads because a key was not visible
  to an old thread). The six-Opus-threads limit (25.10) was not reported as exceeded.

---

## 4. Game and marketing against the goals

| Goal | Date | Where we are | Risk |
| --- | --- | --- | --- |
| Steamworks S1–S3 (registration, USD account, tax form) | 01.11 | last known: «ищет способ оплаты» (22.10) | **high**, 2 days left, only Kanta |
| Steam Direct $100 (S4) | 10.11 | not marked as paid | **high**, only Kanta |
| РКН notice (PD-02) | planned 24.10 | no mark | medium |
| Steam page «Скоро выйдет» | end of November | texts draft (`steam-page.md`), 36 s trailer (25.10); no capsules; needs S1 | high (depends on S1) |
| Highland visuals «до идеала» (priority 1) | — | weak models list done 29.10, Forward+, GPU effects, relief; not yet seen by Kanta in a build | medium: needs s14 |
| Demo code (DM-02…DM-05) | 30.11–15.12 | done 22.10 (flag `--demo`, end screen, preset) | low |
| Demo content and balance | freeze 01.02 | «Оса» hard at the first ace in s12; many balance changes per cycle | medium |
| Next Fest registration (DM-10) | 10.01.2027 | after Steamworks | 72 days |
| Demo + page to Valve | 25.01.2027 | — | 87 days |
| Next Fest | 22.02.2027 | — | 115 days |
| Wishlists 2 000 | 22.02.2027 | 0 (no page) | depends on the page |
| Telegram | — | 10 subscribers (30.10), last post 26.10 | 4 plan days missed |
| Discord ≥ 25 live by 25.10 | 25.10 | 2 members on 20.10, current count not checked | missed; move the target to the Steam page date |

---

## 5. Proposals from the 22.10 review: status

| № | Proposal 22.10 | Status 30.10 |
| --- | --- | --- |
| 5.1 | One build = one closed cycle, ≥ 1 day between builds | rule in force; in practice 5 builds in 5 days on Kanta's commands, «checked in the game» is not tracked — **partly** |
| 5.2 | Docs without PR | **done** (≈54 direct commits vs 21 doc PRs) |
| 5.3 | Backlog by systems | **done** 22.10; «Где мы сейчас» stale since |
| 5.4 | One-line journal + rules section | **done**; some entries are long again (25–27.10) |
| 5.5 | Project instructions, 15 rules | **done** 22.10, edited 25.10 (6 threads) |
| 5.6 | Self-check before every reply | in instructions; misses on 26.10 and 29.10 — **partly** |
| 5.7 | «Только Kanta» first in the stand-up | **done** in the stand-up; the file itself not updated since 22.10 |
| 5.8 | ≤ 2 strong-model threads | **changed by Kanta** 25.10: ≤ 6 |
| 5.9 | Models by gallery before the build | **done** for models; effects (turrets #430) merged before «ок» and rolled back |
| 5.10 | Balance method | **done** 23.10 (v1 accepted); «one change per build» not kept |
| 5.11 | Coordinator decides once | **done** (no reassign flip-flops seen; checked selectively) |
| 5.12 | Stand-up lines «build cycle» and «days to Next Fest» | **done** |
| 5.13 | Marketing in one thread | **done** 24.10 by Kanta («Объедини треды про маркетинг в 1») |
| 5.14 | Start EX-01…EX-12 and demo code | **done** (EX in s9, DM-02…05 on 22.10); backlog statuses not updated |

---

## 6. New proposals

Numbers are continuous so Kanta can answer «1, 3, 4 — да». Each: what changes, effect, what is needed from Kanta.

**1. Home PC without prompts for builds.** Claude writes a permission allowlist once into the Claude settings on the
home PC (`godot.exe`, the build and bench PowerShell scripts, copying into `E:\Claude\FlakHeaven\builds`), nothing
else. Effect: s14 and later builds, benchmarks and reels stop waiting for a click (this week ≈ 2 days lost).
From Kanta: «да» and one «Разрешить» on the session that writes the settings.

**2. «Checked in the game» as a status.** With every build Claude posts a page «что проверить» (≤ 15 lines, one per
item, with where to look). Kanta answers in one message: numbers that are bad; everything else becomes «проверено в sN»
in the backlog the next day. Effect: the backlog shows what is really closed; the next build starts from a short list,
not from 60 «на проверке». From Kanta: «да», then one message per build.

**3. Marketing posts by the approved plan without a separate «ок».** For posts from the weekly plan Kanta already saw
(«было / стало», frames, reels already approved): published at 12:00 MSK unless Kanta writes «стоп» by 11:00.
Texts in Kanta's own voice (devlog, opinions, replies to people) still need «ок». Effect: one post a day really goes
out (0 posts 27–30.10). This is a standing «yes» for external posts, so only Kanta can decide it.
From Kanta: «да» or «нет».

**4. Steamworks this weekend.** Claude prepares one page: every field of S1–S3 with the values already decided
(Russia, self-employed author, name), the tax form choice, and the legal payment options for the $100 fee from Russia
that Valve accepts (no workarounds of restrictions). Effect: the only high-risk item of the plan gets a 30-minute slot.
From Kanta: one line now — what is done of S1–S4 and the РКН notice, and what blocks (payment?).

**5. Status files refresh themselves.** The daily stand-up thread also updates `kanta-now.md` (dates and statuses from
the chat), the backlog «Где мы сейчас», and adds the build line to `status-log.md` (commit to `main`). Effect: no
8-day-old tables; new threads read the truth. From Kanta: «да» (prompt change of the stand-up routine).

**6. Feel and effects behind a toggle until «ок».** Changes Kanta asked to see before deciding (turret firing, flight
feel, effects) go into `main` behind an F1 or settings toggle that is off by default, and become default after «ок».
Effect: no revert PRs like #430 → #448, the build is never worse than the last one. From Kanta: «да».

**7. Self-check as a script, attached to every build.** The promise of 26.10 becomes a tool: a contact sheet of the
hangar (3 classes × planes × weapons × level 1/3/5/modernised) and combat (nozzles, barrels, pylons, smoke), on a page
attached to the build message. Effect: the 26.10 defects (flame, bricks, bomb tails, missing upgrades) are caught
before Kanta. Code task for the 3D/build thread. From Kanta: «да».

**8. Memory cleanup.** `MEMORY.md` index under 4 KB (details moved into topic files), duplicate «Russian names» memories
merged, backlog R-10 and R-14 statuses fixed. Effect: new threads see the thread list and the latest rules.
From Kanta: nothing, «да» is enough.

**9. Weekly marketing numbers (start R-13 now).** The channels are launched, so R-13 can start: once a week (Sunday)
one line — Telegram subscribers, Discord members, site visitors without bots, tester applications, posts out of plan.
Effect: it becomes visible whether the daily posts give anything before the Steam page. From Kanta: «да».

**What to take first:** 4 (two days to the deadline), 1 (unblocks s14 today), 3, 2. The rest is cheap and can follow.

---

## Decisions

**Kanta 31.10.2026: «По всем пунктам ок»** — all nine proposals accepted. Tasks R-17…R-25 in `docs/backlog.md` (section «Процесс»), journal line 31.10 in `docs/game-context.md`.
