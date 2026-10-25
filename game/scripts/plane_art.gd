class_name PlaneArt
## Спрайты самолётов и подвесов (прототип 2.5).
## Самолёты: res://art/planes/<класс>_<ур>.png — нос ВПРАВО, прозрачный фон.
## Оружие:   res://art/weapons/w_<оружие>.png — нос ВВЕРХ (как из ChatGPT); нет файла — рисуем заглушку.
## Точки подвеса считаются по силуэту крыла автоматически — новые картинки подхватываются без правки кода.

## 2.8: длина подвеса — доля длины истребителя на экране (plane_len), чтобы подвесы были видны
## PG-01: `srm` shorter than `aam`, `agm` the longest missile, `hebomb` longer than a cluster bomb
const WEAPON_FRAC := {"aam": 0.34, "rockets": 0.26, "bombs": 0.27, "gunpod": 0.3, "flares": 0.22, "turret": 0.22,
	"srm": 0.28, "agm": 0.4, "hebomb": 0.24}   # hebomb: the stubby finned model reads huge at 0.33 (PG-01)

## S11-06 / S11-07 (playtest 3.5-s11): the inner wing pair's station on planes where the point found from the sprite
## silhouette misses the real wing, in model units (plane length 1 = sprite width, as Hangar3D and Render3D map
## points onto the model): x along the nose, z out along the wing. «Оса» 2: outboard of the engine nacelle and the
## fairing beside it, where the underside is flat (at 38 % of the half-span the missile fins cut into both).
## «Оса» 1: under the fixed wing glove, the source model's own pylon station (the silhouette point sat against the
## fuselage side under the swing-wing root, with the pylon's rear half behind the trailing edge).
const WING_PAIR := {"fighter_1": Vector2(-0.075, 0.085), "fighter_2": Vector2(-0.15, 0.2)}

static var _tex := {}
static var _anchors := {}


static func plane_tex(cls_id: String, lvl: int) -> Texture2D:
	var key := "%s_%d" % [cls_id, lvl]
	if not _tex.has(key):
		var path := "res://art/planes/%s.png" % key
		_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _tex[key]


static func weapon_tex(w: String) -> Texture2D:
	var key := "w_" + w
	if not _tex.has(key):
		var path := "res://art/weapons/%s.png" % key
		_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _tex[key]


## Геометрия силуэта: длина, размах по столбцам, где крыло.
## Возвращает {"len": px, "wing_x": x центра крыла (от центра текстуры), "half": полуразмах крыла,
##             "fus": полуширина фюзеляжа, "nose": x носа, "tail": x хвоста}
static func shape_info(cls_id: String, lvl: int) -> Dictionary:
	var key := "%s_%d" % [cls_id, lvl]
	if _anchors.has(key):
		return _anchors[key]
	var info := {}
	var t := plane_tex(cls_id, lvl)
	if t == null:
		_anchors[key] = info
		return info
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var cy := h / 2.0
	var half := PackedFloat32Array()
	half.resize(w)
	var x0 := w
	var x1 := 0
	for x in w:
		var top := -1
		var bot := -1
		for y in h:
			if img.get_pixel(x, y).a > 0.4:
				if top < 0:
					top = y
				bot = y
		if top >= 0:
			half[x] = maxf(absf(top - cy), absf(bot - cy))
			x0 = mini(x0, x)
			x1 = maxi(x1, x)
	var maxh := 0.0
	for x in w:
		maxh = maxf(maxh, half[x])
	# крыло — столбцы с размахом > 60% максимума, но не хвост (задняя четверть)
	var tail_lim := x0 + (x1 - x0) * 0.28
	var sx := 0.0
	var n := 0
	for x in w:
		if x > tail_lim and half[x] > maxh * 0.6:
			sx += x
			n += 1
	var wing_x := (sx / n) if n > 0 else (x0 + x1) * 0.5
	# фюзеляж — минимальная полуширина в передней трети
	var fus := maxh
	for x in range(int(x0 + (x1 - x0) * 0.55), int(x0 + (x1 - x0) * 0.8)):
		if half[x] > 0.0:
			fus = minf(fus, half[x])
	var wing_half := 0.0
	for x in range(maxi(0, int(wing_x) - 2), mini(w, int(wing_x) + 3)):
		wing_half = maxf(wing_half, half[x])
	info = {"len": float(x1 - x0 + 1), "w": float(w), "wing_x": wing_x - w / 2.0, "half": wing_half,
		"fus": fus, "nose": x1 - w / 2.0, "tail": x0 - w / 2.0}
	_anchors[key] = info
	return info


