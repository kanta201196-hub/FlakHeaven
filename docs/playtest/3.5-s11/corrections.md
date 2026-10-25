# Corrections for build 3.5-s11

One numbered list for Kanta's notes (IDs `S11-NN`). Work starts after Kanta's "готово" or an explicit "distribute and start".
Build kit: `/mnt/project-files/builds/3.5-s11/`. Open items carried from s10 are in `docs/backlog.md` (S9-*, S10-*).

| ID | Note | Source | Status |
| --- | --- | --- | --- |
| S11-01 | Title screen: the biome looks bad | relief thread | new |
| S11-02 | Hangar flaps: only the flap piece lowers, the wing stays solid; the wing section must lower as a part of the wing («Osa» 2) | 3D models thread | new |
| S11-03 | Hangar: NAR (unguided rockets) need a proper stand when viewed | 3D / upgrades thread | new |
| S11-04 | Move the course gun setup to the left so weapons are set up in one place | menu / upgrades thread | merged (PR #404) |
| S11-05 | Course gun: a separate description under each block instead of one common text | menu / upgrades thread | merged (PR #404) |
| S11-06 | «Osa» 2: missiles intersect the plane's textures | 3D models thread | new |
| S11-07 | «Osa» 1: missiles hang crooked on the pylon; a leftover hull-coloured part on the wing looks like a missile mount | 3D models thread | new |
| S11-08 | «Osa» 1: flaps work with the same defects as «Osa» 2 (see S11-02) | 3D models thread | new |
| S11-09 | Rework weapon setup in the hangar: one solid list where at most two items can be picked; heading «Выбор стартового вооружения (не более 2 видов)», the main list below as it is now (screenshot s11_note_6.png) | menu / upgrades thread | merged (PR #404) |
| S11-10 | «Kit» (Кит): the model already had a permanently open bomb bay and the new mechanisation now conflicts with it — remove the extra parts; wing mechanisation has the same defects as on the other planes (see S11-02; screenshot s11_note_7.png) | 3D models thread | new |
| S11-11 | «Kit» 1: the bomb bay opens but the bombs hang right on the belly; the bay must open the plane's interior where the bombs sit, now they appear from thin air (screenshot s11_note_8.png) | 3D models thread | new |
| S11-12 | «Kit» 1: wing mechanisation has the same problems as on the other planes (see S11-02) | 3D models thread | new |
| S11-13 | Hangar: turrets look low quality and hang in the air (screenshot s11_note_9.png) | 3D models thread | new |
| S11-14 | «Kit» 2: texture problems on the model (screenshot s11_note_10.png) | 3D models thread | new |
| S11-15 | «Grach» (Грач): the same texture problem as «Kit» 2 (see S11-14; screenshot s11_note_11.png) | 3D models thread | new |
| S11-16 | In game: ground textures look pixelated (screenshot s11_note_12.png) | relief thread | new |
| S11-17 | Make the cards (level-up card pick) about 25% smaller (screenshot s11_note_13.png) | combat UI thread | merged (PR #405) |
| S11-18 | Pause pylon panel: numbers overlap other elements; the launch hint shows «К» (K) but missiles actually fire on the right mouse button (screenshot s11_note_14.png) | combat UI thread | merged (PR #405) |
| S11-19 | Header «НАГРАДА ЗА ПОЗИЦИЮ ПВО» is too dim and hard to find: make it a bit brighter (screenshot s11_note_15.png) | combat UI thread | merged (PR #405) |
| S11-20 | Card description is unclear: cannot tell whether the bonuses apply now or only after 4 more levels (screenshot s11_note_16.png) | combat UI thread (card text) | merged (PR #405) |
| S11-21 | Card descriptions: text wraps so a closing bracket lands alone on the next line (e.g. «(из 11» / «)»); fix the wrapping in all descriptions (screenshot s11_note_17.png) | combat UI thread | merged (PR #405) |
| S11-22 | Card pick: the tooltip at the bottom must disappear when the mouse leaves the card (screenshot s11_note_18.png) | combat UI thread | merged (PR #405) |
| S11-23 | Card pick screen: player HP must be visible (screenshot s11_note_19.png; the same screenshot shows the dangling «)» on «Усиленная боевая часть», part of S11-21) | combat UI thread | merged (PR #405) |
| S11-24 | In battle: some yellow flat-looking planes; identify which unit it is (screenshot s11_note_20.png) | 3D models thread | new |
| S11-25 | Pause screen: many elements overlap each other (slot numbers on icons, numbered markers on the plane blueprint, right column cut at the screen edge, truncated labels) (screenshot s11_note_21.png) | combat UI thread | merged (PR #405) |
| S11-26 | Card «Лазер обороны «Луч» (экспериментальный)»: the title/description is cut with an ellipsis, the full text is not visible; the card must also say what the weapon does and its base damage (code: 6 damage per 0.9 s on the nearest enemy only when there is nothing to burn; first it burns up to 2 missiles and 2 bullets in 250 px) (screenshots s11_note_22.png, s11_note_23.png) | combat UI thread | merged (text in main, title layout PR #405) |
| S11-27 | After an explosion many unclear particles hang in the air, look like hay or straw (screenshot s11_note_24.png) | effects thread | merged (PR #406): it was the scorch texture (straw in the photo), rebaked without it |
| S11-28 | Before a NAR (unguided rocket) explosion there is a strange, clearly noticeable delay with a pulsing on the ground | effects thread | merged (PR #406): it was the «Термобарика» 0.5 s sticky delay; the blast is now on impact |
| S11-29 | «Fortress» (Крепость) boss: turrets float in the air detached from the plane; the screenshot also shows the bomber drawn flat white/pink (screenshot s11_note_25.png) | 3D models thread | new |
| S11-30 | Could not shoot down the «Fortress» boss on an upgraded «Grach» (balance: needs the balance method, one change per build cycle) | game design thread | new |

Screenshots (Kanta, 2026-10-25): `/mnt/project-files/playtest/3.5-s11/s11_note_1.png` … `s11_note_25.png`.
