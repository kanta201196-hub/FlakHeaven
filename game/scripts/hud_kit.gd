class_name HudKit
extends RefCounted
## Общие примитивы отрисовки интерфейса (текст с обводкой, панели, кнопки, чипы условий).
## Модули интерфейса (HudFlight, HudScreens, HudCodex, HudHangar) наследуют их и рисуют в общий ctrl.

var ctrl: Control
var _buttons: Array # [Rect2, action] — общий массив с Hud, по нему Hud ловит клики


func _init(c: Control, buttons: Array) -> void:
	ctrl = c
	_buttons = buttons


static func ui_font() -> Font:
	return Hud.ui_font()


# ---------- Примитивы ----------

## Player-facing name of the key bound to `action` (design system pattern 3): the first
## keyboard key, else the mouse button. Follows rebinding because it reads InputMap.
## Keyboard only on purpose: no gamepad glyphs in hint bars (Kanta, 24.10); the gamepad
## column lives in the controls tab.
## The HUD asks for the same keys every frame; resolving a physical key asks the OS (and in headless runs
## prints an error each time), so labels are cached and refreshed twice a second — a rebind or a keyboard
## layout switch shows within 0.5 s.
static func key_label(action: String) -> String:
	var now := Time.get_ticks_msec()
	if now - _key_t > 500:
		_key_cache.clear()
		_key_t = now
	if not _key_cache.has(action):
		_key_cache[action] = _key_label(action)
	return _key_cache[action]


static var _key_cache := {}
static var _key_t := 0


## Mouse button and keyboard key of `action` together («ПКМ / K»), mouse first: for actions
## players mostly use with the mouse (missile launch), where key_label() alone shows only the
## key and reads as if the mouse did nothing (S11-18). Falls back to key_label() without a mouse bind.
static func key_labels(action: String) -> String:
	var mouse := ""
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				mouse = _mouse_name((ev as InputEventMouseButton).button_index)
				break
	var key := key_label(action)
	if mouse == "" or mouse == key:
		return key
	return mouse + " / " + key


static func _mouse_name(button: int) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return Loc.t("ЛКМ")
		MOUSE_BUTTON_RIGHT:
			return Loc.t("ПКМ")
		MOUSE_BUTTON_MIDDLE:
			return Loc.t("СКМ")
	return ""


## key_label() without the cache: reads InputMap now.
static func _key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var mouse := ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code := k.keycode if k.keycode != KEY_NONE else DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
			return OS.get_keycode_string(code).to_upper()
		if ev is InputEventMouseButton and mouse == "":
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					mouse = Loc.t("ЛКМ")
				MOUSE_BUTTON_RIGHT:
					mouse = Loc.t("ПКМ")
				MOUSE_BUTTON_MIDDLE:
					mouse = Loc.t("СКМ")
	return mouse if mouse != "" else "?"


## Word-wrapped lines of `s` (translated) for `width`, at most `max_lines`; the last one
## gets an ellipsis when text is left over. For centred captions under icon tiles.
## Results are cached: tile captions are re-laid out every frame, and each try measures (shapes) a string.
func _lines(s: String, width: float, fsize: int, font: Font = null, max_lines := 2) -> PackedStringArray:
	var f := font if font != null else ui_font()
	var key := [s, width, fsize, f.get_instance_id(), max_lines, TranslationServer.get_locale()]
	if _lines_cache.has(key):
		return _lines_cache[key]
	if _lines_cache.size() > 2000:
		_lines_cache.clear()
	var res := _lines_now(s, width, fsize, f, max_lines)
	_lines_cache[key] = res
	return res


static var _lines_cache := {}
static var _fit_cache := {}


