# Steam launch checklist (Early Access)

Written 2026-11-01 (thread "Составить список для выхода в Steam"). Requirements were read from the Steamworks docs on 2026-11-01 (links in section 9); anything not found there is marked **[verify in Steamworks]** or **[guess]**. Status: **ready / partial / missing**. Owner: **Claude** (can do alone), **Kanta** (only Kanta: account, clicks in Steamworks, money, legal), **both**.

Companion page for Kanta (Russian): published as an artifact; this file is the source of truth.

## 0. Corrections to our earlier docs (important)
1. **Next Fest review deadlines are earlier than we wrote.** Valve's Feb 2027 page: demo build + store page for review by **2027-01-18** (to be live for Press Preview 02-11); everything else by **2027-02-01**. `docs/demo-next-fest.md` and the backlog say 25.01 / 08.02. Treat **18.01 and 01.02** as the real deadlines.
2. **Capsule sizes changed** (Valve: "old dimensions are no longer accepted" since Aug 2024). `docs/marketing/steam-page.md` §6 lists the old 616x353 main capsule; the current ones are in §3 below.
3. **Tax check can take up to 30 days** (not 15): Valve onboarding page. Our "~16.11" is the optimistic case; plan for up to ~01.12.
4. **Early Access: no specific promises about future content** (Valve rule). `steam-page.md` §5 ("Что добавим": more biomes, weapons, languages) must be reworded as intent, not promises.
5. **AI disclosure must also cover the Figma-generated story art** (9 comic pictures, #535, 2026-11-01); `steam-page.md` §8 does not list it yet. Steam's survey covers shipped content only (art, sound, narrative, localization), not AI used as a dev tool (so Claude-written code is not in scope).

## 1. Timeline (hard Valve rules + our dates)
| Date | What | Source |
| --- | --- | --- |
| ~16.11 – ~01.12 | Valve identity/tax verification finishes (up to 30 days for tax); only then store page editing opens | onboarding doc |
| 22.11 | Earliest possible release (21 days after paying the fee, first titles) - not a concern for spring | onboarding doc |
| end of Nov (target) | Store page submitted -> "Post as Coming Soon". Review 3-5 business days; submit **>= 7 business days** before the wanted live date | review process, coming soon docs |
| 08.12 10-11 PST | Valve Next Fest Q&A (Zoom, optional) | nextfest feb_2027 |
| **10.01 23:59 PST** | **Next Fest registration deadline** (register the base game, not the demo). Trailer and store art should be final by then | nextfest feb_2027 |
| **18.01** | Valve pulls trailers for the fest trailer; **demo build + store page submitted for review** (for Press Preview) | nextfest feb_2027 |
| **01.02** | Last day to submit everything required for the fest | nextfest feb_2027 |
| 11.02 10:00 PST | Press Preview starts; last day to opt out of trailer use | nextfest feb_2027 |
| **22.02 10:00 PST (21:00 MSK)** | Next Fest starts; demo must be live **>= 30 min** earlier | nextfest docs |
| 01.03 10:00 PST | Fest ends, wrap-up | nextfest feb_2027 |
| spring 2027 (plan) | Early Access release; page must have been "Coming soon" **>= 2 weeks**; page and build both reviewed (each plan >= 7 business days) | releasing doc |

## 2. Account and legal
| Item | Status | Owner |
| --- | --- | --- |
| Steamworks registration, $100 app fee, tax + bank forms | ready (sent 01.11, Valve review pending) | Kanta |
| Account permissions "Publish app changes" and "Manage pricing and discounts" on the app | missing (after approval) | Kanta |
| Game name final - **cannot be changed after pre-release review** | partial (name trademark check L1 first pass done 15.10; WIPO/USPTO/FIPS left) | Kanta |
| Privacy policy page `site/privacy.html` | ready (needs a re-read against the demo report-sending consent, DM-07) | Claude |
| RKN personal-data notification (PD-02) | missing, overdue since 24.10 | Kanta |
| Meshy / Hunyuan commercial terms (V-08) - required before the AI survey is answered | missing | Kanta (Claude drafts the question list) |
| Asset licence register (L2), `game/art/LICENSES.md`, `game/models/CREDITS.md`, `game/audio/CREDITS.md` | partial (no credits file for generated art / Figma story art) | Claude |

## 3. Store graphics (Valve "Graphical Assets" doc, 2026-11-01)
Current art exists as in-game captures and site/branding images only; **no Steam-size art has been made yet**. All capsules need the readable game logo/title (review rule). No real flags/insignia/aircraft (our hard rule 1).

| Asset | Required | Size px | Format / rules | Status | Owner |
| --- | --- | --- | --- | --- | --- |
| Header capsule | yes | 920 x 430 | logo + artwork | missing | Claude (art needs Kanta's "yes") |
| Small capsule | yes | 462 x 174 | logo + artwork, readable when tiny | missing | same |
| Main capsule | yes | 1232 x 706 | logo + artwork | missing | same |
| Vertical capsule | yes | 748 x 896 | logo + artwork | missing | same |
| Library capsule | yes | 600 x 900 | logo + artwork | missing | same |
| Library header capsule | yes | 920 x 430 | logo + artwork (same as header is fine) | missing | same |
| Library hero | yes | 3840 x 1240 | **.png, artwork only, no logo** | missing | same |
| Library logo | yes | 1280 wide and/or 720 tall | **.png, transparent logo only** | missing (logo exists in brand files, check transparent PNG) | Claude |
| Shortcut icon | yes | 256 x 256 | .png or .ico | missing | Claude |
| App icon | yes | 184 x 184 | .jpg | missing | Claude |
| Event cover | yes | 800 x 450 | artwork + copy; used for announcements | missing | Claude |
| Event header | optional | 1920 x 622 | follow Valve template clipping | missing | Claude |
| Page background | optional | 1438 x 810 | subtle, not bright | missing | Claude |
| Screenshots | yes (**count: verify in Steamworks; usual minimum 5 [guess]**) | >= 1920 x 1080, 16:9 | **gameplay only**; no concept art, pre-rendered stills, text/awards | missing: our shots are 1280x720 / 1600x900 (`site/img`, `demo/shots-2026-10-22`), too small | Claude (cloud capture) or Kanta's PC; plan B-44 |
| Demo capsules / library assets | only if the demo gets its own page | same sizes | must make clear it is a demo; own trailer + >= 5 own screenshots | not needed (decision 19.10: no separate demo page) | - |

How to make the art without spending: render key art from the game's own 3D scene (the model lab and trailer capture already work, `game/scripts/trailer_cap.gd`), compose logo/text in HTML/Playwright. Generator credits (ChatGPT, Figma AI, Meshy) only after Kanta's "yes". Valve's templates are linked from the Graphical Assets page; the final clipping check must be done against them.

## 4. Trailer
| Item | Status | Owner |
| --- | --- | --- |
| Spec: up to 1920x1080, 30/60 fps, >= 5000 kbps, .mp4/.mov/.wmv, H.264 + AAC (44.1/48 kHz), 16:9; no length limit stated; at least one public trailer is mandatory for Next Fest and Early Access ("a video trailer showing gameplay") | - | - |
| Trailer v1 (RU, 36.5 s): 1920x1080, 30 fps, H.264 ~8.2 Mbps, AAC 44.1 kHz - **meets the spec**. Files in `/mnt/project-files/marketing/video/trailer/` (16x9 EN/RU) | partial: end card says "Скоро в Steam"; Steam wants **English as the base video**; Valve favours gameplay-first with HUD; no Fortress in frame | Claude |
| Steam cut: English base trailer, gameplay in the first seconds, end card "Wishlist now" (no URL text, no Steam-UI imitation), localized RU trailer assigned in Advanced Settings | missing | Claude |
| Poster frame (1920x1080 .jpg/.png from the video, no text) | missing | Claude |
| Optional: teaser + dev-diary trailer (categories General / Teaser / Gameplay / Dev diary) | missing | Claude |
| Must be on the page and final by 10.01 (fest registration), pulled by Valve 18.01 | deadline | Claude |

## 5. Store page text
| Item | Status | Owner |
| --- | --- | --- |
| Short description (limit **[verify in Steamworks]**; our draft assumes 300 chars) EN + RU | partial (`steam-page.md` §2, written 18.10; class names/modes outdated: now Osa/Grach/Kit classes, Ace Battle mode, Highlands story, medals) | Claude, Kanta approves tone |
| About this game (long description, BBCode/images), EN | partial (`steam-page.md` §3, needs refresh; **no links to websites in the description**, no Steam-UI imitation, no other games) | Claude |
| Russian full description | missing (translate after EN is approved) | Claude |
| Chinese | not now (L-05 after native check) | - |
| Early Access Q&A, all six topics: goals, expected duration, how the full version differs, current state, pricing plans, community involvement; **no promises of dates or features** | partial (`steam-page.md` §5 draft, needs rewording) | Claude drafts, Kanta decides duration and price statement |
| Only features available at launch on the page; remove unimplemented ones from Basic Info | rule | Claude |
| Tags (up to ~20 [guess]): Bullet Heaven, Action Roguelike, Roguelite, Shoot 'Em Up, Top-Down, Flight, Aircraft, Singleplayer | partial (`steam-page.md` §4) | Claude |
| Categories / features: Single-player, controller support (declare only after B-11 gamepad pass), Steam Cloud (if enabled), achievements (optional, MD-01 later), trading cards (optional, separate review) | partial | Kanta clicks |
| System requirements min/rec | missing - needs numbers from real PCs (cloud has no GPU); renderer is Forward+ with automatic GL Compatibility fallback; size ~1.8 GB build | Claude drafts from logs of testers; Kanta checks |
| Supported languages table (interface / audio / subtitles): RU, EN (ZH later) | partial | Claude |
| Supported OS: list only what runs and was tested (Windows now; macOS has no signing; Linux only a CI check) | decision | Kanta |
| Links: website flakheaven.com, Telegram, Discord (via the dedicated link fields) | ready content | Kanta |
| Developer / publisher names, support email | missing | Kanta |
| Price: $9.99, RU 250 RUB manual, other regions by Valve recommendation; no permanent discount in Early Access; no discount within 30 days of a price increase; launch discount 10% allowed | decided 19.10; set in Steamworks | Kanta (`pricing.md`) |

## 6. Ratings and content declarations
| Item | Status | Owner |
| --- | --- | --- |
| Content Survey, three required sections: General content (generates regional age ratings), Mature content (violence, must match the build), Generative AI (pre-generated content) | missing (target 20.11 / S6) | Claude prepares answers, Kanta submits |
| AI disclosure answer: yes - 3D models (Meshy, hand-finished), crew portraits (ChatGPT), story comic art (Figma AI); music/SFX are stock CC0/CC-BY/Sonniss, not AI | partial (`steam-page.md` §8, add story art) | Claude |
| Anti-cheat declaration, accessibility flags, controller support in Basic Info | missing | Kanta clicks |
| Fictional world check of all store text/art (no real countries, flags, aircraft) | rule | Claude |

## 7. Build and technical
| Item | Status | Owner |
| --- | --- | --- |
| Steamworks App ID for the game; later a separate App ID for the demo (Add Demo from the game's landing page) | missing (after Valve approval) | Kanta |
| Depots + builds: upload with SteamCMD to the default branch; mostly-final build with every feature the page lists | missing - no steamcmd scripts or release export preset in the repo (presets: Windows Tester, Linux Check, macOS Tester, Windows Demo) | Claude writes scripts and preset; Kanta runs the upload (needs his login / Steam Guard) and any build is made only on Kanta's direct command (rule 3) |
| Steam integration in the game: `steam_appid.txt` for dev, SteamAPI init, overlay, Steam Cloud, achievements - no GodotSteam in the project yet | missing | Claude (system change: plan first, Kanta "yes") |
| Demo: code ready (`demo.gd`, preset "Windows Demo"); set `Demo.STEAM_APP_ID` after the app exists; wishlist button | ready (code), Steamworks side missing | Claude + Kanta |
| Demo Steamworks setup: separate demo app, depots, "Download Demo" button via Special Settings > Associated Demos, republish base page after demo release; achievements off in demo | missing (DM-09) | Kanta + Claude |
| Wishlist notification: one email/push to wishlisters, available for 2 weeks after the demo first goes live (2-week cooldown vs. other events) | plan for 11.02 | Kanta |
| Launch checks Valve runs on the build: starts on every listed OS; listed features exist | to do before 18.01 | Claude |
| Gamepad / Steam Deck pass (B-11, CR-05) | missing | Claude |

## 8. Release steps in Steamworks (Kanta clicks)
1. Fill the Store Presence checklist; "Mark as ready for review" (page first, then the build checklist).
2. After approval click "Post as Coming Soon" (community hub opens, wishlists start).
3. Register for Next Fest by 10.01.
4. Submit demo + page by 18.01; final items by 01.02.
5. Enable Early Access (Early Access tab, Q&A) - the page is reviewed again.
6. After >= 2 weeks of Coming Soon and approvals: "Release App" -> Publish Now -> Release Now.

## 9. Sources (read 2026-11-01)
- https://partner.steamgames.com/doc/store/assets
- https://partner.steamgames.com/doc/store/trailer
- https://partner.steamgames.com/doc/store/releasing
- https://partner.steamgames.com/doc/store/review_process
- https://partner.steamgames.com/doc/store/coming_soon
- https://partner.steamgames.com/doc/store/earlyaccess
- https://partner.steamgames.com/doc/store/application/demos
- https://partner.steamgames.com/doc/gettingstarted/contentsurvey
- https://partner.steamgames.com/doc/gettingstarted/onboarding
- https://partner.steamgames.com/doc/marketing/upcoming_events/nextfest/feb_2027
- Not retrievable from the docs pages we could read: screenshot count, short-description limit, system requirements fields, tag limit, language list. Check these inside Steamworks when the page editor opens.
