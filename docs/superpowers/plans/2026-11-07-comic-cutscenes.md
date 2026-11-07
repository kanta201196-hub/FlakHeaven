# Story cutscenes as a living comic page (ST-12)

**Decision:** Kanta 07.11.2026 — «вариант 2»: every story scene becomes a comic page of 3–4 panels with motion
inside the panels (options page https://claude.ai/artifact/1SijbHm6rRwAfmB3fqJFFt). Replaces the single key-art
picture of ST-11; the picture and the live fly-over stay as fallbacks.

## Goal

The 11 scene cards of the Highlands (5 intros, 4 outros, 2 epilogue cards) stop reading as «a plane flies». Each card
is a page: panels slide in one after another, each panel slowly pushes in, speech balloons pop next to the speaker,
captions sit in yellow plates, sound words punch in, and the engine animates life inside the panels: smoke, flak,
tracers, fire and afterburner flicker, rain, flares, screen shake, and cut-out jets that fly across a panel.

Length, skip rules, light presets, stingers, flags and the autotest stay as they are (`Cutscene`).

## Architecture

- `game/scripts/story/story_comic.gd` (`StoryComic`, data only): page per scene id
  (`intro_pass`, `outro_forts`, …, `epilogue_sky_south`). A page is a list of panels:
  - `t` — s when the panel slides in; `rect` — [x, y, w, h] share of the comic area;
  - `img` — `res://` path; `src` — [x, y, w, h] source rect in px (crop of a key-art picture or a portrait);
  - `push` — [scale gain, dx, dy] of the slow push-in over the panel's life;
  - `cap` — [x, y, text] caption plate; `say` — index into the scene's `lines` (the balloon text and speaker come
    from `StoryScenes`, so the words stay in one place and go through `Loc`) + balloon anchor;
  - `sfx` — [x, y, word, colour, angle]; `shake` — true: a short screen shake when the panel lands;
  - `fx` — list of engine effects: `smoke`, `flak`, `tracer`, `glow`, `rain`, `fly` (a cut-out sprite moving
    from a to b, optional), each with points in panel space.
- `game/scripts/story/comic_keys.gd` (`ComicKeys`, pure maths, unit-tested): panel slide-in alpha and offset,
  push-in source rect, balloon and sound-word pop scale, shake offset, deterministic particle positions for a time `t`.
- `game/scripts/hud_comic.gd` (`HudComic`, drawing): dark halftone page, white panel borders, cropped textures,
  effects, balloons, captions, sound words. `HudCutscene` calls it instead of the single picture when the scene has
  a page; the letterbox caption bar is not drawn then (text lives in balloons), the skip hint and fades stay.
- `Cutscene` loads the page's textures for the scene and drops them at the end (same VRAM rule as ST-11).
- F1 `story_comic` (default 1, R-22 as changed 06.11): 0 → the single picture of ST-11.

## Art

Phase A (no credits, this PR): pages built from what is in the game already — the 9 key-art pictures (crops) and
the three story portraits. Motion comes from push-in, effects and shake.

Phase B (after Kanta's «да» on the generation package): about 13 new pictures in Figma AI in the accepted ST-11
style — ~6 panel plates (close-ups with empty sky or ground where a jet will fly) and ~7 jet cut-outs on a flat
magenta background (player flight from three angles, Baron's jet, enemy fighter, the «Крепость» flying wing, a far
swarm), keyed to alpha by script. With retries ~20–25 generations. Same prompt rules as ST-11: fictional jets, no
letters, logos, flags or insignia.

## Pages (phase A)

| Scene | Panels |
| --- | --- |
| intro_sky | base wide (afterburner glow, dust) · swarm in the sky (crop) · Купол balloon ×2 · jets close-up, «РРАУ!» |
| intro_forts / .recon | forts wide (flak) · Baron's jet close, red balloon · Купол balloon · fort tower close (flak, tracers); recon adds a map marker ring |
| intro_riverbed | works wide (dust) · guns in concrete close · Купол balloon · far silhouette in the sky |
| intro_pass | as on the options page: pass wide · convoy · Купол balloon · jet close «ВВУУХ!» |
| outro_sky | convoy and people · burning «Крепость» (smoke, fire) · Купол balloon · jets into the sunset, title |
| outro_forts | as on the options page + green flare glow and smoke |
| outro_riverbed | wreck wide (smoke, fire) · wreck close · Купол balloon · radio set (dial glow) |
| outro_pass | jet over the road · convoy lights · Купол balloon |
| epilogue (south / later) | port at night (rain, lamps) · radio set (dial glow) · Купол balloon |

## Tests and checks

- `game/tests/comic_keys_test.gd` (TDD): slide-in timing, push-in rect stays inside the source, pop scale,
  shake decays to zero, particles deterministic and inside the panel, every page's `say` index exists in its scene.
- `tools/ci/unit.sh`, `tools/ci/smoke.sh fighter`; frames for the review page with `--cutshot` (Compatibility).

## Steps

1. Plan + backlog ST-12 (this file).
2. `ComicKeys` + tests.
3. `StoryComic` pages from existing art.
4. `HudComic` drawing + `Cutscene` loading + F1 switch.
5. Frames of every page → page for Kanta with a text list of what changed.
6. Generation package (list, prompts, input picture) → Kanta's «да» → phase B pictures → `fly` layers.
