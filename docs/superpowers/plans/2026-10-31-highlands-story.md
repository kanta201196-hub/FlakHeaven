# Highlands story: cutscenes, hangar dialogues, radio — plan

Kanta 31.10.2026: depth 3 for the Highlands (full narrative), enemy «Монолит», rule amended, everything in the demo,
second ace «Граф». Design: `docs/story/highlands-storyline.md` (§9 Monolith, §10 bosses, §11 hangar scenes),
`docs/story/cutscenes-and-presentation.md` (forms, tech, audio, VFX). Backlog ST-01…ST-10.
**Approved by Kanta 31.10.2026 («Корректируй план. Нагорье делаем всё!»)**: the whole Highlands story is one job, no
split into «before the demo» and «after». Open points of storyline §8 are taken as the recommended options (portraits with
briefs shown first and no generation spend without a separate «да», Grom's role as the player's choice, mechanic «Ключ»,
Monolith mark with a frame for «ok»); Kanta can overrule any of them by number. Owner: thread «Проработать сюжет Нагорья
и заставки», branch `claude/project-thread-d4n9lr`, one PR per step.

## Rules

- The sortie is never stopped: inside the 15 minutes only radio, banners and three 1.5 s slow-motion accents.
- Every scene (intro, outro, hangar dialogue) is skippable with any key / button; a setting «Заставки: при первом
  прохождении / всегда / никогда» (default: first time). Scenes play on the first clear of an operation; story flags live
  in the campaign save (`user://campaign.cfg`, section `story`) through the existing `Campaign.flag / set_flag`.
- Choices change text, a camera target or one radio warning; never HP, damage, rewards or unlocks.
- All strings through `Loc.t()`; Russian source, EN/ZH drafts for the translation thread.
- Drawn with `HudKit` (ADR-05), no Control scenes; no video; no voice acting; no generator credits without Kanta's «да».
- Demo (`Demo` flags): everything for ops 1–2 incl. H0–H2′; the demo-end overlay follows H2′.
- Autotest: `--autotest` skips every scene at 0.2 s and logs `CUTSCENE <id> skipped` / `DIALOG <id> skipped`;
  `--shots` takes one frame per scene for the review page.

## Where it lives

1. **Texts** — `game/scripts/story/story_text.gd` (`StoryText`, const Dictionaries keyed by id; one place for radio,
   dialogue, captions, result lines). `story.gd` reads lines from it instead of literals. Mini-boss lines: `boss.gd` gets
   `op_lines(callsign, op, met_count)` from `StoryText`, falls back to its generic `LINES`. Fortress speaker:
   «Штаб „Монолита“» (enemy, red) for its own lines, «Купол» for ours.
2. **Flags** — `Campaign` gains `story_scene_due(id) -> bool`, `story_choice(id) -> String`, `set_story_choice(id, v)`,
   `met(callsign) -> int`, `on_met(callsign)`. Pure logic, unit tests in `game/tests/story_flags_test.gd` (TDD).
3. **Cutscene runtime** — `game/scripts/story/cutscene.gd` (`Cutscene`, RefCounted): plays a scene definition
   `{camera: [[t, pos, look_at, fov]...], actors: [...], captions: [[t, speaker, text]...], light: "dawn|day|dusk|night",
   stinger: id, dur}`. Camera via `Tween` on the sortie `Camera3D`; actors via `TitleFlight`'s model spawn with a scripted
   route (`title_route.gd` gets a `from_keys()` constructor); light presets = sun angle, colour, exposure (3 values,
   tweened; both renderers). Letterbox + caption + skip hint drawn by `hud_cutscene.gd` (HudKit). `Main.state = "cutscene"`;
   ends with `Events.cutscene_done`.
4. **Hangar dialogue runtime** — `game/scripts/story/dialog.gd` (`Dialog`, RefCounted) + `hud_dialog.gd`: scene =
   `[{who, side, text, trait_line: bool} | {choice: id, options: [[label, next]...]}]`; portraits from
   `Profile.portrait()` for the crew and `res://art/portraits/<id>.png` for Купол / Гром / Ключ (fallback: callsign plate
   if the file is missing — so the code ships before the pictures). Typewriter 40 chars/s, Enter/click advance, Esc skips,
   gamepad focus on choices. Plays over the 3D hangar (`hangar3d.gd`) with the camera on the plane's nose.
