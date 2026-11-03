# Story presentation: intros, outros, radio, visual and audio effects

31.10.2026 · thread «Проработать сюжет Нагорья и заставки» · companion to `highlands-storyline.md`.
Status: **concept, waiting for Kanta** (questions in the storyline document, §7). Estimates are thread-days in the cloud
(one strong-model thread, checks included), not calendar days.

## 1. Principles

1. **The sortie is never stopped by the story.** Inside the 15 minutes the story is radio, banners, a 2-second slow-motion
   accent at most — the rule «радио идёт очередью и бой не останавливает» (EX-09) stands. Scenes live *before* and
   *after* the sortie.
2. **Short and skippable.** Intro ≤ 12 s, outro ≤ 12 s, any key or click skips; a setting controls when they play
   (first clear / always / never). Kanta's principle: the player enjoys, does not endure.
3. **Everything is rendered live by the engine.** The player's own livery, decals and plane level appear in the scenes;
   no video files, no generator credits, nothing to re-render when a model changes. The menu already does this
   (`TitleFlight`: hangar-quality models flying over the live biome), so the technique is proven in both renderers.
4. **One visual language with the HUD.** Letterbox bars, captions and the radio panel reuse `HudKit` immediate-mode drawing
   (ADR-05), tokens from `docs/standards/ui-design-system.md`; no Control-node scenes.
5. **Three languages, no voice acting.** Radio stays text with a «radio texture» sound; captions go through `Loc.t()`.

## 2. Where the story is delivered (map of moments)

| # | Moment | When | Form | Exists? |
| --- | --- | --- | --- | --- |
| M1 | Operation briefing | screen «В вылет» | text block + task line | yes (`hud_campaign.gd`) — add a live **operation vignette** (see §3.1) |
| M2 | Intro | after «В ВЫЛЕТ ▶», before control is given | in-engine scene 8–12 s | new |
| M3 | Opening radio | 0:00–0:10 of the sortie | radio queue | yes (`story.gd`) |
| M4 | Story radio beats | 8:00 Baron, miniboss, first Fortress sight, Graf line | radio with red intercept frame | partly (`story.gd`, `rival_ace.gd`) |
| M5 | Rescue activity | op 2 | activity with radio | yes (`rescue.gd`) |
| M6 | «Кино-момент» inside combat | Fortress arrival, Baron down, Grom joins | banner + 1.5–2 s slow-motion + stinger, no camera change | new (banner exists) |
| M7 | Outro | after evacuation, before the results screen | in-engine scene 6–12 s | new |
| M8 | Story line on the results screen | results | one line under the operation title | new (results screen exists) |
| M9 | Demo-end teaser | after op 2 in the demo | existing overlay + outro of op 2 before it | yes (M-07), outro new |
| M10 | Campaign epilogue + hook | after op 4 first clear | outro + black card with the hook line, district credits | new |

Scenes M2/M7 play only when the operation is not yet cleared (or per setting). On replays the flow is exactly today's.

## 3. Forms, from cheapest to most expensive

### 3.1. Briefing vignette (M1) — ~0.5 day
On the «В вылет» screen the operation card gets a live 3D window: the camera parks over a characteristic spot of the
biome (pass road, dry riverbed with AA, a fortress-kala, the valley mouth) with the player's plane in the foreground.
Reuses the menu world that is already rendered behind the UI; only a camera target per operation is new.

### 3.2. Radio and intercept frame (M3, M4) — in game; polish ~0.5 day
- Keep the queue and the 3.5 s + 0.03 s/char timing (`hud.gd`).
- Story lines get a **speaker plate** (callsign + role: «Купол · база», «Барон · перехват») so a new player knows who talks.
- Intercept (enemy) lines: red frame (exists) + a 0.3 s static burst sound before the line; Baron's lines slightly longer on screen.
- Unify the Fortress speaker to «Купол» (today «Штаб»).

### 3.3. In-combat «кино-момент» (M6) — ~1 day
No camera move, no input loss. Recipe: banner text (exists, `Events.banner`) + `Engine.time_scale` 0.35 for 1.5 s with
an exponential return (the level-up already uses 0.05 → base, so the code path is known) + music duck −8 dB for 2 s on the
`Music` bus + a stinger. Used three times per campaign at most: first Fortress sighting (op 2), Baron down (op 3),
Grom joins (op 4). Must obey the «игрок не преодолевает» principle: enemies also slow down, projectiles too, nothing fires
during the accent that would not have fired anyway. The autotest must see a `BANNER` line and keep running.

