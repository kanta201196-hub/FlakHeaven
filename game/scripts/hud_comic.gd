class_name HudComic
extends HudKit
## Draws a story scene as a living comic page (ST-12, plan `docs/superpowers/plans/2026-11-07-comic-cutscenes.md`;
## Kanta 07.11 «вариант 2»). The page (`StoryComic.PAGES`) is a 16:9 sheet fitted to the screen: panels slide in at
## their times inside white borders, each picture pushes in slowly, and the engine animates life inside a panel
## (smoke, dust, glow and flicker, flak bursts, tracers, rain, a marker ring). Captions sit in yellow plates, the
## scene's radio lines become speech balloons next to the speaker's portrait, sound words punch in, and a panel
## marked `shake` jolts the page when it lands. Everything is a function of scene time (`ComicKeys`), so a frame is
## the same on every machine. Drawn in code like every screen (ADR-05); `HudCutscene` adds the skip hint and fades.

const PAGE_ASPECT := 16.0 / 9.0
const MARGIN := 0.02             # share of the screen height around the page
const BORDER := 0.0045           # panel border, share of the page width
const PAPER := Color(0.96, 0.93, 0.86)
const INK := Color(0.07, 0.06, 0.055)
const PAGE_BG := Color(0.085, 0.075, 0.07)
const CAPTION := Color(0.95, 0.84, 0.35)
const BALLOON := Color(1.0, 0.99, 0.96)
const ENEMY_BG := Color(0.24, 0.06, 0.06)
const ENEMY_TEXT := Color(1.0, 0.86, 0.82)
const SLIDE_DROP := 0.03         # share of the page height a panel drops from while sliding in
const SFX_DELAY := 0.55          # s after a panel lands before its sound word pops
const PUFF_LIFE := 3.2           # s a smoke or dust puff lives
const FLAK_PERIOD := 1.7         # s between bursts of one flak slot
const TRACER_PERIOD := 0.75      # s a tracer takes to cross its path
const RAIN_LINES := 70

var _box: StyleBoxFlat


## Draws page `key` at scene time `t` over the whole `size` screen; `textures` maps image paths to loaded textures,
## `scene` is the scene definition (its lines feed captions and balloons).
func draw(size: Vector2, key: String, t: float, scene: Dictionary, textures: Dictionary) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), PAGE_BG)
	var page: Dictionary = StoryComic.PAGES.get(key, {})
	if page.is_empty():
		return
	var area := _page_rect(size)
	var panels: Array = page["panels"]
	var shake := Vector2.ZERO
	for p in panels:
		if bool((p as Dictionary).get("shake", false)):
			shake += ComicKeys.shake(t, float(p["t"]) + ComicKeys.SLIDE * 0.6)
	area.position += shake * (area.size.y / 1080.0)
	var dur := float(scene.get("dur", 1.0))
	var lines: Array = scene.get("lines", [])
	var overlays: Array = []   # balloons and sound words go over every panel, drawn last
	for p in panels:
		var pd: Dictionary = p
		var u := ComicKeys.panel_in(t, float(pd["t"]))
		if u <= 0.0:
			continue
		var r: Array = pd["rect"]
		var outer := Rect2(area.position + Vector2(float(r[0]), float(r[1])) * area.size, Vector2(float(r[2]), float(r[3])) * area.size)
		outer.position.y += (1.0 - u) * SLIDE_DROP * area.size.y
		var a := clampf(u * 1.6, 0.0, 1.0)
		var b := area.size.x * BORDER
		var inner := outer.grow(-b)
		ctrl.draw_rect(outer, Color(PAPER, a))
		ctrl.draw_rect(inner, Color(0, 0, 0, a))
		var tex: Texture2D = textures.get(String(pd["img"]))
		var src := Rect2()
		if tex != null:
			var s: Array = pd["src"]
			src = ComicKeys.cover(Rect2(float(s[0]), float(s[1]), float(s[2]), float(s[3])), inner.size.x / maxf(inner.size.y, 1.0))
			src = ComicKeys.push_src(src, pd.get("push", []), t - float(pd["t"]), maxf(dur - float(pd["t"]), 0.1))
			ctrl.draw_texture_rect_region(tex, inner, src, Color(1, 1, 1, a))
			for f in pd.get("fx", []):
				if String((f as Dictionary)["k"]) == "fly":
					_fly(f, inner, t - float(pd["t"]), a, textures)
				else:
					_fx(f, inner, src, t, a)
		if pd.has("cap"):
			var c: Array = pd["cap"]
			var text := String(StoryComic.NAME_CAPS.get(key, "")) if int(c[0]) < 0 else _line_text(lines, int(c[0]))
			if text != "" and t >= _line_start(lines, int(c[0]), float(pd["t"])):
				_caption(inner.position + Vector2(float(c[1]), float(c[2])) * inner.size, text, area.size.y, a, inner)
		if pd.has("say"):
			overlays.append(["say", pd, outer])
		if pd.has("sfx"):
			overlays.append(["sfx", pd, inner])
	for o in overlays:
		if o[0] == "say":
			_balloon(o[1], o[2], area, lines, t)
		else:
			_sfx(o[1], o[2], area.size.y, t)


