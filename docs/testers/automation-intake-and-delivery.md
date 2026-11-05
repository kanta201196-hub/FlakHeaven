# Automating tester intake and build delivery

Requested by Kanta 2026-11-05. Options and a recommendation only: nothing here is implemented, no accounts were touched, nothing was uploaded. Kanta reviews on 2026-11-06.
Facts marked **(verified)** were read from the repo or the vendor docs today; **(guess)** means from memory or from forum posts and must be checked before we spend time on it.

## 1. Where we are today
| Step | How it works now | Pain |
| --- | --- | --- |
| Applications | Yandex Form https://forms.yandex.ru/u/6ad66df2c45c0770823c7c1e/ (invite is in the YouTube Shorts). Kanta reads the answers by hand (verified: `docs/legal/personal-data.md` PD-01) | Nobody watches the form between visits; no list of who got which build |
| Build | Built in the cloud (`build-cloud-howto`), split into 20 MB parts, carried to the home PC DESKTOP-B28TE7A, glued by `join_sNN.bat`. s16 is 1.7 GB | Several hours of hops; the PC thread is needed every time |
| Delivery | Kanta uploads to Yandex Disk and presses "Share" per person, or uploads to https://kanta2011.itch.io/flak-heaven | Manual, per person; web uploader on itch is capped at 1 GB by default (verified in itch forum posts: 1 GB, 2 GB on request) |
| "New build" signal | Verified: the game fetches `https://flakheaven.com/version.json` (`game/scripts/update_check.gd`) and shows "Вышла сборка …" in the main menu with the itch.io link. Kanta/Claude bump `site/version.json` by hand after upload (`working-rules.md`) | `version.json` still says `3.5-s13`; s16 is out, so testers on s13/s14 are not told |

Constraints: builds only on Kanta's command, at least a day apart; money and external writes only on his "yes"; Steam App ID is not issued yet (tax check, ~01.12); personal data of Russian applicants must first land in a Russian base (152-FZ, why we left Tally; verified in `personal-data.md`).

