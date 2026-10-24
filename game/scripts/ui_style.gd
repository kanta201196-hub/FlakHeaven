class_name UiStyle
extends RefCounted
## Design tokens and shared drawing for every screen drawn in code (CS-11b,
## docs/standards/ui-design-system.md §2–3). Colours, font sizes and spacing come from here,
## not from literals. Also draws the selection style «Прицел» (gunsight corner brackets,
## chosen by Kanta on 2026-10-24) used by the main menu and, later, settings and combat
## screens. Static only; screens pass their CanvasItem in.

# ---------- Colour ----------
## Primary accent: selected item, hover/focus border, primary button
const ACCENT := Color(0.95, 0.66, 0.2)
## Gold, only for screen and section headings on dark
const ACCENT_SOFT := Color(1.0, 0.82, 0.29)
## Inactive accent, pressed fill
const ACCENT_DIM := Color(0.55, 0.36, 0.1)
## Text on an amber fill
const ON_ACCENT := Color(0.08, 0.07, 0.05)
## Primary text in combat and screens
const TEXT := Color(0.92, 0.95, 1.0)
## Primary text in the main menu (warm title theme)
const TEXT_WARM := Color(0.92, 0.9, 0.84)
## Secondary text, captions
const TEXT_2 := Color(0.75, 0.8, 0.9)
## Muted caption on the warm menu theme
const TEXT_DIM := Color(0.62, 0.62, 0.56)
## Disabled, locked
const TEXT_OFF := Color(0.6, 0.62, 0.68)
const OK := Color(0.6, 1.0, 0.7)
const DANGER := Color(1.0, 0.35, 0.3)
## Brand red: hazard stripe, «something to buy» dot
const BRAND_RED := Color(0.85, 0.24, 0.18)
const PARTS := Color(0.95, 0.85, 0.55)
const PANEL := Color(0.085, 0.095, 0.085, 0.95)
## Hairline dividers and quiet borders on the warm theme
const LINE := Color(0.85, 0.82, 0.72, 0.22)
const SCRIM := Color(0.02, 0.03, 0.025, 0.88)
const OUTLINE := Color(0.02, 0.025, 0.03, 0.85)

# ---------- Type ----------
## Floor for any text: 14 × 0.667 ≈ 9.3 px on the Steam Deck
const FS_MIN := 14
const FS_CAPTION := 14
const FS_BODY := 16
const FS_LABEL := 18
const FS_H3 := 22
const FS_H2 := 28
const FS_H1 := 40
const FS_HERO := 54

# ---------- Spacing and shape ----------
const SP_1 := 4
const SP_2 := 8
const SP_3 := 12
const SP_4 := 16
const SP_5 := 24
const SP_6 := 32
const SP_7 := 48
const SP_8 := 64
## Screen margin on menus and full screens
const MARGIN := 64
const PAD := 16
## Panel corner cut
const CUT := 14.0
const BORDER := 1.5
const BORDER_FOCUS := 2.5
## Gunsight bracket arm length and thickness for the «Прицел» selection
const BRACKET := 18.0
const BRACKET_W := 3.0
## Selection wipe-in time, seconds (0.12 s, off with reduced motion later)
const WIPE_S := 0.12
## Letter spacing of menu items and headings, px per glyph (≈ 0.17 em at 40 px)
const TRACKING := 6

static var _heads := {}


## Exo 2 at the given weight with letter spacing, for menu items, tabs and headings
## (plan: Exo 2 covers headings, the body font follows `Settings.font`). Cached per pair;
## Chinese falls back to the bundled Noto Sans SC subset like the body font.
static func head_font(weight := 700, tracking := TRACKING) -> Font:
	var key := weight * 100 + tracking
	if _heads.has(key):
		return _heads[key]
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/exo2_variable.ttf")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	fv.spacing_glyph = tracking
	fv.fallbacks = [load("res://fonts/noto_sans_sc_subset.ttf")]
	_heads[key] = fv
	return fv


## Width of a string as drawn (after `Loc.out`), for layout of carets, underlines and caps.
static func text_w(font: Font, s: String, size: int) -> float:
	return font.get_string_size(Loc.out(s), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(size, FS_MIN)).x


## Draws translated text, clamping the size to FS_MIN (design system §2.2).
static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	ci.draw_string(font, pos, Loc.out(s), align, width, maxi(size, FS_MIN), color)