## The 16:9 page inside the screen with a small margin, centred.
static func _page_rect(size: Vector2) -> Rect2:
	var m := size.y * MARGIN
	var avail := size - Vector2(m, m) * 2.0
	var w := minf(avail.x, avail.y * PAGE_ASPECT)
	var h := w / PAGE_ASPECT
	return Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))


static func _line_text(lines: Array, i: int) -> String:
	return String((lines[i] as Array)[3]) if i >= 0 and i < lines.size() else ""


## When line `i` starts; a caption without a line (`i` < 0) shows with its panel at `fallback`.
static func _line_start(lines: Array, i: int, fallback: float) -> float:
	return float((lines[i] as Array)[0]) if i >= 0 and i < lines.size() else fallback


## A texture point (px) inside the panel on screen, through the panel's current crop `src`.
static func _map(p: Vector2, inner: Rect2, src: Rect2) -> Vector2:
	return inner.position + (p - src.position) / src.size * inner.size


func _fx(f: Dictionary, inner: Rect2, src: Rect2, t: float, a: float) -> void:
	var k := inner.size.x / maxf(src.size.x, 1.0)   # texture px → screen px
	var seed := int(f.get("at", Vector2.ZERO).x) + int(f.get("at", Vector2.ZERO).y) * 7
	match String(f["k"]):
		"smoke", "dust":
			var c: Color = f["c"]
			var dust := String(f["k"]) == "dust"
			for i in int(f.get("n", 6)):
				var pf := ComicKeys.puff(f["at"], f["drift"], i + seed, t, PUFF_LIFE)
				var pos := _map(pf[0], inner, src)
				var rad := float(f["r"]) * float(pf[1]) * k
				if inner.grow(-rad * 0.3).has_point(pos):
					var al := float(pf[2]) * a * (0.32 if dust else 0.6)
					ctrl.draw_circle(pos, rad, Color(c, al))
					if not dust:
						ctrl.draw_arc(pos, rad, 0.0, TAU, 20, Color(INK, al * 0.6), maxf(1.0, rad * 0.06))
		"glow":
			var c: Color = f["c"]
			var fl := float(f.get("flick", 0.3))
			var w := 1.0 - fl * 0.5 * (1.0 + sin(t * 23.0 + seed) * sin(t * 7.3 + seed * 0.5))
			var pos := _map(f["at"], inner, src)
			var rad := float(f["r"]) * k
			if inner.has_point(pos):
				for i in 4:
					var q := 1.0 - i * 0.22
					ctrl.draw_circle(pos, rad * (1.6 - i * 0.35) * (0.85 + 0.15 * w), Color(c, a * 0.16 * w / q))
				ctrl.draw_circle(pos, rad * 0.22 * (0.8 + 0.2 * w), Color(1, 1, 0.92, a * 0.7 * w))
		"flak":
			var area: Rect2 = f["area"]
			for i in int(f.get("n", 3)):
				var phase := t / FLAK_PERIOD + ComicKeys.rand01(seed, i) * 3.0
				var cycle := int(floor(phase))
				var s := (phase - cycle) * FLAK_PERIOD
				var at := area.position + Vector2(ComicKeys.rand01(cycle, i * 2 + 1), ComicKeys.rand01(cycle, i * 2 + 2)) * area.size
				var pos := _map(at, inner, src)
				if not inner.grow(-6.0).has_point(pos):
					continue
				var rad := (14.0 + 26.0 * minf(s / 0.5, 1.0)) * k
				var fade := clampf(1.0 - (s - 0.4) / 1.0, 0.0, 1.0)
				if s < 0.12:
					ctrl.draw_circle(pos, rad * 1.3, Color(1.0, 0.85, 0.45, a * 0.9))
				ctrl.draw_circle(pos, rad, Color(0.09, 0.08, 0.08, a * 0.75 * fade))
				ctrl.draw_arc(pos, rad, 0.0, TAU, 18, Color(INK, a * 0.5 * fade), maxf(1.0, rad * 0.08))
		"tracer":
			var c: Color = f["c"]
			var pa := _map(f["a"], inner, src)
			var pb := _map(f["b"], inner, src)
			for i in int(f.get("n", 3)):
				var u := fposmod(t / TRACER_PERIOD + float(i) / float(f.get("n", 3)), 1.0)
				var p0 := pa.lerp(pb, u)
				var p1 := pa.lerp(pb, minf(u + 0.12, 1.0))
				if inner.has_point(p0) and inner.has_point(p1):
					ctrl.draw_line(p0, p1, Color(c, a * 0.5), maxf(2.0, 6.0 * k))
					ctrl.draw_line(p0, p1, Color(1, 1, 0.9, a), maxf(1.0, 2.5 * k))
		"rain":
			for i in RAIN_LINES:
				var x := inner.position.x + ComicKeys.rand01(i, 11) * inner.size.x
				var y := inner.position.y + fposmod(t * 0.9 + ComicKeys.rand01(i, 12), 1.0) * inner.size.y
				var d := Vector2(-0.18, 1.0) * inner.size.y * 0.05
				if inner.has_point(Vector2(x, y) + d):
					ctrl.draw_line(Vector2(x, y), Vector2(x, y) + d, Color(0.75, 0.82, 0.95, a * 0.35), 1.5)
		"ring":
			var pos := _map(f["at"], inner, src)
			var rad := float(f["r"]) * k * (1.0 + 0.08 * sin(t * 5.0))
			ctrl.draw_arc(pos, rad, 0.0, TAU, 40, Color(UiStyle.DANGER, a * 0.9), maxf(2.0, 5.0 * k))
			ctrl.draw_arc(pos, rad * 1.25, 0.0, TAU, 40, Color(UiStyle.DANGER, a * 0.35), maxf(1.0, 2.0 * k))


