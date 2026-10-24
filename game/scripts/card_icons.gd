class_name CardIcons
extends RefCounted
## U-09: значки на карточках улучшений — по виду оружия или по разделу карточки.
## Рисуются линиями и многоугольниками (без картинок), чтобы читались на любом размере.

## Правка 9 (тест 3.5-s4): у каждого модуля и резерва свой значок — раньше все модули были шестерёнкой
const OWN := ["armor", "engine", "wing", "gun_dmg", "gun_rate", "reload", "seeker", "frag", "servo", "warhead",
	"msl_head", "msl_motor", "launcher", "radio", "magnet", "roll", "afterburner", "skill3", "repair",
	"res_overload", "res_bounty", "res_kit", "res_course"]


## Ключ значка карточки: свой значок модуля, оружие (если есть) или раздел
static func key(c: Dictionary, p: Player = null) -> String:
	var id := String(c.get("id", ""))
	if OWN.has(id):
		return id
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


## PG-01 (Kanta 24.10 «Значки ок»): volumetric weapon icons rendered from the hangar models
## (game/tools/model_lab/card_icons.py); a key without a picture keeps its line drawing
static var _tex := {}


## Picture of icon k (res://art/icons/<k>.png) or null; cached, including misses
static func tex(k: String) -> Texture2D:
	if not _tex.has(k):
		var path := "res://art/icons/%s.png" % k
		_tex[k] = load(path) if ResourceLoader.exists(path) else null
	return _tex[k]


