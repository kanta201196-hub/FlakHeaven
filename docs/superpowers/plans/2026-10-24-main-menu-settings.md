# Main menu and settings redesign — plan

Status: **draft, waiting for Kanta's "yes"** (large work: new UI component set, settings system, rebinding). Thread «Переделать главное меню и настройки». Reference: Sublight screenshots sent by Kanta 2026-10-24 (cleaner, easier to read; ours is overloaded). Mockups (1920×1080, real background from the game): gallery artifact linked in the thread.

## Goal
1. Main menu: fewer items, more air, one clear selection style that also works as gamepad focus.
2. Graphics settings: flexible per-option control (antialiasing, shadows, shadow distance/resolution, ambient occlusion and more) on top of quality presets, ready for Forward+ (Kanta 2026-10-24) with a working fallback in Compatibility.
3. Controls tab: full rebinding (two keys + gamepad per action), conflict handling, gamepad options.

## What is wrong today (checked 2026-10-24, build 3.5-s10 code)
- Main menu has 7 buttons of 3 sizes + flight log panel + theater cards + tagline; three visual weights compete (`menu.gd` `_main`).
- Version label reads `3.4-t1` (`Main.BUILD` is stale).
- Settings content overflows the panel at 1600×900 (the default window): last rows sit under the bottom buttons (no scroll, no height-aware layout — design-system defect #4).
- Graphics has one quality switch (4 levels) mixing shadows, MSAA, render scale and terrain density (`Render3D.apply_gfx`); the player cannot turn one thing off.
- Rebinding: keyboard only, one key per action, no conflict check, `skill_2` (F) and mouse buttons not rebindable; HUD hints use hardcoded key names.
- No gamepad focus in menu/settings (CR-05 / CS-11c, Steam Deck blocker).

## Design (mockups)
### Main menu
- Items: **ВЫЛЕТ, АНГАР, СПРАВОЧНИК, НАСТРОЙКИ, ВЫХОД**. «Как играть» becomes a tab in the codex; «Логи» moves to the «Отзыв» card (opens the log folder / report).
- Item = text row, Exo 2 Bold 40 px, letter spacing 0.17 em, hairline dividers, chevron. Parts line from PR #352 stays as a caption under АНГАР, red dot when something can be bought.
- Right column: two cards «Что нового» (build notes, from `WHATS_NEW`) and «Отзыв»; theater as a two-way segmented switch; compact flight log (4 numbers + last sortie).
- Bottom: key hints from the real bindings. No A/B gamepad glyph circles in the hint bars (Kanta, 2026-10-24); the gamepad column stays in the controls tab.
- Logo «FLAK HEAVEN» in one line with the red hazard stripe; tagline removed.
### Selection style — «Прицел» (Kanta chose style 2 on 2026-10-24)
No fill, gunsight corner brackets, orange text, underline. Settings tabs use the same brackets.
Same component for hover, gamepad focus, pressed (0.1 s darker), disabled; 0.12 s wipe-in, off with reduced motion.
### Settings
- Left: tabs as the same menu items (ИГРА, ГРАФИКА, ЗВУК, УПРАВЛЕНИЕ, ИНТЕРФЕЙС). New ИНТЕРФЕЙС tab takes minimap, font, HUD options out of ИГРА/ГРАФИКА.
- Centre: scrolling list (mouse wheel, stick, scrollbar), sections, row = label + control (selector `‹ value ›`, ВКЛ/ВЫКЛ switch, slider).
- Right: description of the focused row: what it does, which renderer, GPU cost bars, before/after frame (rendered by us with `--shots`).
- Most options apply instantly; window mode/resolution show a 10 s "keep these settings?" revert.

## Graphics options (Godot 4.4.1)
F+ = Forward+ only (hidden or shown disabled with a reason under Compatibility). "verify" = check against 4.4.1 docs/engine before coding.

| Section | Option | Values | Engine |
| --- | --- | --- | --- |
| Экран | Режим окна, Разрешение, VSync, Ограничение кадров | as today | DisplayServer, Engine.max_fps |
| Экран | Масштаб отрисовки | 50–100 % | `Viewport.scaling_3d_scale` |
| Экран | Апскейл | Билинейный / FSR 1 / FSR 2 (F+) | `scaling_3d_mode` (FSR 1 in Compatibility: verify) |
| Качество | Общее качество | Низкое / Среднее / Высокое / Максимальное / Своё | preset table |
| Качество | Сглаживание | Выкл / FXAA / MSAA 2×/4×/8× / TAA (F+) | `msaa_3d`, `screen_space_aa` (FXAA in Compatibility: verify), `use_taa` |
| Качество | Снижать качество при низком FPS | ВКЛ/ВЫКЛ | existing `gfx_auto` |
| Тени и свет | Тени | Выкл / Низкие / Средние / Высокие / Ультра | soft shadow filter quality + atlas; "Выкл" only in F+ (Compatibility frame gets darker, see `apply_gfx` note) |
| Тени и свет | Дальность теней | Ближе / Весь экран | multiplier on `_fit_shadow` distance |
| Тени и свет | Разрешение теней | 1024 / 2048 / 4096 / 8192 | `directional_shadow_atlas_set_size` |
| Тени и свет | Фоновое затенение (SSAO) | Выкл / Низкое / Среднее / Высокое (F+) | `Environment.ssao_*`, `RenderingServer.environment_set_ssao_quality` |
| Тени и свет | Отражённый свет (SSIL) | Выкл / Вкл (F+) | `ssil_enabled` |
| Тени и свет | Свечение | ВКЛ/ВЫКЛ | `glow_enabled` (with the VFX thread's glow) |
| Тени и свет | Дымка / объёмный туман | Выкл / Низкая / Высокая (F+) | `volumetric_fog_*` (only if VIS-01 uses it) |
| Детали мира | Детализация рельефа | 4 levels | `Terrain3D.N_GFX` |
| Детали мира | Растительность и камни | 4 levels | `BiomeProps` density |
| Детали мира | Фильтрация текстур | 2× … 16× | project setting anisotropic level (verify runtime change) |
| Эффекты | Качество эффектов | Низкое … Максимальное | caps from `balance/vfx.gd` (thread «Улучшить эффекты боя») |
| Эффекты | Следы и воронки | Мало / Много | decal pool cap (same thread) |
| Эффекты | Резкость | 0–1 (F+ with TAA/FSR) | `Environment`/viewport sharpening (verify) |
| Экран | Счётчик кадров | ВКЛ/ВЫКЛ | existing perf overlay |

Presets are a pure table (`game/scripts/gfx_presets.gd`); changing any option after a preset shows «Своё». Preset numbers get tuned from fps measured on Kanta's PC (RTX 4060) once Forward+ is in the project.

## Controls
- Columns: action · key · alternative key · gamepad. Sections Полёт / Бой / Интерфейс. All gameplay actions from `InputSetup`, including `skill_2`, mouse buttons as keys.
- Capture: Enter/A starts, Esc cancels, Backspace clears. Conflict: warning directly under the row being edited (not elsewhere in the list): "X is already «…» — Enter swaps, Esc cancels".
- Gamepad: rebind buttons/triggers, stick dead zone, vibration on/off, glyph set (auto / Xbox / PlayStation / Steam Deck).
- Saved in `settings.json` as `binds_v2` (action → list of events); old `binds` migrated once.
- `HudKit.key_label(action)` everywhere a key is shown (design system pattern 3).

## Architecture
- `game/scripts/ui_style.gd` — tokens (CS-11b) + `menu_item` component (the selection style) + focus helper (CS-11c). The hangar and codex adopt it later, not in this work.
- `menu.gd` split: `menu_main.gd`, `menu_settings.gd`, `settings_rows.gd` (row widgets + scroll + focus). Still drawn in code (ADR-05).
- `settings.gd`: data-driven option list `{id, section, values, default, needs (renderer), apply}`; save/load with migration.
- Pure logic with unit tests first (TDD): preset → options, «Своё» detection, binding conflicts and swap, settings migration, focus navigation (nearest item in a direction).
- Renderer check: `RenderingServer.get_current_rendering_method()`. Switching the project to Forward+ stays with thread «3D-модели по плану Kirill» (VIS-01); this work runs under both renderers.
- Localization: every new string into `en.po` and `zh_CN.po`, then `subset_font.py`.

## Steps (PRs)
1. `UiStyle` tokens + `menu_item` + focus model; new main menu; version label fix; «Как играть» into the codex. Checks: unit, `smoke.sh fighter`, `--shots` frames at 1920×1080 and 1280×800 (Deck).
2. Settings frame: left tabs, scrolling list, description panel, gamepad, ИНТЕРФЕЙС tab; existing options moved over unchanged.
3. Graphics options + presets (both renderers), before/after frames for the description panel (Forward+ frames on lavapipe in the cloud).
4. Controls: two keys + gamepad, conflicts, migration, key labels in HUD.
5. Remote Control on Kanta's PC: fps per preset in Forward+, tune the preset table, one gallery of results.
Combat code is not touched; `full.sh` only if step 4 changes combat input handling.

## Combat UI: HUD, pause, card pick, results (added 2026-10-24)
More Sublight references from Kanta: large colored skill icons, grid of taken cards with levels, stats tab, per-weapon damage tab (dps with bars), level and timer, mission goals and currency, weapons with target mode ("boss first / optimal"), card descriptions with highlighted terms and nested term tooltips, final screen (damage summary with shares, kills/time, build grid, currency rewards by line). Kanta also recorded a Sublight session (`C:\Users\Kirill-Dom\Videos\Captures\Sublight 2026-10-24 12-41-39.mp4`, 2.2 GB, folder access granted); key frames get extracted on his PC with ffmpeg (Remote Control) at the start of this stage. The video never goes to the cloud.

Icons: the 3D weapon icon style from thread «Углубить прокачку для демо» (weapon model on family-colored glow + family symbol disc). Non-weapon cards (modules, skills, wingmen) get schematic icons in the same frame: a silhouette of what the card does (engine with flame, plane doing a barrel roll, wingmen in formation, radio set, armor plates on the airframe) on the family glow, with the family disc. Mockup v2 has 13 of them; the final art comes from that thread.

### Kanta's feedback on mockup v1 (2026-10-24 10:33) and what v2 changes
- HUD: skill icons did not say what happens and had no names. v2: schematic icon per skill, key cap, name and a short hint line under each; hover/hold shows a tooltip.
- Pause: too close to Sublight. v2: weapon hardpoints with target-mode selectors in the left panel, pause menu under them, no tabs. Stats and damage are always visible (v1 hid them behind Q/E tabs that were not obvious). Wingmen and skills sit under the inventory. Three variants for the inventory/stats block: А «Приборная доска» (round gauges, cards grouped by family, dps in weapon rows), Б «Планшет пилота» (kneeboard list with each card's effect, stat strip, damage-share bar), В «Чертёж самолёта» (modules on leader lines to the part of the airframe they affect, wingmen in formation, stats table and damage list). Kanta picks one.
- Card pick: rarity outline continues along the bevelled corners; schematic icons for non-weapon cards.
- Results: «Эвакуация» is the title at the top with the operation line under it; the blocks moved lower.

| Screen | Today (3.5-s10) | Proposed |
| --- | --- | --- |
| HUD | text skill panels top-left, level small, timer top-right with goal lines, weapon chip bottom | thin XP bar on top; level + timer framed top centre; hull/fuel top-left; parts and kills counters top-right with mission goals and rewards under them; bottom centre bar: weapon groups (big icon, level, reload, target mode) + skills (icon, key, cooldown) |
| Pause | text list of hardpoints, tag grid, 120 colored text chips | left: hardpoints (icon, level pips, `‹ target mode ›`), pause menu under them (Continue / Settings / Codex / Leave sortie); right: inventory + stats + damage in one of the variants А/Б/В, wingmen and skills under the inventory; no tabs |
| Card pick | 2×2 wide cards, small icon, long text | 4 tall cards in a row: rarity header, big icon, name in rarity color, level pips, 2-line text with highlighted terms; hovering a term opens a tooltip (term → explanation, can nest); reroll/lock/ban below; gamepad focus = selected card lifted |
| Results | title + 3 tabs (overview / damage / build) | one screen: damage summary (numbered, icon, share, value, family-colored bar) left; result title + kills/time/level/aces centre; build grid + parts reward lines + total + crew XP bar right; "details" opens damage taken |

Data needed (no rule changes): dps over the last 60 s per source (pause damage block), term dictionary for tooltips (`game/scripts/terms.gd`, keys in `.po`), icon id per card. Rewards and goals show the numbers the game already computes.

Steps (after step 4 above, or in parallel by a second thread if Kanta wants):
6. Video frames from Kanta's PC; HUD rebuild (combat code: `full.sh` once).
7. Pause screen in the variant Kanta picks (А/Б/В).
8. Card pick screen with terms and tooltips (unit tests for term markup parsing).
9. Results screen.

## Needs from outside (asked up front)
1. Gamepad button glyphs: Kenney «Input Prompts» (CC0, free) — art asset, needs Kanta's "yes".
2. UI sounds (hover, click, back): Kenney «UI Audio» (CC0, free) or keep silent — audio, needs Kanta's "yes".
3. Fonts: none — Exo 2 (already in the game, OFL) covers headings and menu items.
4. Kanta's PC (Remote Control): step 5 (fps per preset, after Forward+) and step 6 (frames from the Sublight video).

## Open questions for Kanta
1. Pause inventory/stats block: А «Приборная доска», Б «Планшет пилота» (recommended: most readable, every card says what it gives), В «Чертёж самолёта».
2. Menu items and moves («Как играть» → codex, «Логи» → «Отзыв» card): yes/no.
3. Flight log on the main screen: compact card (recommended) or only in the codex.
4. Combat UI order: after the menu and settings (recommended) or in parallel in a separate thread.
5. Kenney Input Prompts and UI Audio (CC0): yes/no each.