## A cut-out jet crossing the panel (`ComicKeys.fly`), cut at the panel edge, with a faint speed streak behind it.
func _fly(f: Dictionary, inner: Rect2, life: float, a: float, textures: Dictionary) -> void:
	var tex: Texture2D = textures.get(String(f["img"]))
	if tex == null:
		return
	var st := ComicKeys.fly(life, float(f["t0"]), float(f["t1"]), f["from"], f["to"], float(f["s0"]), float(f["s1"]))
	var al := float(st[2]) * a
	if al <= 0.0:
		return
	var ts := tex.get_size()
	var h := float(st[1]) * inner.size.y
	var sz := Vector2(h * ts.x / ts.y, h)
	var centre := inner.position + (st[0] as Vector2) * inner.size
	var back := ComicKeys.fly(life - 0.12, float(f["t0"]), float(f["t1"]), f["from"], f["to"], float(f["s0"]), float(f["s1"]))
	var prev := inner.position + (back[0] as Vector2) * inner.size
	if prev.distance_to(centre) > 2.0:
		var d := (centre - prev).normalized()
		for i in 3:
			var o := d.orthogonal() * (i - 1) * h * 0.18
			var p0 := centre - d * h * 1.6 + o
			if inner.has_point(p0) and inner.has_point(centre + o):
				ctrl.draw_line(p0, centre - d * h * 0.3 + o, Color(1, 1, 1, al * 0.18), maxf(1.0, h * 0.02))
	var cut := ComicKeys.clip_sprite(Rect2(centre - sz * 0.5, sz), inner, ts)
	if not cut.is_empty():
		ctrl.draw_texture_rect_region(tex, cut[0], cut[1], Color(1, 1, 1, al))


## Yellow caption plate with a hard ink shadow, top-left at `pos`, kept inside the panel.
func _caption(pos: Vector2, text: String, page_h: float, a: float, inner: Rect2) -> void:
	var font := UiStyle.head_font(700, 1)
	var fs := maxi(12, int(page_h * 0.027))
	var s := Loc.out(text).to_upper()
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := Vector2(fs * 0.6, fs * 0.35)
	var box := Rect2(pos, Vector2(w, fs * 1.1) + pad * 2.0)
	box.position.x = clampf(box.position.x, inner.position.x + 4.0, maxf(inner.position.x + 4.0, inner.end.x - box.size.x - 4.0))
	var sh := maxf(2.0, fs * 0.18)
	ctrl.draw_rect(Rect2(box.position + Vector2(sh, sh), box.size), Color(INK, a))
	ctrl.draw_rect(box, Color(CAPTION, a))
	ctrl.draw_rect(box, Color(INK, a), false, maxf(1.5, fs * 0.08))
	ctrl.draw_string(font, box.position + Vector2(pad.x, pad.y + fs * 0.88), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK, a))