### 3.4. In-engine intro/outro scenes (M2, M7, M10) — core ~2 days + ~0.4 day per scene
*(in game: `Cutscene`, `StoryScenes`, `HudCutscene`. Step 11, Kanta 01.11: every intro, outro and the epilogue card
has comic-style key art (`game/art/story/<scene id>.jpg`, Figma AI, 1536×864) shown with a slow push-in instead of the
live fly-over; the fly-over remains the fallback behind F1 `story_art`. Plan: `docs/superpowers/plans/2026-11-01-story-art.md`.)*

**Runtime (new `Cutscene` class, `RefCounted` like `Story`):**
- A scene = a small data script (`game/scripts/story/scenes/<op>_<intro|outro>.gd` or a Dictionary in one file):
  camera keyframes `[t, position, look_at, fov]`, actor list (which hangar models, formation offsets, roll/bank curves),
  caption lines `[t, speaker, text]`, time of day, stinger id.
- Camera: the existing `Camera3D` of the combat scene; position and look-at tweened between keyframes with `Tween`
  (`TRANS_SINE`, `EASE_IN_OUT`); no `Path3D` needed for 2–3 keyframes. The world under the camera is the **real sortie
  terrain** at the start position, so the intro doubles as the first look at the map and the ground is already built for
  the sortie (RV-05 builds visible chunks first; the intro camera must stay over the chunks the sortie start needs).
- Actors: `TitleFlight` already places hangar-quality models of the three classes in formation over the live biome with
  the player's livery, bank, cheap shadows and contrails; the scene reuses its spawn and advance functions with a scripted
  route instead of the river trace. Enemy actors (Fortress, rival ace) are the battle models, unarmed and unpiloted.
- UI: `HudKit` draws two black bars (letterbox, 12 % of height each), the caption in the lower bar, the speaker plate,
  «Пропустить — любая клавиша» hint after 1 s (fades after 3 s). Gamepad: any button skips.
- Input: `Main.state = "cutscene"`; any press ends the scene with a 0.4 s fade to the sortie / results.
- Time of day: the sun is a `DirectionalLight3D`; dawn/dusk/night are a sun angle + colour + exposure preset tweened over the
  scene (dusk ≠ a new sky system; a 3-preset table is enough). The sortie itself keeps its normal lighting — the fade covers
  the switch. If the renderer is the GL Compatibility fallback, the same presets apply with `SRGB()` colours.
- Save flags in the campaign file: `seen_intro_<id>`, `seen_outro_<id>`.
- Autotest: `--autotest` skips scenes at t = 0.2 s and logs `CUTSCENE <id> skipped`; `--shots` can take one frame per scene
  for Kanta's review page.

**Authoring a scene** is editing numbers in the data script and taking a screenshot — no Blender, no new assets:
all actors, props and terrain exist. Eight scenes (4 intros, 4 outros) ≈ 3 days including iteration on Kanta's feedback.

### 3.5. Pre-rendered video — **not recommended**
Godot 4.4 ships only Theora (`VideoStreamPlayer` + `.ogv`): large files (~50–100 MB per minute at 1080p), no player
livery, re-render on every model change, a second pipeline (Blender/ffmpeg) and no Forward+ look. Keep for a possible
Steam trailer, not for the game.

### 3.6. Hangar crew scenes (talking portraits, choices) — after Early Access
Needs portraits per character, dialogue UI, writing in three languages. Listed only so the ladder is complete (question 1,
option 3 in the storyline document).

## 4. Audio

| Element | What | Source / licence | Cost |
| --- | --- | --- | --- |
| Radio texture | 0.3 s squelch/static before intercept lines, soft «click» before friendly lines; a typed-out caption «tick» at 30 chars/s (optional, setting) | existing `radio` sound + Sonniss GDC pack via `build_audio_hybrid.py`; CC0 | 0.3 day |
| Stingers | 3–5 s hits: operation start (brass + low synth), Fortress sighting (low drone + metallic), Baron down (short triumphant), epilogue (soft pad) | cut from the chosen CC0 rock tracks (nene) and `Remembrance` (bobjt, CC0) so the palette matches; or CC0 one-shots from OpenGameArt | 0.5 day |
| Intro bed | the menu track continues under the intro, ducked −6 dB, crossfade to `battle` on the first frame of control (crossfade exists, 1.5 s) | existing | 0 |
| Outro bed | `result` track starts under the outro, continues into the results screen | existing | 0 |
| Fortress presence | low rotor/turbine drone that rises with proximity, 2D-positioned (`AudioStreamPlayer2D` as in `sfx.gd`) | Sonniss GDC jets/propellers layers; CC0 | 0.3 day |
| Epilogue | 10 s quiet wind + distant column engines over the black hook card | `ambient_highland.ogg` + layer | 0.2 day |