## Точки подвеса для группы (в пикселях текстуры, начало — центр, нос вправо).
## Wing pairs come from the silhouette; the first pair of a plane in WING_PAIR hangs at its measured station instead.
static func slot_points(cls_id: String, lvl: int, group_index: int, group: Hardpoint) -> Array:
	var s := shape_info(cls_id, lvl)
	if s.is_empty():
		return []
	var pts: Array = []
	var wx: float = s["wing_x"]
	var half: float = s["half"]
	var fus: float = s["fus"]
	if group.builtin: # турели — по фюзеляжу
		var L: float = s["len"]
		var xs := [s["tail"] + L * 0.18, s["nose"] - L * 0.28, wx]
		for i in group.slots:
			pts.append(Vector2(xs[i % xs.size()], 0.0))
		return pts
	if group.name.begins_with("Бомбоотсек"):
		# 2.8: бомбоотсек «открыт» — бомбы видны по оси фюзеляжа
		var L2: float = s["len"]
		var pts2: Array = []
		for i in group.slots:
			pts2.append(Vector2(wx + L2 * (0.09 - 0.18 * i / maxf(group.slots - 1, 1)), 0.0))
		return pts2
	if group.slots == 1:
		return [Vector2(wx + 2.0, 0.0)]
	# пары на крыле: первая группа ближе к фюзеляжу, вторая — дальше
	var frac := 0.38 if group_index == 0 else 0.62
	if group.mount_frac > 0.0:
		frac = group.mount_frac   # PG-01: third group on the wing tips / outer pair
	var off := maxf(fus + 5.0, half * frac)
	var px := wx - 1.0
	var station: Vector2 = WING_PAIR.get("%s_%d" % [cls_id, lvl], Vector2.ZERO)
	if group_index == 0 and group.mount_frac <= 0.0 and station != Vector2.ZERO:
		px = station.x * float(s["w"])
		off = station.y * float(s["w"])
	for i in group.slots / 2:
		var o := off + i * half * 0.14
		pts.append(Vector2(px, o))
		pts.append(Vector2(px, -o))
	return pts


## Нарисовать одну единицу оружия в локальных координатах самолёта (нос вправо).
static func draw_weapon(ci: CanvasItem, w: String, pos: Vector2, scale: float, alpha: float, base: Transform2D) -> void:
	var L: float = WEAPON_FRAC.get(w, 0.25) * Tuning.g("plane_len") * scale
	var t := weapon_tex(w)
	if t != null:
		# текстура носом вверх → поворачиваем на +90°, чтобы нос смотрел вправо
		var k := L / float(maxi(t.get_height(), 1))
		ci.draw_set_transform_matrix(base * Transform2D(PI / 2.0, Vector2(k, k), 0.0, pos))
		# тёмный контур — подвес читается на фоне крыла
		var o := 1.2 * scale / k
		for d in [Vector2(o, 0), Vector2(-o, 0), Vector2(0, o), Vector2(0, -o)]:
			ci.draw_texture(t, -t.get_size() / 2.0 + d, Color(0.05, 0.05, 0.05, alpha * 0.8))
		ci.draw_texture(t, -t.get_size() / 2.0, Color(1.15, 1.15, 1.15, alpha))
		ci.draw_set_transform_matrix(base)
		return
	var c := Color(1, 1, 1, alpha)
	match w:
		"aam":
			ci.draw_line(pos + Vector2(-L / 2, 0), pos + Vector2(L / 2, 0), Color(0.85, 0.87, 0.9, alpha), 2.0 * scale)
			ci.draw_line(pos + Vector2(-L / 2, -1.6 * scale), pos + Vector2(-L / 2, 1.6 * scale), Color(0.6, 0.62, 0.66, alpha), 1.2)
			ci.draw_circle(pos + Vector2(L / 2, 0), 0.9 * scale, Color(0.4, 0.42, 0.45, alpha))
		"rockets":
			ci.draw_rect(Rect2(pos + Vector2(-L / 2, -1.8 * scale), Vector2(L, 3.6 * scale)), Color(0.42, 0.47, 0.3, alpha))
			ci.draw_circle(pos + Vector2(L / 2, 0), 1.8 * scale, Color(0.5, 0.55, 0.36, alpha))
		"bombs":
			ci.draw_rect(Rect2(pos + Vector2(-L / 2, -1.7 * scale), Vector2(L, 3.4 * scale)), Color(0.4, 0.45, 0.28, alpha))
			ci.draw_line(pos + Vector2(L * 0.2, -1.7 * scale), pos + Vector2(L * 0.2, 1.7 * scale), Color(0.95, 0.8, 0.2, alpha), 1.2)
			ci.draw_line(pos + Vector2(-L / 2, -2.4 * scale), pos + Vector2(-L / 2, 2.4 * scale), Color(0.3, 0.33, 0.22, alpha), 1.4)
		"gunpod":
			ci.draw_rect(Rect2(pos + Vector2(-L / 2, -1.8 * scale), Vector2(L * 0.8, 3.6 * scale)), Color(0.3, 0.32, 0.35, alpha))
			ci.draw_line(pos + Vector2(L * 0.3, 0), pos + Vector2(L / 2, 0), Color(0.15, 0.15, 0.17, alpha), 1.2)
		"flares":
			ci.draw_rect(Rect2(pos + Vector2(-L / 2, -1.5 * scale), Vector2(L, 3.0 * scale)), Color(0.28, 0.3, 0.33, alpha))
			ci.draw_circle(pos, 0.8 * scale, Color(1.0, 0.75, 0.3, alpha))
		"turret":
			ci.draw_circle(pos, L * 0.42, Color(0.55, 0.58, 0.62, alpha))
			ci.draw_line(pos + Vector2(0, -1.0 * scale), pos + Vector2(L * 0.75, -1.0 * scale), Color(0.2, 0.2, 0.22, alpha), 1.0)
			ci.draw_line(pos + Vector2(0, 1.0 * scale), pos + Vector2(L * 0.75, 1.0 * scale), Color(0.2, 0.2, 0.22, alpha), 1.0)
		_:
			ci.draw_circle(pos, 2.0 * scale, c)
