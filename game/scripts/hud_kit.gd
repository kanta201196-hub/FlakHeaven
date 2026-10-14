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

## 3.1: у всего текста интерфейса тёмная обводка — читается на светлой земле
func _text(pos: Vector2, s: String, size := 20, color := Color(0.92, 0.95, 1.0), align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	ctrl.draw_string_outline(ui_font(), pos, s, align, width, size, maxi(3, size / 5), Color(0.02, 0.025, 0.03, 0.85 * color.a))
	ctrl.draw_string(ui_font(), pos, s, align, width, size, color)


func _ctext(y: float, s: String, size: int, color: Color) -> void:
	_text(Vector2(0, y), s, size, color, HORIZONTAL_ALIGNMENT_CENTER, ctrl.size.x)


## Многострочный текст с переносом по ширине
func _para(pos: Vector2, s: String, width: float, size := 18, color := Color(0.85, 0.88, 0.95)) -> float:
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
		var label := ("✓ " if c[1] else "") + String(c[0])
		var tw := ui_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16.0
		var col := Color(0.45, 1.0, 0.55) if c[1] else Color(0.75, 0.78, 0.85)
		ctrl.draw_rect(Rect2(x, pos.y, tw, 22), Color(col.r, col.g, col.b, 0.14))
		ctrl.draw_rect(Rect2(x, pos.y, tw, 22), Color(col.r, col.g, col.b, 0.5), false, 1.0)
		_text(Vector2(x + 8, pos.y + 16), label, 14, col)
		x += tw + 6.0
	return x