5. **Accents** — `Cinematic.accent(id)` in `game/scripts/story/cinematic.gd`: banner + `Engine.time_scale` 0.35 → base
   over 1.5 s + music duck −8 dB (Music bus) + stinger. Called from `story.gd` (Fortress first sight, Baron down, Grom joins).
6. **Flow** — `Main`: campaign screen → (H-scene before op if due) → «В ВЫЛЕТ ▶» → terrain preload → intro if due →
   `Story.start` → sortie → evac → outro if due → H′-scene if due → results (+ story line) → demo-end overlay in the demo.
   Story log («Журнал») on the campaign screen lists played scenes and choices (`hud_campaign.gd`, one panel).
7. **Audio** — `build_audio_layers.py --only story`: 4 stingers cut from the chosen CC0 tracks, radio squelch, Fortress
   drone; rows in `audio/CREDITS.md`.
8. **Settings** — `Settings` key `cutscenes` (0 first time / 1 always / 2 never) in the menu «Игра» section.

## Steps (each a PR into main; smoke `all` after each; `full.sh` once for step 6)

Order: runtime first, then the content operation by operation, so every PR after step 4 adds a playable piece.

| # | Step | Content | Est. days |
| --- | --- | --- | --- |
| 1 | ST-01 + flags | small fixes («Штаб „Монолита“» / «Купол», `Loc.t` audit, op 4 briefing sentence); `Campaign` story API with unit tests; `StoryText` skeleton | 1 |
| 2 | ST-03 cutscene runtime | `Cutscene`, `hud_cutscene`, light presets (both renderers), setting, autotest hooks; one test scene | 2.5 |
| 3 | ST-07 dialogue runtime | `Dialog`, `hud_dialog`, choices, story log panel, portrait fallback (plates) | 2.5 |
| 4 | ST-05 accents + audio | `Cinematic.accent`, 4 stingers, radio squelch, Fortress drone (CC0, credits rows) | 1.5 |
| 5 | Op 1 «Перевал» | texts, H0 / H1 / H1′, intro + outro, boss lines (op 1), result line | 1.5 |
| 6 | Op 2 «Сухое русло» | texts, H2 / H2′ with the recon choice, intro + outro, Fortress first-sight accent, «Штаб „Монолита“» lines, demo-end hand-off; `full.sh` | 2 |
| 7 | Op 3 «Крепости» | texts, H3 / H3′ with Grom's role choice (ST-10), intro + outro, «Граф» and «Сквозняк» lines, Baron-down accent | 2 |
| 8 | Op 4 «Небо над Шахрисангом» | texts, H4 / H4′, intro + outro, epilogue card with the hook, Grom-joins accent, second-controller mode | 2 |
| 9 | Finish | village / column lights at dusk, briefing vignette (ST-06), review page with one frame per scene and all texts by number, `.po` EN/ZH stubs for the translation thread | 1.5 |
| 10 | ST-08 / ST-09 | portrait briefs for Купол / Гром / Ключ → Kanta; Monolith mark decal with a frame for «ok»; wire the pictures when they exist | 1 |
| | **Total** | | **≈ 17.5** |

Estimates are thread-days of one strong-model thread with checks; iteration on Kanta's frame reviews is included once
per step. Translation (EN/ZH) is the translation thread's time, not counted here. The demo gets whatever is merged for
ops 1–2 at build time (`Demo` flags hide ops 3–4 as today).

## Not in this step

- Voice acting; video; crew scenes outside the Highlands; Archipelago story (hook line only); Steam achievements for story.
- Any balance effect of a choice; new enemies or boss phases.
- Night/dusk variants of the biome for the sortie itself (presets are for scenes only).

## Checks

- `tools/ci/unit.sh` for `story_flags_test.gd`; `tools/ci/smoke.sh all` after every PR (scenes skipped at 0.2 s, must log
  the skip line and reach `playing`); `tools/ci/full.sh` once after step 6 (accents touch `Engine.time_scale` in combat) and once before the build.
- Both renderers for light presets: Compatibility screenshots (`--shots`) and one Forward+ run with lavapipe for the
  review page.
- Kanta's review: a page with one frame per scene and all texts by number before the demo build.