## 2. Part A. Tracking applications
| № | Option | What it automates | Cost | Needs from Kanta | Risks |
| --- | --- | --- | --- | --- | --- |
| A1 | Status quo + the daily stand-up asks "any new answers?" | Nothing, only a reminder | 0 | Opens the form results himself | Slow, easy to forget |
| A2 | **Form sends an e-mail on every new answer; Claude reads that mailbox (Gmail connector) and keeps a count + queue** | New-applicant alert, daily digest in the stand-up (new / invited / has build), an invitation draft per applicant | 0 | (1) In the form settings turn on e-mail notification for new answers to the Gmail he connected (Yandex Forms has a "send mail" option; verified it exists, exact steps **guess**, see https://yandex.ru/support/forms/ru/send-mail). (2) Say yes to "Claude may read this mailbox for notifications only" | Answers (names, contacts) pass through Gmail, a foreign service. Mitigation: the digest keeps only counts, system and GPU; contacts stay in the mail and the Yandex base. Kanta should confirm this against 152-FZ first (**guess**, not legal advice) |
| A3 | Poll the Yandex Forms API on a schedule | Same as A2 but no mail | 0 | OAuth token as an environment secret | The API may be open only for forms inside a Yandex 360 organization (found in search: "submit via public API only for organization forms"; read side **not verified** for a personal account). Worth a 10-minute check by Kanta before choosing |
| A4 | Replace the first step by self-service: the form's thank-you page shows the private Telegram chat / itch.io link right away | Removes the "invite each person" step completely; applicants get the build link instantly | 0 | Edit the thank-you text in the form; decide whether a link may be public (see B2/B3) | No vetting of who plays; fine for 5 → 50 testers, not for a secret demo |
| A5 | Steam Playtest request-access button | Applicants press "Request access" on the Steam page; Kanta approves in Steamworks | in the $100 already paid | Wait for App ID | Needs the app and playtest page in Steamworks (**guess**: confirm the exact prerequisites there); not before December |

**Recommendation for A: A2 now, A4 as soon as B2 or B3 is chosen, A5 when the App ID arrives.** A3 only if Kanta confirms the API works for his form.

## 3. Part B. Getting new builds to testers
| № | Option | How an update reaches a tester | Cost | Needs from Kanta | Risks / limits |
| --- | --- | --- | --- | --- | --- |
| B1 | Status quo: Yandex Disk "Share" per person | Kanta sends a link per person and per build | 0 | Every build, every person | Does not scale; no list of who has what |
| B2 | **One permanent public Yandex Disk folder link**, `…\builds\latest` synced by the Disk client on the home PC; a PC thread drops each new build there | Tester keeps the same link; the in-game banner (`version.json`) says "new build", they re-download | 0 (free space is limited, **guess** about 5 GB: keep only the latest build per OS) | Create the folder, press "Share" **once**, give the link to Claude, keep the client signed in | Link can leak (regenerate it to revoke); 1.7 GB full re-download each time; Disk throttles very popular files (**guess**) |
| B3 | **itch.io + `butler`** (private or password page, channels `windows`, `mac`, `android`) | The itch app (or page) updates by small patches. Verified: butler uploads only the diff from the last build, the site makes an optimized patch later, repeat pushes of unchanged files are nearly instant; limit is 30 GB total uncompressed per build, no per-file limit in the docs. Web uploader limit 1 GB stays for hand uploads, so upload with butler, not the browser (https://itch.io/docs/butler/pushing.html) | 0 | (1) Create an itch API key (his account), store it as an environment secret `BUTLER_API_KEY`. (2) A standing "yes" for external writes in the form "after I say 'залей sNN' push it". (3) Set the page to private / restricted | A 1.7 GB zip is a single file: some forum posts claim a 2 GB butler cap (**guess**, conflicting); test with a real push, which needs his yes. Patches shrink only if we push an unpacked folder, not a pre-compressed zip (butler unpacks a lone zip itself; verified). Whether itch.io opens freely for testers in Russia is **not checked**; if it does not, B2 stays as the Russian path |
| B4 | **Own storage on Cloudflare R2** (downloads.flakheaven.com), the cloud session uploads the build straight from where it is built | Same stable link, no PC hop at all. Egress is free on R2 (**guess**; verify at https://developers.cloudflare.com/r2/pricing/) | 0 inside the free tier (10 GB storage, **guess**), may need a card on file | Create the R2 bucket and an R2 API token, say yes to the bucket being public. The token proxy-injected for this project currently sees no accounts (checked today: empty list), so a new scoped token is needed | Pages' 25 MB file limit does not apply to R2; a 1.7 GB single upload through the cloud proxy is untested. No patching: full download each time |
| B5 | Game updates itself (in-game downloader of a patch) | Fully automatic, no tester action | Dev time | Yes to a large system (brainstorming → plan → "yes") | Too big for now; Steam will do this for free |
| B6 | **Steam Playtest** (steamcmd/SteamPipe) | Steam installs and auto-updates, delta patches, ban/revoke access | in the $100 | Wait for App ID; yes to publishing the playtest | Not before ~01.12; Mac/Windows depots both possible (**guess**: Android not on Steam) |

**Recommendation for B:** two steps.
1. **This week: B2 as the primary path (everything stays inside Russia, nothing to learn) and B3 as the second path** (best for patch-sized updates and for English-speaking testers, plus it already exists as Kanta's page).
2. **From December: B6**, and then A5 + B6 replace A2 + B2 + B3 for new testers.
B4 is the fallback if the PC hop becomes the bottleneck, because it removes the PC from delivery.

Why not only B3: updates over butler are the nicest, but the single 1.7 GB file and Russian reachability are both unchecked. Why not only B2: no patches and no access control.

### Option T. Telegram bot as the delivery channel (added 2026-11-05 after Kanta's question)
A bot cannot write to a person first: the person must press Start (/start) once. Verified for our own bot: Kanta's chat works since he pressed Start (`reference-telegram-bot-kanta-chat`). Flow:
1. The form's thank-you page (and the Shorts description) shows a link `t.me/<bot>?start=tester`.
2. The tester presses Start; the bot stores their chat id (a personal datum: keep it on a Russian-hosted base or only in the bot's own storage, **guess**, check with `personal-data.md`).
3. After each build the bot sends "new build sNN" + WHATS_NEW + the download link (B2/B3). Claude sends the broadcast by a script using `TELEGRAM_BOT_TOKEN`; Kanta's "yes" for each broadcast.
Limits: the bot sends files up to 50 MB only (verified in `docs/marketing/channels.md` note), so builds go as a link, never as a file. Matching a Yandex Form answer to a Telegram chat is possible only if the tester writes the code from the form to the bot, or we skip matching and treat everyone who pressed Start as a tester. Cost 0; needs a small always-on receiver for /start (Cloudflare Worker, **guess**) or a poll by a scheduled Claude routine (once an hour, no server).
Recommendation: add as the notification layer on top of B2/B3, it replaces "Kanta posts in Telegram/Discord by hand".

## 3a. Standard reply to an applicant (Kanta's text, 2026-11-05)
Claude fills this in for each new application and hands it over as a draft; Kanta (or the bot, option T, after his yes) sends it. Only the link and the folder name change per build or platform.

```
Привет, Это Flak Heaven!
Ты оставлял заявку на тест.

Сборка для Windows: https://disk.yandex.ru/d/51-K79RPT2cO7Q, папка «Test for Win».

Распакуй zip и запусти exe. Буду рад любым впечатлениям и багам прямо сюда 🙏

https://flakheaven.com/
https://www.youtube.com/@FlakHeaven
```
Notes: this is the permanent public Yandex Disk folder of option B2, so it already works as the "one link, replace the files inside" scheme; Mac and Android need their own variants of the Disk line, to be written when those folders exist.

## 4. Part C. Gluing it together (end to end)
```
Yandex Form -> e-mail (A2) -> Claude digest in stand-up -> invite text with the permanent link (B2/B3)
Kanta: "собери sNN"  ->  cloud builds, checks  ->  PC thread copies to Disk 'latest' (B2)
Kanta: "залей sNN"  ->  butler push (B3)       ->  Claude bumps site/version.json, posts to Telegram/Discord
```
- Builds still start only on Kanta's direct command. The only new automation is **after** that command: upload, version bump (`site/version.json`), the Telegram post draft, and the "who is on which build" list.
- The version bump is the quick win: today it is manual, so the banner is a build behind. Claude can bump it in the same step as an upload (commit to `main`, docs/site rule).
- Per-build checklist stays: `make_kit.sh` (checksums, safety note), WHATS_NEW, R-23 hangar/combat self-check.

## 5. What Kanta needs to do (smallest set for the recommendation)
Items by order; each is one action.
1. Form settings → turn on e-mail notification of new answers to the Gmail connected to Claude (A2).
2. Say yes / no to "Claude reads that mailbox for form notifications only; digest keeps no contacts".
3. Yandex Disk: create folder `FlakHeaven-latest`, press "Share" once, send the link (B2).
4. itch.io: create an API key; give it as environment secret `BUTLER_API_KEY` (B3); say whether the standing phrase "залей sNN" counts as the yes to an external write.
5. Later (December): Steamworks playtest (B6) once the App ID arrives.

Open questions for tomorrow:
1. B2 + B3 now and Steam later (recommended), or B2 only, or B4?
2. May Claude read the notification mailbox (A2), or keep the manual check (A1)?
3. Is the applicant list allowed to leave Yandex (affects whether we also keep a tracker sheet)? Recommended: no, counts only.

## 6. Not decided, to verify first
- Per-file limit of butler for one 1.7 GB zip (needs one real push, Kanta's yes).
- Whether Yandex Forms API/webhook exist for a personal form.
- Whether itch.io and Yandex Disk links are reachable from the testers' regions.
- Disk free space, and R2 free-tier terms.