No voice acting (three languages, budget rule «без найма людей»). If Kanta later wants voices, AI voice would need his
«yes» on spending; the text design does not depend on it.

## 5. Visual effects that carry the story (all reuse existing systems)

- **Contrails and flares in formation** during intros: existing contrail and flare dispenser effects (`flare_dispenser.gdshader`).
- **Column lights / village lights at dusk and night**: emissive tint on existing props via `unit_tint.gdshader`-style
  parameter; headlights as small emissive quads on convoy trucks (same technique as nozzle flames). ~0.5 day, also useful
  for a future night variant of the biome.
- **Green signal flare from the fortress wall** (op 3 outro): existing flare particle with a green tint.
- **Burning Fortress hull on a slope** (op 2 and op 4 outros): the wreck + smoke already exist for destroyed units
  (S10-07 wrecks, `boom3d.gd` smoke); place one at a fixed offset from the camera.
- **Fortress silhouette in the clouds** (op 2 intro): the Fortress battle model above the cloud layer (`clouds.gd`,
  `cloud_puff.gdshader`), unlit from below, flying straight — the cheapest «dread» shot in the game.
- **Slow-motion accent** (M6): `Engine.time_scale` only; no post-process. Optional desaturation for the accent would need
  a full-screen `CanvasLayer` shader — skip unless Kanta asks.
- **Letterbox + captions**: HudKit drawing, tokens from the design system.

## 6. Flow in code (for the implementing thread)

```
Menu → «В вылет» (HudCampaign, vignette)
     → «В ВЫЛЕТ ▶» → Main.start_sortie(): terrain preload as today
     → if Campaign.story_scene_due("intro"): Main.state = "cutscene"; Cutscene.play(def) ; await done/skip
     → Main.state = "playing"; Story.start()
     … sortie (Story.tick: radio; Cinematic.accent(id) for M6) …
     → evacuation: if due: Cutscene.play(outro) → HudResult (+ story line) → (demo: _demo_end overlay)
```

Owners by `architecture.md`: scenes are presentation (3D layer + HUD); flags live in the campaign save through the one
save layer (ADR-07); no writes into `Main` from the scene (ADR-02: emit `Events.cutscene_done`).

## 7. Cost and order

| Step | Content | Thread-days | Needed for the demo? |
| --- | --- | --- | --- |
| P0 | small fixes: «Штаб» → «Купол», `Loc.t` audit, op 4 briefing sentence | 0.3 | yes |
| P1 | story texts (~20 strings), result-screen lines, Graf lines, `.po` EN/ZH drafts | 1 | yes (ops 1–2 part) |
| P2 | `Cutscene` runtime: letterbox, captions, skip, setting, flags, autotest hooks | 2 | yes |
| P3 | intros + outros ops 1–2 (4 scenes) + review page with frames for Kanta | 1.5 | yes |
| P4 | in-combat accents M6 (3) + stingers + radio texture | 1.5 | Fortress sighting only |
| P5 | intros + outros ops 3–4, epilogue card with hook, village/column lights | 2.5 | no |
| P6 | briefing vignette | 0.5 | nice to have |
| **Total** | | **≈ 9.3**, of which **≈ 6** before the demo | |

Checks per `CLAUDE.md`: `smoke.sh all` after every change (scenes run in the autotest, skipped at 0.2 s), `full.sh`
once before merge if combat code (`Engine.time_scale` accent) is touched; unit tests for the flag logic
(`Campaign.story_scene_due`) in `game/tests/`.

## 8. Risks

- **Rule conflict**: «катсцены — нет» is a recorded decision (10.10, 17.10). This concept is the explicit proposal to amend
  it to «короткие заставки в движке, ≤ 15 с, пропускаемые»; without Kanta's «yes» only §3.1–3.3 and the texts are done.
- **Start-up freeze (RV-05)**: on Kanta's PC the sortie start stalls 3–5 s while chunks build. The intro cannot hide a main-thread
  stall; it must start *after* the first visible chunks exist. If RV-05 is not fixed, the intro begins with a fade from black
  of up to 1 s so the stall is not seen as a broken scene.
- **Forward+ vs Compatibility**: dusk/night presets must be tuned in both; `SRGB()` rule for shader constants.
- **Localisation length**: captions in EN/ZH may be longer; the caption area is two lines, 90 chars per line max (same as radio).
- **Performance**: scenes render the same world as the sortie plus ≤ 4 hangar-quality models — the menu does this today at ≤ 60 FPS cap.
