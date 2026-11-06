# Work review: Kanta and Claude on Flak Heaven (30.10–06.11.2026)

Weekly review, task R-15 (Kanta's decision 22.10.2026). Format follows `docs/review/2026-10-30-work-review.md`.
Nothing in the game, settings or rules was changed by this review: rule changes below are proposals only, Kanta decides.

**Sources:** `main` history 30.10 15:00 → 06.11 14:10 (`6c3357a`, 220 commits), `docs/game-context.md` decision log
(31.10–06.11), `docs/backlog.md` (R-15…R-25, build lists s14–s16), `docs/status-log.md`, `docs/owner-checklist/kanta-now.md`,
`docs/marketing/content/2026-W45.md`, `docs/marketing/steam-launch-checklist.md`, the project chat 31.10–06.11 (all pages),
the thread list since 30.10, the scheduled tasks list, project memory. Where a number is approximate or a conclusion is a
guess, it says so.

---

## 1. Short version

The biggest week so far on content: 89 PRs (#499–#589), four test builds (3.5-s14 31.10, s15 04.11, s16 05.11, s17 being
built 06.11), the full Highlands story (10 steps + comic art and portraits), weapon profiles and second modernisations
(PG-06), build depth (archetypes, synergies, build album, trade-off cards, «Долгий вылет»), operation objectives,
«Подготовка и вылет», real numbers in the hangar, the Archipelago back in work. **Steamworks was paid and sent on 01.11**
(the only high-risk item of last week). Marketing posts went out every day by the plan (R-19 works), the first two outside
testers came in on 05.11, the tester bot answers instantly, builds go to Yandex Disk without Kanta.

Five things hurt the most:

1. **Kanta is still the courier between the cloud and the home PC.** On 05.11 between 20:05 and 20:57 UTC the chat sent
   him **14 «Нужно от тебя» messages in 52 minutes** (drag a zip, copy a link, PowerShell for itch.io, butler login,
   «Подключить», «Разрешить», run a .bat, check a SHA). His words at 20:40: «бесишь...». Today s17 again stops on
   «Разрешить» (14:29). R-17 (PC allowlist) is still open and now sits on Kanta's list.
2. **Builds go out faster than the «checked in the game» loop.** s16 (05.11 ~17:00) → s17 order (06.11 11:44) is
   ~19 h, under the «≥ 1 day» rule; `kanta-now.md` itself says «следующая не раньше 07.11». Of 66 items in the s14–s16 lists
   none is marked «проверено в sN» (R-18 used once). All builds were Kanta's own orders, so this is not a breach by
   Claude, but the backlog cannot tell what is really closed.
3. **«One balance change per build» is not how we work any more.** The s15 cycle carried GD-14/15/16 + MO-01 + PG-11;
   the s16 cycle the plane-2 price, start rerolls/bans, bunker and fort HP, node prices ×2 and rarity on rank cards.
   Every one had Kanta's «да», so it is allowed, but CLAUDE.md hard rule 2 and `balance-method.md` say otherwise, and
   nobody can tell which change moved the numbers in the next log.
4. **Status files and routines lag behind decisions.** `status-log.md` still ends at s10 (23.10); backlog «Где мы сейчас»
   is dated 31.10 and says the last build is s13; the stand-up prompt v2 (R-21) is not in the routine (its text still
   says «R-01…R-15» and «демо 25.01»); the old twice-weekly backup routine still runs on Mon/Fri after Kanta's 06.11
   «другую задачу по бэкапу убирай»; the Steam thread is shown as «ждёт Kanta» while it waits for Valve's App ID.
5. **The Steam page is the next critical path and has not started.** Target «Coming Soon» end of November (~3.5 weeks):
   no capsules (7 required), no screenshots, game-name check not finished, AI survey blocked on Meshy/Hunyuan commercial
   terms (V-08), РКН notice overdue 13 days. Valve's review (~16.11) will open page editing; the art can be made now.

Main recommendation: **take the PC out of the delivery path (proposal 1) and start the Steam page art now (proposal 4).**
Everything else is cheap.

---

## 2. What works well (keep it)

- **Steamworks done on time** (01.11, $100 paid, documents sent) after the one-page fill-in guide (R-20).
- **R-19 works.** Posts went out every day 02–06.11 (messages 17–22 of the channel, `2026-W45.md`), including three s13
  reels that waited since 27.10. Last week: 0 posts in 4 days.
- **Kanta's lists → PRs within hours.** The s16 list (17 items, 05.11 20:05) was split, approved and merged by 06.11 07:17
  (#564–#570); the 06.11 morning asks (prep & sortie, op art, objectives, distances, real stats, bank) were merged by
  ~11:00 (#573–#581).
- **Feel and effects behind toggles (R-22)**: s15 items 9–12 shipped off, Kanta said «ок», then on by default (#561).
  No revert PRs this week.
- **Self-check contact sheet (R-23)** shipped 31.10 (#521) and is in every build folder (`builds/3.5-s16/selfcheck/`).
  No «flame between engines» type complaint about a fresh build this week.
- **Automation removed manual steps:** Yandex Disk upload by Claude (06.11), daily backup to Disk (#571/#572), tester bot
  with instant «Старт» via Cloudflare (06.11).
- **Docs straight to `main`** keep working (~60 direct doc commits).

---

## 3. What hurts: facts

### 3.1 Kanta's hands in the build and delivery path

| When (UTC) | What waited | Kanta's action |
| --- | --- | --- |
| 31.10 09:47, 09:59 | s14 export | «Разрешить» + a permanent rule on the PC |
| 03.11 17:44 | s15 export | allow export on the PC |
| 04.11 09:43 | s15 check | run `FlakHeaven.exe`, read the number |
| 04.11 16:16 | full backup | connect the PC |
| 05.11 14:12 | s16 to the PC | enable the PC in Claude |
| 05.11 16:57, 18:22 | s16 archive | run `join_s16.bat` (asked twice, second time with a new file name) |
| 05.11 20:08–20:57 | s16 videos, Disk, itch.io, Mac | «Разрешить», drag zip to YandexDisk, copy link, butler login, PowerShell line, «Подключить», «Разрешить», run `join_s16_mac.bat`, check SHA |
| 06.11 04:52 | s16 Mac on itch.io | PowerShell line, hide two s11 uploads by hand |
| 06.11 14:29 | s17 delivery | «Разрешить» on Remote Control |

Root cause (partly verified): builds are made in the cloud, but the cloud cannot write big files to the PC or publish on
itch.io, so every build is moved in 20 MB pieces and glued by a .bat on the PC. Yandex Disk upload from the cloud works
since 06.11, so the PC is no longer needed for the Disk; itch.io (butler) and the allowlist are what is left.

### 3.2 Builds and verification

| Build | Ordered (UTC) | Ready (approx.) | Gap to previous | List after it | Items «проверено в sN» |
| --- | --- | --- | --- | --- | --- |
| 3.5-s14 | 31.10 09:46 | 31.10 13:59 | 4 days | 22 (S14-xx) | 0 |
| 3.5-s15 | 03.11 16:40 | 04.11 09:43 | 3 days | 13 (S15-xx) + AB-02…08 | 0 |
| 3.5-s16 | 05.11 12:27 | 05.11 ~17:00 (Mac 20:56) | 1.3 days | 31 (S16-xx) | 0 |
| 3.5-s17 | 06.11 11:44 | built in the cloud, delivery waits | ~19 h | — | — |

- The «что проверить» page was made for s14 (31.10, artifact Q2AKgd9VCCB5KFd8HpWSS3); for s15/s16 only `WHATS_NEW.md`.
  Nobody turned the silence after the page into «проверено в s14» the next day, as R-18 says.
- `docs/status-log.md`: no lines for s11–s16.

### 3.3 Balance changes per cycle

| Cycle | Changes (all with Kanta's «да») |
| --- | --- |
| s15 | i-frames 0.7 → 0.55 s, wave cap ×1.5 → ×1.8, cards after level 30 every second level, «Долгий вылет», PG-11 archetypes and synergies |
| s16 | plane 2 price 50 000, start rerolls/bans 3/1, bunker and fort HP (floor 3/6/20 s), node prices ×2, rarity on rank and «Э+» cards |

The rule «баланс не чаще раза за сборку» (CLAUDE.md hard rule 2, project instructions) was written to make the next log
readable. In practice Kanta decides 3–6 balance items per build. Either the rule or the practice should change.

### 3.4 Communication: what repeated (Kanta's own words)

| Complaint | When | Repeat of | What was done |
| --- | --- | --- | --- |
| «опять вижу проблемы с крыльями в ангаре. Ты можешь нормально все модели проверить?» | 31.10 14:50 | 26.10 «проверь ВСЕ кадры сам» | full player-plane pass (#527, #531–#537, #540, #541, #556) |
| «Окраски … посредственно … должны быть четкими» | 31.10 14:52 | — | camo rework, 4 per plane (#527, #551) |
| «бесишь...» (after «бот не может написать первым») | 05.11 20:40 | 26.10 «дай мне ссылку… цельного» | tester bot with instant reply (06.11), Disk upload by Claude |
| «А ты с бота написать не можешь?» / «как мне написать от имени канала?» | 05.11 20:40 | — | bot in the form and video descriptions |
| «а ты с каких пор англичанином стал?» (coordinator answered in English 3 times) | 06.11 11:32 | 16.10 «Общаемся на русском» | apologised, back to Russian |
| «что такое к профилю? непонятные описания» | 06.11 08:03 | 17.10 testers «слова непонятны» | descriptions rewritten in numbers (#578, #585) |
| «В каких тредах и что от меня сейчас надо?» | 06.11 08:40 and 11:43 | 03.11 04:18 «Что ждешь от меня?» | answered by hand each time |

Pattern (guess): the asks are not collected in one place. Each thread posts its own «Нужно от тебя» into the chat, so
Kanta gets many small asks at once and has to ask «what do you need from me» three times in four days.

### 3.5 Threads and models

- ~40 threads were started this week; many one-off (logo, distances, library clean-up, Disk access check).
- The Fable safety filter stopped the progression thread twice on 31.10 (weapon modernisation read as real weapons); Kanta
  chose «try Fable again», it failed again, the work moved to Opus the same evening. About 3 hours lost (guess).
- Two threads report «blocked» on things that do not need Kanta: «Составить список для выхода в Steam» (waits for Valve's
  App ID), «Замедлить выход самолёта из крена» (waits for an «ок» that is already in kanta-now as an F1 check).

---

## 4. Game and marketing against the goals

| Goal | Date | Where we are | Risk |
| --- | --- | --- | --- |
| Steamworks S1–S4 (registration, $100, bank, tax) | 01–10.11 | **done 01.11**, Valve review ~16.11 (up to 30 days for tax) | low |
| Steamworks content survey + AI disclosure (S6) | 20.11 | drafts ready; AI answer needs V-08 (Meshy/Hunyuan terms) | medium |
| РКН notice (PD-02) | 24.10 | overdue 13 days, only Kanta | medium |
| Steam page «Coming Soon» | end of November | texts draft, trailer 36 s (25.10); **0 of 7 capsules, 0 screenshots**; name check partial | **high** |
| Highlands visuals «до идеала» (priority 1) | — | player planes, camo, hangar, weapon store, effects reworked; quality bar written down 06.11 (`docs/standards/art-quality-bar.md`) | medium: needs Kanta's look in s17 |
| Archipelago (2nd biome) | — | restarted 06.11, first models at the Highlands bar (#589) | medium |
| Build depth (Kanta 04–05.11 priority) | — | archetypes, synergies, album, trade-off cards, «Долгий вылет» merged 05.11; first test in s16/s17 | low |
| Next Fest registration (DM-10) | 10.01.2027 | after Valve review | 65 days |
| Demo + page to Valve | 18.01.2027 (Steamworks) / 25.01 (`early-access.md`) | dates differ in two docs | 73 / 80 days |
| Next Fest | 22.02.2027 | — | 108 days |
| Wishlists 2 000 | 22.02.2027 | 0 (no page) | depends on the page |
| Telegram | — | one post a day kept 02–06.11; subscriber count not measured this week (R-25 first numbers due 08.11) | — |
| YouTube | — | Short «Мне запрещали играть ночью»: 1 311 views, 59 % stayed, +9 subscribers in ~6 h (06.11); links in descriptions locked for new channels | — |
| Outside testers | — | 2 requests (05.11), builds sent; bot live | — |

---

## 5. Proposals from the 30.10 review: status

| № | Proposal 30.10 | Task | Status 06.11 |
| --- | --- | --- | --- |
| 1 | PC allowlist for builds | R-17 | **not done**: the line for `settings.json` is on Kanta's list since 03.11; this week 10+ PC asks (3.1) |
| 2 | «Что проверить» page, silence = «проверено в sN» | R-18 | **partly**: page for s14 only; no item marked «проверено» |
| 3 | Posts by plan unless «стоп» | R-19 | **done**, works (daily posts 02–06.11) |
| 4 | Steamworks this weekend | R-20 | **done** 31.10 page, Kanta paid and sent 01.11 |
| 5 | Stand-up refreshes status files | R-21 | **partly**: `kanta-now.md` refreshed daily; `status-log.md` and «Где мы сейчас» not; prompt v2 not pasted |
| 6 | Feel and effects behind a toggle | R-22 | **done** (s15 9–12, wingman, bank, fx_s16, msl_s16) |
| 7 | Self-check script | R-23 | **done** 31.10 (#521), used in s14–s17 |
| 8 | Memory cleanup | R-24 | **done** 31.10; `MEMORY.md` is again ~7.6 KB (over the 4 KB recall window) |
| 9 | Weekly marketing numbers (Sunday) | R-25 | **not seen yet**: no numbers on 01.11; planned for 08.11 |
| R-16 | Superpowers: repo or plugin | R-16 | open, no decision |

---

## 6. New proposals

Numbers are continuous so Kanta can answer «1, 3, 4 — да». Each: what changes, effect, what is needed from Kanta.

**1. Builds never go through the PC.** Every build goes from the cloud straight to Yandex Disk («Test for Win» / «Test for
Mac», old ones deleted — already allowed 06.11) and to itch.io via butler from the cloud with an itch.io API key in the
environment secrets. The PC is used only for bench and recordings. Effect: no .bat gluing, no PowerShell lines, no
«Разрешить» for a build (≈ 14 asks on 05.11 alone). From Kanta: «да», and once: create an itch.io API key
(itch.io → «Настройки (Settings)» → «Ключи API (API keys)») and put it in «Сетевые секреты (Network secrets)»; Claude
gives the exact field values.

**2. One list of asks, once a day.** Threads stop posting «Нужно от тебя» into the chat one by one. They put the ask into
`kanta-now.md` (section «Ждёт ответа Kanta»), and the coordinator sends **one** message at most twice a day (morning and
the 17:00 stand-up) with a numbered list; urgent things only (a build waiting, a deadline today) go out at once. Effect:
Kanta answers «1 да, 2 нет, 3 ок» once instead of 10–14 separate pings, and never has to ask «что от меня надо».
From Kanta: «да».

**3. Balance: one package per build instead of one change.** Replace «баланс не чаще раза за сборку» with: all balance
changes of a cycle go into one numbered package (one journal line, one PR or PR series), each change logged with
«было → стало», and the next build's log is read against the package. Effect: the rule matches how Kanta decides, and logs
stay readable. From Kanta: «да» (changes CLAUDE.md hard rule 2 and the project instructions line).

**4. Steam page art starts now.** Before Valve opens the page (~16.11): 7 capsules (header, small, main, vertical,
library capsule, library header, library hero) from the existing key art and Forward+ frames, 8 screenshots on all three
classes, shown on one page for «ок». No paid generators. Effect: the page can be filled the day Valve approves, «Coming
Soon» by end of November stays real. From Kanta: «да», then «ок» on the page.

**5. Build cycle you can count.** With every build: the «что проверить» page (≤ 15 lines) is attached to the build
message; 24 h after Kanta's first message about the build, items he did not flag become «проверено в sN» in the backlog,
and the build list is archived. `status-log.md` gets one line per build from the build thread itself (not the stand-up).
Effect: «закрыто X из Y» in the stand-up becomes a real number; s14–s16 lists (66 items) get closed. From Kanta: «да».

**6. Clean up routines and statuses (Claude does it).** Turn off the old twice-weekly backup routine (Kanta 06.11
«убирай»; daily Disk backup replaces it); put the stand-up prompt v2 into a text Kanta can paste in one go, with the
dates fixed (demo 18.01 by Steamworks); mark «Составить список для выхода в Steam» as waiting for Valve, not Kanta; trim
`MEMORY.md` under 4 KB again. Effect: no duplicate work, true statuses. From Kanta: «да» (and one paste of the prompt).

**7. Language guard for the coordinator.** Add one line to the project instructions: «Если ответ получился на английском —
перепиши по-русски до отправки», and the coordinator's own check before each reply. Effect: no repeat of 06.11 (three
English replies). From Kanta: «да».

**8. Fable only for text, Opus for weapons and numbers.** Weapons, damage and upgrade work starts on Opus directly
(the Fable filter stopped such work twice on 31.10); Fable stays for story, texts and art direction. Effect: no lost
evenings to a filter. From Kanta: «да».

**What to take first:** 1 (removes most of Kanta's manual work), 4 (the Steam page is the next deadline), 2, 5.
6–8 are cheap and can go the same day.

---

## Decisions

**Kanta 06.11.2026 (20:16 MSK):** 1 «Да, проверь где узкое место и устрани его» (R-26); 2 «не критично» — not adopted (R-27);
3 «Согласен» (R-28, rule changed); 4 «Запускай» (R-29); 5 «Ок» (R-30); 6 «Да, делай» (R-31); 7 «Да» (R-32);
8 «Почему?» — answered in the thread, then «Ок» (R-33). Journal line 06.11 in `docs/game-context.md`.

Bottleneck for №1 (measured 06.11 from the cloud): Cloudflare upload ~10 MB/s, Google storage ~18 MB/s, Yandex Disk direct
PUT 0.25–0.6 MB/s with a 502 at ~30 s on 8 MB and 20 MB files; Disk «upload by URL» pulled a 50 MB test file in seconds.
butler download host `broth.itch.ovh` is refused by the network policy; `ITCH_API_KEY` is already in the environment.