## Speech balloon of panel `pd`: the latest of its lines that has started, with the speaker on top; an enemy voice
## gets the dark red balloon. The tail points at the speaker's panel; the balloon pops from the tail.
func _balloon(pd: Dictionary, panel: Rect2, area: Rect2, lines: Array, t: float) -> void:
	var say: Array = pd["say"]
	var line: Array = []
	for i in say[0]:
		var ii := int(i)
		if ii < lines.size() and t >= float((lines[ii] as Array)[0]):
			line = lines[ii]
	if line.is_empty():
		return
	var sc := ComicKeys.pop(t, float(line[0]), 0.0)
	if sc <= 0.0:
		return
	var enemy := line.size() > 4 and bool(line[4])
	var font := ui_font()
	var head := UiStyle.head_font(800, 1)
	var fs := maxi(12, int(area.size.y * 0.03))
	var hs := maxi(10, int(fs * 0.68))
	var width := float(say[3]) * area.size.x
	var pad := fs * 0.75
	var text := Loc.out(String(line[3]))
	var th := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width - pad * 2.0, fs).y
	var box := Rect2(area.position + Vector2(float(say[1]), float(say[2])) * area.size, Vector2(width, th + hs * 1.4 + pad * 2.0))
	box.position.x = clampf(box.position.x, area.position.x + 6.0, area.end.x - box.size.x - 6.0)
	box.position.y = clampf(box.position.y, area.position.y + 6.0, area.end.y - box.size.y - 6.0)
	# tail: from the balloon edge nearest the speaker panel's centre toward it
	var target := panel.get_center()
	var below := target.y > box.end.y
	var base_y := box.end.y if below else box.position.y
	var bx := clampf(target.x, box.position.x + box.size.x * 0.18, box.end.x - box.size.x * 0.18)
	var tip := Vector2(bx, base_y) + (target - Vector2(bx, base_y)).normalized() * fs * 1.6
	var pivot := Vector2(bx, base_y)
	ctrl.draw_set_transform(pivot * (1.0 - sc), 0.0, Vector2(sc, sc))
	var bg := ENEMY_BG if enemy else BALLOON
	var edge := UiStyle.DANGER if enemy else INK
	if _box == null:
		_box = StyleBoxFlat.new()
		_box.anti_aliasing = true
	_box.bg_color = bg
	_box.border_color = edge
	_box.set_border_width_all(maxi(2, int(fs * 0.12)))
	_box.set_corner_radius_all(int(fs * 1.0))
	var tw := fs * 0.55
	var tri := PackedVector2Array([Vector2(bx - tw, base_y), tip, Vector2(bx + tw, base_y)])
	ctrl.draw_colored_polygon(tri, bg)
	ctrl.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2]]), edge, maxf(2.0, fs * 0.12), true)
	ctrl.draw_style_box(_box, box)
	ctrl.draw_line(Vector2(bx - tw + 2.0, base_y), Vector2(bx + tw - 2.0, base_y), bg, maxf(3.0, fs * 0.2))
	var speaker := Loc.out(String(line[2])).to_upper()
	ctrl.draw_string(head, box.position + Vector2(pad, pad + hs), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, UiStyle.DANGER if enemy else UiStyle.ACCENT_DIM)
	ctrl.draw_multiline_string(font, box.position + Vector2(pad, pad + hs * 1.4 + fs * 0.85), text, HORIZONTAL_ALIGNMENT_LEFT, width - pad * 2.0, fs, -1, ENEMY_TEXT if enemy else INK)
	ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Sound word of panel `pd`: heavy display face, thick ink outline and hard shadow, tilted, popping in after the panel.
func _sfx(pd: Dictionary, inner: Rect2, page_h: float, t: float) -> void:
	var s: Array = pd["sfx"]
	var sc := ComicKeys.pop(t, float(pd["t"]), SFX_DELAY)
	if sc <= 0.0:
		return
	var font := UiStyle.head_font(900, 0)
	var fs := maxi(16, int(float(s[3]) * page_h))
	var word := Loc.t(String(s[0]))
	var pos := inner.position + Vector2(float(s[1]), float(s[2])) * inner.size + Vector2(0, fs)
	var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	pos.x = minf(pos.x, inner.end.x - w * 0.9)
	var c: Color = s[5]
	ctrl.draw_set_transform(pos, deg_to_rad(float(s[4])), Vector2(sc, sc))
	var sh := Vector2(fs * 0.07, fs * 0.07)
	ctrl.draw_string_outline(font, sh, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(4, int(fs * 0.16)), INK)
	ctrl.draw_string_outline(font, Vector2.ZERO, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(4, int(fs * 0.16)), INK)
	ctrl.draw_string(font, Vector2.ZERO, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
	ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
