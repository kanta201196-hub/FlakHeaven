# Steam Content Survey and AI disclosure: draft answers

Draft 2026-11-02. The survey has three required sections (Valve, contentsurvey doc, read 2026-11-01): General content, Mature content, Generative AI. It must match the build. Kanta submits in Steamworks (target 20.11, S6); the answers marked **[verify]** need a look at the build first. Do not change them without checking `docs/game-context.md`.

## 1. General content (generates regional age ratings)
- Setting: fictional world, fictional aircraft and places. No real countries, flags, insignia.
- Violence: stylised combat between aircraft, ground vehicles, ships, turrets and missiles seen from above. **[verify]** no visible people hit or killed, no blood or gore (crew shown only as portraits).
- No sexual content, nudity, drugs, alcohol, gambling, simulated gambling, user-generated content, online chat or multiplayer. Single-player.
- Loot "cards" are chosen by the player, no randomised paid items, no purchases in the game.
- Data: tester builds can send a report with the player's consent; **[verify]** the Steam build/demo's report button wording against `docs/legal/personal-data.md` and `site/privacy.html`.

## 2. Mature content
Answer from the build, not from the plan. Nothing adult is expected (**[verify]**: search assets for any such content before answering). Valve wants every adult item in uploaded builds disclosed, even if not reachable.

## 3. Generative AI (shipped content only; dev tools like Claude for code are out of scope)
Pre-generated content in the game:
| What | Tool | Where | Human work |
| --- | --- | --- | --- |
| 3D models of part of the vehicles | Meshy (paid plan) and some made in Blender by script | `game/models/CREDITS.md` | reworked by hand |
| 15 crew portraits | ChatGPT image generation by Kanta | `game/art/portraits/` | selected and edited |
| 9 comic-style story pictures (2026-11-01) | Figma AI image models | `game/art/story/` | selected by Kanta |
| Music and sound effects | none: stock CC0 / CC-BY / Sonniss | `game/audio/CREDITS.md` | - |
| Localization | RU/EN written with Claude, ZH pending a native check | `.po` files | **[verify]** whether to list; localization is named in Valve's scope |

Live-generated AI: none.
Open: Meshy/Hunyuan commercial terms (V-08), still unchecked by Kanta. Do not submit this section before that is closed.