## Значок в квадрате со стороной s с центром в c. Объёмный значок (tex) рисуется без рамки и на четверть
## крупнее квадрата: у него своё цветное свечение, а модель занимает не весь кадр; col задаёт только прозрачность
static func draw(ctrl: Control, c: Vector2, s: float, k: String, col: Color) -> void:
	var h := s / 2.0
	var t := tex(k)
	if t != null:
		var ts := s * 1.25
		ctrl.draw_texture_rect(t, Rect2(c - Vector2(ts, ts) / 2.0, Vector2(ts, ts)), false, Color(1, 1, 1, col.a))
		return
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
		"srm":
			# PG-01: short heat missile and the heat «waves» of its target
			_missile(ctrl, c + Vector2(-u * 0.3, u * 0.2), u * 1.25, col, lw * 0.9)
			for i in 3:
				ctrl.draw_arc(c + Vector2(u * 0.75, -u * 0.6), u * (0.15 + 0.17 * i), PI * 0.6, PI * 1.4, 8, col, lw * 0.7)
		"agm":
			# PG-01: heavy guided missile over a ground target in a sight
			_missile(ctrl, c + Vector2(-u * 0.35, -u * 0.1), u * 1.7, col, lw * 1.3)
			var tg := c + Vector2(u * 0.6, u * 0.6)
			ctrl.draw_rect(Rect2(tg - Vector2(u * 0.22, u * 0.13), Vector2(u * 0.44, u * 0.26)), col)
			ctrl.draw_arc(tg, u * 0.38, 0.0, TAU, 16, col, lw * 0.7)
			ctrl.draw_line(c + Vector2(-u * 0.05, u * 0.95), c + Vector2(u * 1.0, u * 0.95), col, lw * 0.8)
		"hebomb":
			# PG-01: heavy bomb with blast rays below it
			ctrl.draw_circle(c + Vector2(0, -u * 0.05), u * 0.5, col)
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.3, -u * 0.45), c + Vector2(u * 0.3, -u * 0.45),
				c + Vector2(u * 0.45, -u * 1.0), c + Vector2(-u * 0.45, -u * 1.0)]), col)
			for i in 5:
				var a := PI * (0.15 + 0.175 * i)
				ctrl.draw_line(c + Vector2(0, u * 0.35) + Vector2.from_angle(a) * u * 0.35, c + Vector2(0, u * 0.35) + Vector2.from_angle(a) * u * 0.7, col, lw * 0.8)
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
		"repair", "res_kit":
			ctrl.draw_rect(Rect2(c + Vector2(-u * 0.22, -u * 0.8), Vector2(u * 0.44, u * 1.6)), col)
			ctrl.draw_rect(Rect2(c + Vector2(-u * 0.8, -u * 0.22), Vector2(u * 1.6, u * 0.44)), col)
		"armor":
			# щит брони
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.8, -u * 0.8), c + Vector2(u * 0.8, -u * 0.8), c + Vector2(u * 0.8, u * 0.05),
				c + Vector2(0, u * 0.95), c + Vector2(-u * 0.8, u * 0.05)]), col)
			ctrl.draw_line(c + Vector2(0, -u * 0.6), c + Vector2(0, u * 0.6), Color(0.07, 0.09, 0.13), lw)
		"engine", "afterburner":
			# сопло двигателя и пламя (у форсажа пламя длиннее)
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.45, -u * 0.95), c + Vector2(u * 0.45, -u * 0.95), c + Vector2(u * 0.3, -u * 0.15), c + Vector2(-u * 0.3, -u * 0.15)]), col)
			var fl := 1.0 if k == "afterburner" else 0.7
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.28, -u * 0.05), c + Vector2(u * 0.28, -u * 0.05), c + Vector2(0, u * (0.1 + fl))]), col)
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.12, 0), c + Vector2(u * 0.12, 0), c + Vector2(0, u * (0.05 + fl * 0.6))]), Color(0.07, 0.09, 0.13))
		"wing":
			# стреловидное крыло с закрылком
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.9, u * 0.3), c + Vector2(u * 0.2, -u * 0.8), c + Vector2(u * 0.9, -u * 0.8), c + Vector2(u * 0.1, u * 0.3)]), col)
			ctrl.draw_line(c + Vector2(-u * 0.8, u * 0.6), c + Vector2(u * 0.2, u * 0.6), col, lw * 1.4)
			ctrl.draw_line(c + Vector2(u * 0.2, u * 0.6), c + Vector2(u * 0.05, u * 0.85), col, lw)
		"gun_dmg":
			# бронебойный снаряд
			ctrl.draw_rect(Rect2(c + Vector2(-u * 0.3, -u * 0.2), Vector2(u * 0.6, u * 1.0)), col)
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.3, -u * 0.2), c + Vector2(u * 0.3, -u * 0.2), c + Vector2(0, -u * 0.95)]), col)
			ctrl.draw_line(c + Vector2(-u * 0.3, u * 0.5), c + Vector2(u * 0.3, u * 0.5), Color(0.07, 0.09, 0.13), lw)
		"gun_rate":
			# очередь: три снаряда и линии скорости
			for i in 3:
				var o := Vector2((i - 1) * u * 0.55, (1 - i) * u * 0.25)
				ctrl.draw_rect(Rect2(c + o + Vector2(-u * 0.14, -u * 0.2), Vector2(u * 0.28, u * 0.65)), col)
				ctrl.draw_colored_polygon(PackedVector2Array([c + o + Vector2(-u * 0.14, -u * 0.2), c + o + Vector2(u * 0.14, -u * 0.2), c + o + Vector2(0, -u * 0.5)]), col)
			ctrl.draw_line(c + Vector2(-u * 0.9, u * 0.85), c + Vector2(u * 0.9, u * 0.85), col, lw * 0.8)
		"reload", "launcher":
			# стрелка по кругу — перезарядка (у пускового — с ракетой внутри)
			ctrl.draw_arc(c, u * 0.8, -PI * 0.35, PI * 1.35, 24, col, lw * 1.3)
			var tip := c + Vector2.from_angle(-PI * 0.35) * u * 0.8
			ctrl.draw_colored_polygon(PackedVector2Array([tip + Vector2(u * 0.3, -u * 0.05), tip + Vector2(-u * 0.15, -u * 0.3), tip + Vector2(-u * 0.05, u * 0.25)]), col)
			if k == "launcher":
				_missile(ctrl, c, u * 0.9, col, lw * 0.7)
			else:
				ctrl.draw_circle(c, u * 0.15, col)
		"seeker":
			# головка наведения: прицел
			ctrl.draw_arc(c, u * 0.6, 0.0, TAU, 24, col, lw)
			for i in 4:
				var d := Vector2.from_angle(TAU * i / 4.0)
				ctrl.draw_line(c + d * u * 0.35, c + d * u * 0.95, col, lw)
			ctrl.draw_circle(c, lw * 1.2, col)
		"frag":
			# осколки: центр и разлёт точек
			ctrl.draw_circle(c, u * 0.25, col)
			for i in 8:
				var d2 := Vector2.from_angle(TAU * i / 8.0 + 0.2)
				ctrl.draw_line(c + d2 * u * 0.4, c + d2 * u * 0.7, col, lw * 0.8)
				ctrl.draw_circle(c + d2 * u * 0.88, lw * 0.9, col)
		"warhead", "res_overload":
			# взрыв — звезда (у перегрузки — со стрелкой вверх)
			var pts := PackedVector2Array()
			for i in 16:
				pts.append(c + Vector2.from_angle(TAU * i / 16.0 - PI / 2.0) * u * (0.95 if i % 2 == 0 else 0.45))
			ctrl.draw_colored_polygon(pts, col)
			if k == "res_overload":
				ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -u * 0.35), c + Vector2(u * 0.25, 0), c + Vector2(-u * 0.25, 0)]), Color(0.07, 0.09, 0.13))
				ctrl.draw_line(c, c + Vector2(0, u * 0.35), Color(0.07, 0.09, 0.13), lw)
		"msl_head":
			# ракета со звездой разрыва у носа
			_missile(ctrl, c + Vector2(-u * 0.25, u * 0.15), u * 1.4, col, lw)
			for i in 6:
				var d3 := Vector2.from_angle(TAU * i / 6.0)
				ctrl.draw_line(c + Vector2(u * 0.45, -u * 0.55), c + Vector2(u * 0.45, -u * 0.55) + d3 * u * 0.38, col, lw * 0.8)
		"msl_motor":
			# ракета с факелом двигателя
			_missile(ctrl, c + Vector2(0, -u * 0.25), u * 1.3, col, lw)
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.2, u * 0.45), c + Vector2(u * 0.2, u * 0.45), c + Vector2(0, u * 1.0)]), col)
		"servo":
			# сервопривод: шестерня со стрелкой поворота
			for i in 6:
				var a2 := TAU * i / 6.0
				ctrl.draw_line(c + Vector2.from_angle(a2) * u * 0.3, c + Vector2.from_angle(a2) * u * 0.6, col, lw * 1.6)
			ctrl.draw_circle(c, u * 0.4, col)
			ctrl.draw_arc(c, u * 0.85, -PI * 0.9, -PI * 0.1, 16, col, lw)
			ctrl.draw_circle(c, u * 0.15, Color(0.07, 0.09, 0.13))
		"radio":
			# рация: корпус и волны
			ctrl.draw_rect(Rect2(c + Vector2(-u * 0.35, -u * 0.2), Vector2(u * 0.7, u * 1.0)), col)
			ctrl.draw_line(c + Vector2(u * 0.2, -u * 0.2), c + Vector2(u * 0.2, -u * 0.8), col, lw)
			for i in 2:
				ctrl.draw_arc(c + Vector2(u * 0.2, -u * 0.8), u * (0.25 + 0.22 * i), -PI * 0.85, -PI * 0.15, 10, col, lw * 0.8)
		"magnet":
			# магнит-подкова и искры опыта
			ctrl.draw_arc(c + Vector2(0, -u * 0.1), u * 0.55, 0.0, PI, 16, col, lw * 2.6)
			ctrl.draw_line(c + Vector2(-u * 0.55, -u * 0.1), c + Vector2(-u * 0.55, -u * 0.7), col, lw * 2.6)
			ctrl.draw_line(c + Vector2(u * 0.55, -u * 0.1), c + Vector2(u * 0.55, -u * 0.7), col, lw * 2.6)
			ctrl.draw_circle(c + Vector2(0, -u * 0.85), lw, col)
		"roll":
			# бочка: самолёт и дуга вращения
			_plane(ctrl, c, u * 0.55, col)
			ctrl.draw_arc(c, u * 0.9, PI * 0.15, PI * 0.85, 14, col, lw)
			ctrl.draw_arc(c, u * 0.9, PI * 1.15, PI * 1.85, 14, col, lw)
		"skill3":
			# навык класса: молния
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(u * 0.2, -u), c + Vector2(-u * 0.55, u * 0.1), c + Vector2(-u * 0.05, u * 0.1),
				c + Vector2(-u * 0.25, u), c + Vector2(u * 0.55, -u * 0.15), c + Vector2(u * 0.05, -u * 0.15)]), col)
		"res_bounty":
			# премия: стопка запчастей-монет
			for i in 3:
				ctrl.draw_rect(Rect2(c + Vector2(-u * 0.6, u * (0.45 - i * 0.4)), Vector2(u * 1.2, u * 0.3)), col)
		"res_course":
			# очко к связке: треугольник специализации
			ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -u * 0.85), c + Vector2(u * 0.85, u * 0.7), c + Vector2(-u * 0.85, u * 0.7)]), col)
		_:
			# модуль: шестерня
			for i in 8:
				var a := TAU * i / 8.0
				ctrl.draw_line(c + Vector2.from_angle(a) * u * 0.5, c + Vector2.from_angle(a) * u * 0.95, col, lw * 1.8)
			ctrl.draw_circle(c, u * 0.62, col)
			ctrl.draw_circle(c, u * 0.25, Color(0.07, 0.09, 0.13))


## Плашка в углу значка: «+» — улучшение оружия, «★» — модернизация, «Н» — новое оружие
static func badge(ctrl: Control, c: Vector2, s: float, kind: String, col: Color) -> void:
	var t := ""
	match kind:
		"weapon_up":
			t = "+"
		"evolution", "mastery", "branch":
			t = "★"
		"weapon_new":
			t = "Н"
		_:
			return
	var p := c + Vector2(s * 0.42, -s * 0.42)
	ctrl.draw_circle(p, s * 0.2, col)
	var f := Hud.ui_font()
	var fs := int(s * 0.28)
	t = Loc.out(t)
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ctrl.draw_string(f, p + Vector2(-tw / 2.0, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.07, 0.09, 0.13))


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