## Four gunsight corner brackets around `r`. `k` (0…1) is the wipe-in progress: brackets
## start BRACKET px outside and settle on the corners.
static func brackets(ci: CanvasItem, r: Rect2, color: Color, k := 1.0) -> void:
	var o := (1.0 - clampf(k, 0.0, 1.0)) * BRACKET
	var g := r.grow(o)
	var a := BRACKET
	var w := BRACKET_W
	for c: Vector2 in [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]:
		var sx := 1.0 if c.x == g.position.x else -1.0
		var sy := 1.0 if c.y == g.position.y else -1.0
		ci.draw_rect(Rect2(minf(c.x, c.x + sx * a), minf(c.y, c.y + sy * w), a, w), color)
		ci.draw_rect(Rect2(minf(c.x, c.x + sx * w), minf(c.y, c.y + sy * a), w, a), color)


## One row of a vertical menu in the «Прицел» style. `focus` (0…1) is the selection
## wipe-in: 0 = plain row, 1 = fully selected (brackets on the corners, amber label with a
## diamond and underline, amber chevron). `note` is a caption under the label, `badge` a red
## dot after it («something to buy»). Disabled rows are grey and have no chevron.
static func menu_item(ci: CanvasItem, r: Rect2, label: String, focus: float, enabled := true,
		note := "", badge := false, pressed := false, size := FS_H1) -> void:
	var font := head_font(700)
	var on := enabled and focus > 0.0
	ci.draw_line(Vector2(r.position.x, r.end.y), r.end, LINE, 1.0)
	if pressed and enabled:
		ci.draw_rect(r, Color(ACCENT_DIM.r, ACCENT_DIM.g, ACCENT_DIM.b, 0.55))
	elif on:
		ci.draw_rect(r, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.06 * focus))
	var tc := (TEXT_WARM.lerp(ACCENT, focus) if enabled else TEXT_OFF)
	var lx := r.position.x + 34.0
	var base := r.position.y + (r.size.y * 0.52 if note != "" else r.size.y * 0.5) + size * 0.36
	text(ci, font, Vector2(lx, base), label, size, tc)
	var lw := text_w(font, label, size)
	if badge and enabled:
		ci.draw_circle(Vector2(lx + lw + 14.0, base - size * 0.42), 5.0, BRAND_RED)
	if note != "":
		text(ci, head_font(600, 2), Vector2(lx + 2.0, base + 22.0), note, FS_CAPTION,
			Color(tc.r, tc.g, tc.b, 0.7) if on else TEXT_DIM)
	if enabled:
		text(ci, font, Vector2(r.end.x - 48.0, base), "›", size * 3 / 4, tc)
	if on:
		var k := focus
		ci.draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + 12, base - size * 0.36),
			Vector2(r.position.x + 18, base - size * 0.36 - 6), Vector2(r.position.x + 24, base - size * 0.36),
			Vector2(r.position.x + 18, base - size * 0.36 + 6)]), Color(ACCENT.r, ACCENT.g, ACCENT.b, k))
		if note == "":
			ci.draw_rect(Rect2(lx, base + 10.0, lw * k, 2.5), ACCENT)
		brackets(ci, r, Color(ACCENT.r, ACCENT.g, ACCENT.b, k), k)


## Keyboard key cap with a caption after it («ENTER  ОТКРЫТЬ»); returns the x after the pair.
static func key_hint(ci: CanvasItem, pos: Vector2, key: String, caption: String) -> float:
	var kf := head_font(700, 1)
	var cf := head_font(600, 3)
	var kw := maxf(32.0, text_w(kf, key, FS_CAPTION) + 18.0)
	var kr := Rect2(pos.x, pos.y - 21.0, kw, 28.0)
	ci.draw_rect(kr, Color(0.06, 0.065, 0.06, 0.85))
	ci.draw_rect(kr, Color(TEXT_WARM.r, TEXT_WARM.g, TEXT_WARM.b, 0.55), false, 1.5)
	text(ci, kf, Vector2(kr.position.x, pos.y - 1.0), key, FS_CAPTION, TEXT_WARM, HORIZONTAL_ALIGNMENT_CENTER, kw)
	text(ci, cf, Vector2(kr.end.x + 10.0, pos.y), caption, FS_BODY, TEXT_DIM)
	return kr.end.x + 10.0 + text_w(cf, caption, FS_BODY) + 34.0


## Panel with a cut top-right corner; the border follows the cut (Kanta 2026-10-24: every
## bevel carries the outline).
static func panel(ci: CanvasItem, r: Rect2, border := LINE, fill := PANEL, cut := CUT, width := BORDER) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x - cut, r.position.y),
		Vector2(r.end.x, r.position.y + cut), r.end, Vector2(r.position.x, r.end.y)])
	ci.draw_colored_polygon(pts, fill)
	pts.append(r.position)
	ci.draw_polyline(pts, border, width)
