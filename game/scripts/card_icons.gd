class_name CardIcons
extends RefCounted
## U-09: значки на карточках улучшений — по виду оружия или по разделу карточки.
## Рисуются линиями и многоугольниками (без картинок), чтобы читались на любом размере.

## Ключ значка карточки: оружие (если есть) или раздел
static func key(c: Dictionary, p: Player = null) -> String:
	var w: String = c.get("weapon", "")
	if w == "" and c.has("group") and p != null and int(c["group"]) < p.groups.size():
		w = (p.groups[int(c["group"])] as Hardpoint).weapon   # улучшение оружия в группе подвесов
	if w != "":
		return w
	match String(c.get("cat", "")):
		"Пушка":
			return "gun"
		"Звено":
			return "wing"
		"Навык":
			return "skill"
		"Связка":
			return "synergy"
		"Резерв", "Ремонт":
			return "repair"
	return "module"


## Значок в квадрате со стороной s с центром в c
static func draw(ctrl: Control, c: Vector2, s: float, k: String, col: Color) -> void:
	var h := s / 2.0
	ctrl.draw_rect(Rect2(c - Vector2(h, h), Vector2(s, s)), Color(col.r, col.g, col.b, 0.14))
	ctrl.draw_rect(Rect2(c - Vector2(h, h), Vector2(s, s)), Color(col.r, col.g, col.b, 0.6), false, 1.5)
	var u := s * 0.36   # «единица» рисунка
	var lw := maxf(2.0, s / 18.0)
	match k:
		"aam":
			# ракета с наведением: корпус, головка, оперение и дуга «захвата»
			_missile(ctrl, c + Vector2(-u * 0.1, u * 0.1), u * 1.6, col, lw)
			ctrl.draw_arc(c + Vector2(u * 0.55, -u * 0.55), u * 0.35, 0.0, TAU, 16, col, lw * 0.7)
		"rockets":
			for i in 3:
				_missile(ctrl, c + Vector2((i - 1) * u * 0.6, u * (0.1 if i != 1 else -0.15)), u * 1.2, col, lw * 0.8)
		"gunpod", "gun":
			ctrl.draw_rect(Rect2(c + Vector2(-u * 0.9, -u * 0.35), Vector2(u * 1.1, u * 0.7)), col)
			ctrl.draw_line(c + Vector2(u * 0.2, 0), c + Vector2(u * 1.05, 0), col, lw * 1.4)
			for i in 3:
				ctrl.draw_circle(c + Vector2(u * (0.5 + 0.25 * i), -u * 0.6), lw * 0.7, col)
		"turret":
			ctrl.draw_circle(c, u * 0.55, col)
			ctrl.draw_line(c, c + Vector2(u * 0.7, -u * 0.7), col, lw * 1.6)
			ctrl.draw_line(c + Vector2(-u * 0.15, u * 0.15), c + Vector2(u * 0.55, -u * 0.85), col, lw * 1.0)
		"flares":
			for i in 6:
				var a := -PI / 2.0 + (i - 2.5) * 0.35
				ctrl.draw_line(c + Vector2(0, u * 0.9), c + Vector2(0, u * 0.9) + Vector2.from_angle(a) * u * 1.4, col, lw * 0.8)
				ctrl.draw_circle(c + Vector2(0, u * 0.9) + Vector2.from_angle(a) * u * 1.5, lw * 1.1, col)
		"bombs":
			ctrl.draw_circle(c + Vector2(0, u * 0.15), u * 0.6, col)
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.35, -u * 0.35), c + Vector2(u * 0.35, -u * 0.35),
				c + Vector2(u * 0.5, -u * 0.95), c + Vector2(-u * 0.5, -u * 0.95)]), col)
		"wing":
			for o in [Vector2(-u * 0.55, u * 0.35), Vector2(u * 0.55, u * 0.35), Vector2(0, -u * 0.45)]:
				_plane(ctrl, c + o, u * 0.55, col)
		"skill":
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(u * 0.2, -u), c + Vector2(-u * 0.55, u * 0.1), c + Vector2(-u * 0.05, u * 0.1),
				c + Vector2(-u * 0.25, u), c + Vector2(u * 0.55, -u * 0.15), c + Vector2(u * 0.05, -u * 0.15)]), col)
		"synergy":
			ctrl.draw_arc(c + Vector2(-u * 0.35, 0), u * 0.55, 0.0, TAU, 24, col, lw)
			ctrl.draw_arc(c + Vector2(u * 0.35, 0), u * 0.55, 0.0, TAU, 24, col, lw)
		"railgun":
			# рельсотрон: две направляющие и снаряд со вспышкой на конце
			for sd in [-1.0, 1.0]:
				ctrl.draw_line(c + Vector2(-u * 0.95, sd * u * 0.32), c + Vector2(u * 0.55, sd * u * 0.32), col, lw * 1.3)
			ctrl.draw_line(c + Vector2(-u * 0.6, 0), c + Vector2(u * 0.95, 0), col, lw * 0.9)
			ctrl.draw_circle(c + Vector2(u * 0.95, 0), lw * 1.6, col)
		"emp":
			# ЭМИ: точка и расходящиеся дуги-волны в обе стороны
			ctrl.draw_circle(c, u * 0.2, col)
			for i in 3:
				var rr := u * (0.45 + 0.28 * i)
				ctrl.draw_arc(c, rr, -0.7, 0.7, 12, col, lw * 0.9)
				ctrl.draw_arc(c, rr, PI - 0.7, PI + 0.7, 12, col, lw * 0.9)
		"laser":
			# лазер: излучатель и луч с вспышкой
			ctrl.draw_rect(Rect2(c + Vector2(-u * 0.95, -u * 0.25), Vector2(u * 0.6, u * 0.5)), col)
			ctrl.draw_line(c + Vector2(-u * 0.35, 0), c + Vector2(u * 0.75, 0), col, lw * 1.2)
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4.0
				ctrl.draw_line(c + Vector2(u * 0.75, 0), c + Vector2(u * 0.75, 0) + Vector2.from_angle(a) * u * 0.3, col, lw * 0.8)
		"plasma":
			# плазма: шар с ореолом над землёй
			ctrl.draw_circle(c + Vector2(0, -u * 0.1), u * 0.45, col)
			ctrl.draw_arc(c + Vector2(0, -u * 0.1), u * 0.72, 0.0, TAU, 24, col, lw * 0.8)
			ctrl.draw_line(c + Vector2(-u, u * 0.85), c + Vector2(u, u * 0.85), col, lw)
		"repair":
			ctrl.draw_rect(Rect2(c + Vector2(-u * 0.22, -u * 0.8), Vector2(u * 0.44, u * 1.6)), col)
			ctrl.draw_rect(Rect2(c + Vector2(-u * 0.8, -u * 0.22), Vector2(u * 1.6, u * 0.44)), col)
		_:
			# модуль: шестерня
			for i in 8:
				var a := TAU * i / 8.0
				ctrl.draw_line(c + Vector2.from_angle(a) * u * 0.5, c + Vector2.from_angle(a) * u * 0.95, col, lw * 1.8)
			ctrl.draw_circle(c, u * 0.62, col)
			ctrl.draw_circle(c, u * 0.25, Color(0.07, 0.09, 0.13))