func _lines_now(s: String, width: float, fsize: int, f: Font, max_lines: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var words := Loc.out(s).split(" ", false)
	for i in words.size():
		var tryl := words[i] if cur == "" else cur + " " + words[i]
		if f.get_string_size(tryl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= width or cur == "":
			cur = tryl
			continue
		if out.size() == max_lines - 1:
			out.append(_fit(cur + " " + " ".join(words.slice(i)), width, fsize, f))
			return out
		out.append(cur)
		cur = words[i]
	if cur != "":
		out.append(cur)
	return out


## Text cut with an ellipsis to fit `width` at font size `fsize` in `font` (default: the
## body font); returns the translated string.
func _fit(s: String, width: float, fsize: int, font: Font = null) -> String:
	var f := font if font != null else ui_font()
	var key := [s, width, fsize, f.get_instance_id(), TranslationServer.get_locale()]
	if _fit_cache.has(key):
		return _fit_cache[key]
	if _fit_cache.size() > 2000:
		_fit_cache.clear()
	var res := _fit_now(s, width, fsize, f)
	_fit_cache[key] = res
	return res


func _fit_now(s: String, width: float, fsize: int, f: Font) -> String:
	s = Loc.out(s)
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= width:
		return s
	while s.length() > 1 and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > width:
		s = s.substr(0, s.length() - 1)
	return s + "…"

## 3.1: у всего текста интерфейса тёмная обводка — читается на светлой земле
## Перевод: ключ — русская фраза; без таблицы перевода строка выводится как есть
func _text(pos: Vector2, s: String, size := 20, color := Color(0.92, 0.95, 1.0), align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	s = Loc.out(s)
	ctrl.draw_string_outline(ui_font(), pos, s, align, width, size, maxi(3, size / 5), Color(0.02, 0.025, 0.03, 0.85 * color.a))
	ctrl.draw_string(ui_font(), pos, s, align, width, size, color)


func _ctext(y: float, s: String, size: int, color: Color) -> void:
	_text(Vector2(0, y), s, size, color, HORIZONTAL_ALIGNMENT_CENTER, ctrl.size.x)


## Многострочный текст с переносом по ширине
func _para(pos: Vector2, s: String, width: float, size := 18, color := Color(0.85, 0.88, 0.95)) -> float:
	s = Loc.out(s)
	ctrl.draw_multiline_string_outline(ui_font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, maxi(3, size / 5), Color(0.02, 0.025, 0.03, 0.8 * color.a))
	ctrl.draw_multiline_string(ui_font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, color)
	var lines := ui_font().get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, size).y
	return lines


## 2.8: стиль Flak Heaven — графит, янтарная подсветка, срезанный угол
func _panel(r: Rect2, hover: bool, accent := Menu.C_AMBER) -> void:
	var cut := minf(14.0, r.size.y * 0.3)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x - cut, r.position.y), Vector2(r.end.x, r.position.y + cut), r.end, Vector2(r.position.x, r.end.y)])
	ctrl.draw_colored_polygon(pts, Color(0.085, 0.095, 0.085, 0.95))
	pts.append(r.position)
	ctrl.draw_polyline(pts, accent if hover else Color(accent.r, accent.g, accent.b, 0.4), 2.5 if hover else 1.5)


func _button(r: Rect2, label: String, action: String, size := 20) -> void:
	var hover := r.has_point(ctrl.get_local_mouse_position())
	_panel(r, hover)
	_text(Vector2(r.position.x, r.position.y + r.size.y / 2.0 + size * 0.35), label, size, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_buttons.append([r, action])


## Подложка панели: тёмная, с мягким краем в сторону центра экрана
func _backing(r: Rect2, right := false) -> void:
	var steps := 6
	for i in steps:
		var k := float(i) / steps
		var rr := r
		var cut := r.size.x * 0.25 * k
		if right:
			rr.position.x += cut
		rr.size.x -= cut
		ctrl.draw_rect(rr, Color(0.03, 0.035, 0.04, 0.09))


## Чипы условий в строку; вернёт x после последнего
func _cond_chips(pos: Vector2, conds: Array) -> float:
	var x := pos.x
	for c in conds:
		var label := ("✓ " if c[1] else "") + Loc.out(String(c[0]))
		var tw := ui_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16.0
		var col := Color(0.45, 1.0, 0.55) if c[1] else Color(0.75, 0.78, 0.85)
		ctrl.draw_rect(Rect2(x, pos.y, tw, 22), Color(col.r, col.g, col.b, 0.14))
		ctrl.draw_rect(Rect2(x, pos.y, tw, 22), Color(col.r, col.g, col.b, 0.5), false, 1.0)
		_text(Vector2(x + 8, pos.y + 16), label, 14, col)
		x += tw + 6.0
	return x


## Правки 15–16: взятые карточки чипами в прямоугольнике (цвет — лучшая редкость), не влезло — «и ещё N»
func _card_chips(r: Rect2, items: Array, size := 14) -> void:
	var x := r.position.x
	var y := r.position.y
	var h := size + 10.0
	for i in items.size():
		var it: Dictionary = items[i]
		var label := Loc.title(String(it["title"]))
		if int(it["lvl"]) > 0:
			label += Loc.t(" · ур. %d") % int(it["lvl"])
		elif int(it["n"]) > 1:
			label += " ×%d" % int(it["n"])
		var tw := ui_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0
		var last_row := y + 2.0 * h + 4.0 > r.end.y
		# на последней строке оставляем место под «и ещё N»
		var room := 0.0 if i == items.size() - 1 else 90.0
		if last_row and x + tw + room > r.end.x:
			_text(Vector2(x + 4, y + h - 7), Loc.t("и ещё %d") % (items.size() - i), size, Color(0.75, 0.8, 0.9))
			return
		if x + tw > r.end.x and x > r.position.x:
			x = r.position.x
			y += h + 4.0
		var col: Color = Cards.RARITY[int(it["r"])]["color"]
		ctrl.draw_rect(Rect2(x, y, tw, h), Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.85))
		ctrl.draw_rect(Rect2(x, y, 3, h), col)
		_text(Vector2(x + 9, y + h - 7), label, size, col.lightened(0.35))
		x += tw + 6.0
