# Decal editor (hangar) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** A «Знаки ›» editor in the hangar's plane tab where the player puts decals anywhere on the plane — place, move, scale, rotate, mirror, recolour, reorder, delete, presets, «на другой борт» — with mouse or gamepad.

**Architecture:** Editing state and rules live in a pure `DecalEditor` (RefCounted, unit-tested). `Hangar3D` gets an editor mode: the cursor ray onto the hull (`PlaneHull.raycast` in model axes), a cheap live preview mesh for the decal under the cursor, the committed decals rebuilt through `PlaneDecals.show`. `HudDecals` (HudKit) draws the panel in place of the node cards; `MainInput` routes `hg:dc:*` clicks and the editor's keys and gamepad.

**Tech Stack:** Godot 4.4.1, GDScript (typed), immediate-mode HudKit UI, gettext `.po`.

**Spec:** `docs/superpowers/specs/2026-10-27-plane-decals-design.md` (§4 placement, §6 hangar UX, §7 unlocks).

## Global Constraints

- Cap 12 decals per plane (`DecalLoadout.MAX_DECALS`); size `DecalRecord.SIZE_MIN … SIZE_MAX`; number 1–3 digits.
- Locked pictures (`Profile.decal_open` false) cannot be placed; shown dimmed with «откроется: …».
- Changes are free and instant; written to the profile (`Profile.set_decals`) on every commit, saved to disk (`Profile.save`) when the editor closes.
- Player text through `Loc.t` / HudKit (`.po` key = the Russian phrase), font ≥ 14, colours from `UiStyle`/`Menu.C_*` like the rest of the hangar; key hints via `HudKit.key_label`.
- Esc / B leaves the editor (not the hangar); any other hangar action closes the editor first (saved).
- No balance, money or art changes; the atlas stays as it is.

## Review Focus

1. Placing on a spot the ray misses (sky, glass): nothing is placed, no error — `DecalEditor.place` with an empty hit returns false.
2. Cap reached: picking a 13th picture says why and places nothing.
3. Switching class, plane level, livery or tab with the editor open: the editor closes and saves; the model rebuild shows the same decals.
4. A tally decal with 0 kills: invisible in combat, so the editor previews it with a few marks (`DecalEditor.PREVIEW_TALLY`) and says the real count.
5. Gamepad only: every action reachable (cursor on the stick, A/B/X/Y, triggers, bumpers, d-pad over the panel).

---

### Task 1: DecalEditor — editing state and rules

**Files:** Create `game/scripts/decal_editor.gd`; Test `game/tests/decals_cases.gd` (new `_test_editor`).

**Interfaces — produces:**
- `class_name DecalEditor extends RefCounted`; consts `ROT_STEP := PI / 12`, `ROT_FINE := PI / 90`, `SCALE_STEP := 1.1`, `PREVIEW_TALLY := 5`, `GRAB_K := 0.6`.
- `var cls: String`, `var lvl: int`, `var records: Array[DecalRecord]`, `var sel := -1`, `var tool := ""` (picture being placed, "" when none), `var moving := false`, `var size := 0.04`, `var angle := 0.0`, `var mirror := false`, `var c1 := DecalCatalog.DEFAULT_C1`, `var c2 := DecalCatalog.DEFAULT_C2`, `var text := "01"`, `var changed := false`.
- `func open(c: String, lv: int, list: Array[DecalRecord]) -> void`
- `func pick(id: String, is_open: bool) -> String` — "" when the tool is set, else the refusal reason key ("locked", "cap").
- `func preview(hit: Array) -> DecalRecord` — the record that a click at `hit` ([pos, normal]) would place or move to; null on an empty hit or no tool / no moving decal.
- `func place(hit: Array) -> bool` — adds `preview(hit)`, selects it, keeps the tool for the next stamp.
- `func select_at(pos: Vector3) -> int` — the topmost record whose centre is within `size * GRAB_K` of `pos` (last drawn wins), selects it; -1 none.
- `func grab() -> bool` / `func drop(hit: Array) -> bool` — move the selected record (hidden from `shown()` while moving).
- `func scale_by(steps: int)`, `func rotate_by(steps: int, fine := false)`, `func toggle_mirror()`, `func set_paint(slot: int, id: String)`, `func next_paint(slot: int)`, `func set_text(s: String)` — act on the selected record, or on the tool settings when nothing is selected.
- `func remove() -> void`, `func order(delta: int) -> void`, `func other_side(hull: PlaneHull) -> bool`, `func preset(hull: PlaneHull, key: String, spot: String, side: int) -> bool`.
- `func shown() -> Array[DecalRecord]` — records to draw now (without the one being moved).