## Ракета носом вверх: корпус, головная часть и стабилизаторы
static func _missile(ctrl: Control, c: Vector2, len: float, col: Color, lw: float) -> void:
	var top := c + Vector2(0, -len / 2.0)
	var bot := c + Vector2(0, len / 2.0)
	ctrl.draw_line(top + Vector2(0, len * 0.12), bot, col, lw * 1.6)
	ctrl.draw_colored_polygon(PackedVector2Array([top, top + Vector2(-lw * 1.1, len * 0.16), top + Vector2(lw * 1.1, len * 0.16)]), col)
	ctrl.draw_colored_polygon(PackedVector2Array([bot, bot + Vector2(-len * 0.16, 0), bot + Vector2(0, -len * 0.2)]), col)
	ctrl.draw_colored_polygon(PackedVector2Array([bot, bot + Vector2(len * 0.16, 0), bot + Vector2(0, -len * 0.2)]), col)


## Силуэт самолёта сверху носом вверх
static func _plane(ctrl: Control, c: Vector2, s: float, col: Color) -> void:
	ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.9, s * 0.35), c + Vector2(s * 0.2, s * 0.2),
		c + Vector2(s * 0.35, s * 0.8), c + Vector2(-s * 0.35, s * 0.8), c + Vector2(-s * 0.2, s * 0.2), c + Vector2(-s * 0.9, s * 0.35)]), col)