- [x] Write `_test_editor`: open/pick/place/select/grab/drop/scale clamps/rotate wraps/mirror keeps numbers readable/paint cycling/text digits/remove/order/cap refusal/locked refusal/empty hit/other_side/preset/shown while moving.
- [x] Run `godot --headless --path game -s res://tests/decals_test.gd`: fails (no class).
- [x] Implement `decal_editor.gd`; `godot --headless --path game --import`; run the test: passes.
- [x] Commit.

### Task 2: PlaneDecals — show any record list, preview mesh, badges come back

**Files:** Modify `game/scripts/plane_decals.gd`.

**Interfaces — produces:**
- `static func show(model: Node3D, key: String, records: Array[DecalRecord], tally: int) -> void` — sets the records on the insignia node and rebuilds (empty list clears the mesh, hidden badges come back).
- `static func show_preview(model: Node3D, r: DecalRecord, tally: int) -> void` — one-record mesh «decal_preview» (highlight tint), null record hides it.
- `static func hull_of(model: Node3D) -> PlaneHull` — the skin with fairings (what the decals are cut from); used by the cursor.
- `material(highlight := 0.0)` gains a `highlight` uniform (pulsing light rim for the selected decal).

- [x] Implement; covered by the frames of Task 5 (node code, no unit test).

### Task 3: Hangar3D editor mode

**Files:** Modify `game/scripts/hangar3d.gd` (new section at the end, small hooks in `_process` and `_input`).

**Interfaces — produces:** `var decal_mode := false`; `func decal_ray(p: Vector2) -> Array` (screen point in ctrl coords → [pos, normal] in model axes, or []); `func decal_refresh(records: Array[DecalRecord], preview: DecalRecord, tally: int)`; `func orbit(dx: float, dy: float)`; `func model_key() -> String`. In decal mode: no idle spin, no sway, left button is the editor's (MainInput), right-drag orbits.

- [x] Implement; check with the bench frames (Task 5).

### Task 4: HudDecals panel, hangar wiring, input, translations

**Files:** Create `game/scripts/hud_decals.gd`; Modify `game/scripts/hud_hangar.gd` (`_hg_livery` row: «Знаки ›»; `_hg_plane`: right column → `HudDecals.draw` while open), `game/scripts/main_input.gd` (`hangar_action` `dc:*`, editor keys and gamepad in `handle_global_input`), `game/scripts/main.gd` (`var decal_edit: DecalEditor`), `game/locale/en.po`, `game/locale/zh_CN.po`.

- [x] Panel: decal list (≤ 12 rows: select, ▲ ▼, ✕), picture grid (locked dimmed + «откроется: …»), presets (Нос · Номер · Счёт · Киль · Крыло, борт Л / П), two paint rows, number digits, Отразить · На другой борт · Удалить, help line with key labels, «‹ Назад».
- [x] Mouse: click in the view places / selects / drags; wheel scales the selected decal (else zooms); Q / E rotate (Shift — fine); F mirror; Del delete; right-drag orbits.
- [x] Gamepad: left stick — cursor (slower over the plane), A place / pick up / drop, B drop selection / back, LT / RT scale, LB / RB rotate, X mirror, Y next paint, right stick — camera, d-pad — panel focus, A on a focused panel button presses it.
- [x] `python3 tools/i18n/check_po.py game/locale/en.po --sync` (and zh_CN), fill the new strings; `check_po.py` exit 0.

### Task 5: Bench frames and checks

**Files:** Modify `game/scripts/visual_bench.gd` (`--decaledit` hangar shot: the editor open with sample decals, a selected decal and the cursor preview).

- [x] Frames (Forward+, JPEG, page in the scratchpad): the editor panel, the cursor preview on a curved nose, a selected decal; gamepad cursor.
- [x] `--import`, `unit.sh`, `smoke.sh all`, `full.sh` with exit codes; push; report.

## As built (differences from the plan)

- Input lives in its own `DecalEditInput` (`game/scripts/decal_edit_input.gd`, owned by `MainInput.dc`): `MainInput` only routes `hg:dc:*` to it and calls `frame()` while the hangar is open. The gamepad is read raw (first pad), because the combat actions also carry mouse and keyboard binds (the left button fires).
- `Hangar3D` reports the editor's left button and wheel by signals (`decal_press`, `decal_wheel`); `decal_close(key, …)` restores the real tally only when that plane is still on view.
- The cursor stops on the canopy glass (`PlaneHull.glass_of`, `raycast_clear`, unit-tested): before, a decal could be put on the skin under the glass, where it is hidden.
- Help line: keyboard words by default, gamepad words while the pad moved the cursor (no glyphs).

