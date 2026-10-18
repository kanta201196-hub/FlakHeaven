class_name Fx
extends Node2D
## Эффекты (2.8): взрывы из нескольких слоёв — вспышка, огненный шар, дым, обломки, искры,
## ударная волна и выжженное пятно на земле (FxGround). Плюс искры попаданий, цифры урона, тексты.
## Текстуры градиентов генерируются в коде — без файлов-ассетов.

var rings: Array = []
var sparks: Array = []
var numbers: Array = []
var zaps: Array = []
var fires: Array = []    # огненные шары и вспышки
var smokes: Array = []   # клубы дыма
var debris: Array = []   # обломки
var flares: Array = []   # 3.1: тепловые ловушки — горящие точки с дымным следом
var ground: FxGround

static var _soft: Texture2D   # мягкое пятно (дым, вспышка)
static var _crater: Texture2D


## Тест 3.5-s4 (п. 14): текстура воронки — тёмная чаша, светлый вал выброшенного грунта и рваные лучи копоти.
## Одна на все воронки (общий материал в 3D), строится один раз.
static func crater_tex() -> Texture2D:
	if _crater != null:
		return _crater
	const N := 160
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var edge := FastNoiseLite.new()   # неровный край: воронка не идеальный круг
	edge.seed = 3517
	edge.frequency = 0.9
	var grain := FastNoiseLite.new()  # комья и пятна грунта
	grain.seed = 911
	grain.frequency = 0.09
	for y in N:
		for x in N:
			var d := Vector2(x + 0.5 - N / 2.0, y + 0.5 - N / 2.0) / (N / 2.0)
			var ang := atan2(d.y, d.x)
			var wob := edge.get_noise_2d(cos(ang) * 2.0, sin(ang) * 2.0)
			var r := d.length() / (1.0 + 0.16 * wob)
			var g := 1.0 + 0.22 * grain.get_noise_2d(x, y)
			var c: Color
			var a: float
			if r < 0.2:       # дно: копоть и горелая земля
				c = Color(0.06, 0.05, 0.04)
				a = 0.85
			elif r < 0.36:    # склон чаши: к валу светлеет
				var t := (r - 0.2) / 0.16
				c = Color(0.06, 0.05, 0.04).lerp(Color(0.2, 0.15, 0.11), t)
				a = lerpf(0.85, 0.78, t)
			elif r < 0.5:     # вал выброшенного грунта: светлый гребень, темнее песка вокруг
				var t1 := (r - 0.36) / 0.14
				c = Color(0.2, 0.15, 0.11).lerp(Color(0.38, 0.3, 0.21), sin(t1 * PI))
				a = lerpf(0.78, 0.62, t1)
			else:             # разлёт копоти и комьев — пятнами, гаснет к краю
				var t2 := clampf((r - 0.5) / 0.5, 0.0, 1.0)
				c = Color(0.12, 0.09, 0.07)
				a = 0.62 * (1.0 - t2 * t2) * clampf(0.5 + 1.1 * grain.get_noise_2d(x * 1.7, y * 1.7), 0.15, 1.0)
			img.set_pixel(x, y, Color(c.r * g, c.g * g, c.b * g, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_crater = ImageTexture.create_from_image(img)
	return _crater
static var _fire: Texture2D   # огненный шар: белое ядро → оранжевый → прозрачный край
static var _fire_n: Array = []  # 3.2: огненные клубы с шумом (неровный край, языки пламени)
static var _smoke_n: Array = [] # 3.2: клубы дыма с шумом
var glow: FxGlow                # 3.2: слой свечения (аддитивное смешивание): вспышки, искры, ореолы
var pops: Array = []            # отложенные вторичные взрывы


## Клуб с шумом: радиальный градиент × фрактальный шум → неровный «живой» край
static func _noisy(seed_i: int, cols: PackedColorArray, stops: PackedFloat32Array, size := 128, rough := 0.55) -> Texture2D:
	var g := Gradient.new()
	g.offsets = stops
	g.colors = cols
	var n := FastNoiseLite.new()
	n.seed = seed_i * 7919 + 13
	n.frequency = 0.045
	n.fractal_octaves = 4
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var v := Vector2(x - c, y - c)
			var d := v.length() / c
			var nz := n.get_noise_2d(x, y) * 0.5 + 0.5
			var dd := clampf(d + (nz - 0.5) * rough * (0.3 + d), 0.0, 1.0)
			var col := g.sample(dd)
			col.a *= clampf((1.0 - d) * 3.0, 0.0, 1.0)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _radial(stops: PackedFloat32Array, cols: PackedColorArray, size := 128) -> Texture2D:
	# 2.8: картинку градиента строим сами (GradientTexture2D в GL Compatibility ломал отрисовку мира)
	var g := Gradient.new()
	g.offsets = stops
	g.colors = cols
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			img.set_pixel(x, y, g.sample(clampf(d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _ready() -> void:
	z_index = 4
	if _soft == null:
		_soft = _radial(PackedFloat32Array([0.0, 0.55, 1.0]), PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)]))
		_fire = _radial(PackedFloat32Array([0.0, 0.25, 0.6, 1.0]),
			PackedColorArray([Color(1, 1, 0.9, 1), Color(1, 0.8, 0.35, 1), Color(0.95, 0.35, 0.08, 0.7), Color(0.6, 0.1, 0.0, 0)]))
	if _fire_n.is_empty():
		for i in 4:
			_fire_n.append(_noisy(i, PackedColorArray([Color(1, 1, 0.92, 1), Color(1, 0.82, 0.38, 1), Color(0.98, 0.42, 0.1, 0.9), Color(0.5, 0.12, 0.04, 0.5), Color(0.2, 0.05, 0.02, 0)]),
				PackedFloat32Array([0.0, 0.22, 0.5, 0.78, 1.0])))
			_smoke_n.append(_noisy(i + 10, PackedColorArray([Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)]),
				PackedFloat32Array([0.0, 0.4, 0.75, 1.0]), 128, 0.8))
	glow = FxGlow.new()
	glow.fx = self
	add_child(glow)
	ground = FxGround.new()
	ground.fx = self
	add_sibling.call_deferred(ground)


## Взрыв (3.2). size — радиус «ядра» (≈ радиус цели или зоны поражения).
## Слои: вспышка и ореол (свечение) → огненные клубы с шумом → чёрный и серый дым → искры-угольки с хвостами →
## дымящие обломки → двойная ударная волна (яркая + пыльная) → вторичные хлопки у крупных → свет в 3D → пятно на земле.
## kind — вид 3D-взрыва (Boom3D): "flak" — подрыв ракеты или перехват; пусто — по размеру и air.
func explosion(pos: Vector2, size: float, air := true, secondary := true, kind := "") -> void:
	var s := maxf(size, 6.0) * 1.35 # 3.2: взрывы крупнее
	# 3.5: в 3D взрыв объёмный (boom3d.gd) — 2D-слои не нужны; свет и пятно на земле общие
	if Boom3D.active():
		Boom3D.ensure().spawn(pos, s, air, kind)
		Render3D.I.light_flash(pos, s)
		if is_instance_valid(ground):
			ground.scorch(pos, s * (1.6 if not air else 1.1), air)
		return
	var n := clampi(int(s / 3.5), 5, 18)
	# вспышка и ореол — в слое свечения
	glow.flashes.append({"p": pos, "r0": s * 1.4, "r1": s * 3.0, "life": 0.12, "max": 0.12, "c": Color(1, 0.9, 0.7, 0.8)})
	glow.flashes.append({"p": pos, "r0": s * 2.0, "r1": s * 3.8, "life": 0.5, "max": 0.5, "c": Color(0.9, 0.35, 0.08, 0.35)})
	# огненные клубы: разлетаются, растут, вращаются, темнеют к краю жизни
	for i in n:
		var d := Vector2.from_angle(randf() * TAU) * randf_range(0.0, s * 0.8)
		var life := randf_range(0.6, 1.1)
		fires.append({"p": pos + d * 0.3, "v": d * randf_range(1.6, 2.6), "r0": s * randf_range(0.5, 0.9), "r1": s * randf_range(1.3, 2.1),
			"life": life, "max": life, "flash": false, "ti": randi() % 4, "rot": randf() * TAU, "spin": randf_range(-2.0, 2.0)})
	# дым: сначала чёрный (горящее топливо), потом серый, поднимается и сносится ветром
	for i in n + 2:
		var d2 := Vector2.from_angle(randf() * TAU) * randf_range(0.0, s * 0.9)
		var life2 := randf_range(2.2, 4.0)
		var dark := i < (n * 2) / 3
		smokes.append({"p": pos + d2 * 0.5, "v": d2 * 0.9 + Vector2(22, -6), "r0": s * 0.6, "r1": s * randf_range(2.2, 3.4), "life": life2, "max": life2,
			"g": randf_range(0.04, 0.1) if dark else randf_range(0.2, 0.32), "ti": randi() % 4, "rot": randf() * TAU, "spin": randf_range(-0.6, 0.6),
			"delay": randf_range(0.0, 0.25)})
	# угольки-искры с хвостами
	for i in n * 2:
		var dir := Vector2.from_angle(randf() * TAU)
		glow.embers.append({"p": pos, "v": dir * randf_range(180.0, 520.0) * (0.6 + s / 30.0), "life": randf_range(0.3, 0.8), "max": 0.8,
			"c": Color(1.0, randf_range(0.5, 0.85), 0.25)})
	# обломки: кувыркаются и дымят
	if air:
		for i in clampi(int(s / 6.0), 2, 10):
			var dv := Vector2.from_angle(randf() * TAU) * randf_range(100.0, 300.0)
			var life3 := randf_range(0.7, 1.3)
			debris.append({"p": pos, "v": dv, "a": randf() * TAU, "w": randf_range(-12.0, 12.0), "s": randf_range(2.0, 4.5) * (0.6 + s / 30.0),
				"life": life3, "max": life3, "puff": 0.0})
	# двойная ударная волна: яркое тонкое кольцо и пыльная волна у земли
	# 3.4-t1 (п. 33): в 3D плоские кольца выглядели «кругами на земле», а не ударной волной — там их нет,
	# волну передают вспышка, свет взрыва и разлёт огня
	var flat := not (Render3D.I != null and Render3D.enabled)
	if flat:
		rings.append({"p": pos, "r": s * 0.6, "max": s * 3.6, "life": 0.3, "max_life": 0.3, "c": Color(1.0, 0.92, 0.75)})
	if flat and (not air or s > 16.0):
		rings.append({"p": pos, "r": s * 0.8, "max": s * 4.4, "life": 0.7, "max_life": 0.7, "c": Color(0.75, 0.62, 0.45), "dust": true})
	# вторичные хлопки у крупных взрывов
	if secondary and s >= 16.0:
		for i in randi_range(2, 3):
			pops.append({"p": pos + Vector2.from_angle(randf() * TAU) * s * randf_range(0.6, 1.3), "s": s * randf_range(0.35, 0.55),
				"t": randf_range(0.08, 0.3), "air": air})
	# свет в 3D: вспышка подсвечивает самолёты и землю
	if Render3D.I != null and Render3D.enabled:
		Render3D.I.light_flash(pos, s)
	# пятно на земле
	if is_instance_valid(ground):
		ground.scorch(pos, s * (1.6 if not air else 1.1), air)


## Зона поражения (НАР, бомбы, ракеты): кольцо радиуса + взрыв по размеру зоны
func blast(pos: Vector2, radius: float) -> void:
	explosion(pos, radius * 0.45, false, true, "blast")
	if Boom3D.active():   # 3.5: в 3D край зоны показывает пыльная волна, плоское кольцо не нужно
		return
	rings.append({"p": pos, "r": radius * 0.85, "max": radius, "life": 0.28, "max_life": 0.28, "c": Color(1.0, 0.6, 0.25)})


## 3.1: отстрел тепловых ловушек — веер ярких точек назад-в-стороны, падают и гаснут, дымный след
## 3.5 (правка 12): ловушки крупнее и ярче, мерцают, вокруг — вспышка; s — масштаб (залп «Кита» крупнее)
## life_k — во сколько раз дольше горят (залп «Кита» — дольше)
func flare_burst(pos: Vector2, heading: float, n := 6, vel := Vector2.ZERO, s := 1.0, life_k := 1.0) -> Array:
	var out: Array = []
	rings.append({"p": pos, "r": 40.0 * s, "max": 70.0 * s, "life": 0.25, "max_life": 0.25, "c": Color(1.0, 0.9, 0.6)})
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var a := heading + PI + side * deg_to_rad(randf_range(30.0, 95.0))
		var lf := randf_range(1.3, 1.9) * life_k
		var f := {"p": pos, "v": vel * 0.4 + Vector2.from_angle(a) * randf_range(180.0, 320.0) * sqrt(s), "life": lf,
			"max": maxf(1.8, lf), "trail": PackedVector2Array([pos]), "s": s, "ph": randf() * TAU}
		flares.append(f)
		out.append(f)
	if flares.size() > 160:
		flares = flares.slice(flares.size() - 160)
	return out


## Тест 3.5-s7: ЭМИ-заряд — волна от самолёта до края радиуса (в 3D — boom3d.emp) и голубые молнии
## к каждому заглушённому врагу: видно, что сработало и кого задело
func emp_wave(pos: Vector2, r: float, hit: Array = []) -> void:
	# волна по плоскости самолётов: от самолёта до края радиуса за 0,4 с, толстая и гаснет к краю
	rings.append({"p": pos, "r": r * 0.12, "max": r, "life": 0.4, "max_life": 0.4, "c": Color(0.55, 0.82, 1.0), "wave": true})
	rings.append({"p": pos, "r": r * 0.08, "max": r * 0.9, "life": 0.5, "max_life": 0.5, "c": Color(0.85, 0.95, 1.0), "wave": true})
	if Boom3D.active():
		Boom3D.ensure().emp(pos, r)
	for e in hit.slice(0, 12):
		if is_instance_valid(e):
			var to: Vector2 = (e as Node2D).global_position
			var mid := pos.lerp(to, 0.5) + (to - pos).orthogonal().normalized() * randf_range(-22.0, 22.0)
			beam(pos, mid, Color(0.6, 0.85, 1.0, 0.9), 2.0, 0.22)
			beam(mid, to, Color(0.6, 0.85, 1.0, 0.9), 2.0, 0.22)
			hit_spark(to, Color(0.6, 0.85, 1.0))


func ring(pos: Vector2, r: float, color: Color) -> void:
	rings.append({"p": pos, "r": r * 0.8, "max": r, "life": 0.3, "max_life": 0.3, "c": color})


func zap(from: Vector2, to: Vector2) -> void:
	zaps.append({"a": from, "b": to, "life": 0.12})


## U-08: луч (рельсотрон, прицельная линия): гаснет за life
func beam(from: Vector2, to: Vector2, color: Color, width: float, life: float) -> void:
	zaps.append({"a": from, "b": to, "life": life, "max": life, "c": color, "w": width})


func text(pos: Vector2, s: String, color := Color(1, 1, 1)) -> void:
	numbers.append({"p": pos, "t": s, "life": 1.2, "c": color, "size": 22})


func hit_spark(pos: Vector2, color := Color(1, 1, 0.8)) -> void:
	for i in 3:
		sparks.append({"p": pos, "v": Vector2.from_angle(randf() * TAU) * randf_range(80.0, 200.0), "life": 0.15, "c": color})


func number(pos: Vector2, dmg: float) -> void:
	if numbers.size() > 120:   # поздний бой: сотни попаданий в секунду — старые цифры уходят
		numbers.pop_front()
	numbers.append({"p": pos, "t": str(int(round(dmg))), "life": 0.6, "c": Color(1, 1, 1), "size": 16})


## Правка 3.5-s4: с наклонной камерой цифры и надписи рисует интерфейс (HudFlight._fx_texts) поверх 3D —
## на плоскости боя они мельчили, мылились текстурой слоя и терялись под моделями
static func texts_in_hud() -> bool:
	return Render3D.I != null and Render3D.enabled and Render3D.I.tilt_on()


func _tick(arr: Array, delta: float) -> void:
	for i in range(arr.size() - 1, -1, -1):
		arr[i]["life"] = float(arr[i]["life"]) - delta
		if float(arr[i]["life"]) <= 0.0:
			arr.remove_at(i)


func _process(delta: float) -> void:
	_tick(rings, delta)
	_tick(zaps, delta)
	for s in sparks:
		s["p"] = s["p"] + s["v"] * delta
		s["v"] = s["v"] * 0.9
	_tick(sparks, delta)
	for n in numbers:
		n["p"] = n["p"] + Vector2(0, -60) * delta
	_tick(numbers, delta)
	for f in fires:
		f["p"] = f["p"] + f["v"] * delta
		f["v"] = (f["v"] as Vector2) * pow(0.08, delta)
		f["rot"] = float(f.get("rot", 0.0)) + float(f.get("spin", 0.0)) * delta
	_tick(fires, delta)
	for s2 in smokes:
		s2["p"] = s2["p"] + s2["v"] * delta
		s2["v"] = s2["v"] * 0.97
		s2["rot"] = float(s2.get("rot", 0.0)) + float(s2.get("spin", 0.0)) * delta
	_tick(smokes, delta)
	for d in debris:
		d["p"] = d["p"] + d["v"] * delta
		d["v"] = d["v"] * 0.96
		d["a"] = float(d["a"]) + float(d["w"]) * delta
		d["puff"] = float(d.get("puff", 0.0)) - delta
		if float(d["puff"]) <= 0.0 and float(d["life"]) > 0.25:
			d["puff"] = 0.05
			smokes.append({"p": d["p"], "v": Vector2(14, -4), "r0": 3.0, "r1": 11.0, "life": 0.7, "max": 0.7, "g": 0.18,
				"ti": randi() % 4, "rot": randf() * TAU, "spin": 0.0})
	for i in range(pops.size() - 1, -1, -1):
		pops[i]["t"] = float(pops[i]["t"]) - delta
		if float(pops[i]["t"]) <= 0.0:
			var pp: Dictionary = pops[i]
			pops.remove_at(i)
			explosion(pp["p"], pp["s"], pp["air"], false)
	_tick(debris, delta)
	for fl in flares:
		fl["v"] = (fl["v"] as Vector2) * pow(0.25, delta) + Vector2(10, 18) * delta
		fl["p"] = fl["p"] + fl["v"] * delta
		var tr: PackedVector2Array = fl["trail"]
		if tr.is_empty() or tr[tr.size() - 1].distance_to(fl["p"]) > 6.0:
			tr.append(fl["p"])
			if tr.size() > 16:
				tr.remove_at(0)
			fl["trail"] = tr
	_tick(flares, delta)
	# не копим бесконечно в мясорубке
	if smokes.size() > 400:
		smokes = smokes.slice(smokes.size() - 400)
	if fires.size() > 300:
		fires = fires.slice(fires.size() - 300)
	queue_redraw()


func _blob(tex: Texture2D, p: Vector2, r: float, c: Color) -> void:
	draw_texture_rect(tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, c)


func _rblob(tex: Texture2D, p: Vector2, r: float, rot: float, c: Color) -> void:
	draw_set_transform(p, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-Vector2(r, r), Vector2(r, r) * 2.0), false, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	if OS.get_cmdline_user_args().has("--nofx"):
		return
	for s in smokes:
		var k := 1.0 - float(s["life"]) / float(s["max"])
		var g: float = s["g"]
		var a := (1.0 - k) * 0.8 * clampf(k * 5.0, 0.0, 1.0)
		_rblob(_smoke_n[int(s.get("ti", 0))] if not _smoke_n.is_empty() else _soft, s["p"], lerpf(float(s["r0"]), float(s["r1"]), sqrt(k)),
			float(s.get("rot", 0.0)), Color(g, g * 0.95, g * 0.9, a))
	for d in debris:
		var k2 := float(d["life"]) / float(d["max"])
		var dp: Vector2 = d["p"]
		var ds: float = d["s"]
		draw_set_transform(dp, d["a"], Vector2.ONE)
		draw_rect(Rect2(-ds, -ds * 0.5, ds * 2.0, ds), Color(0.12, 0.1, 0.08, k2))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if k2 > 0.5:
			draw_circle(dp, ds * 0.8, Color(1.0, 0.6, 0.2, (k2 - 0.5) * 1.4))
	for f in fires:
		var k3 := 1.0 - float(f["life"]) / float(f["max"])
		var rr := lerpf(float(f["r0"]), float(f["r1"]), sqrt(k3))
		if f["flash"]:
			_blob(_soft, f["p"], rr, Color(1, 0.97, 0.85, (1.0 - k3) * 0.9))
		else:
			# огонь остывает: белый → оранжевый → тёмно-красный
			var tex: Texture2D = _fire_n[int(f.get("ti", 0))] if not _fire_n.is_empty() else _fire
			var cool := Color(1, 1 - k3 * 0.55, 1 - k3 * 0.9, 1.0 - k3 * k3).lerp(Color(0.45, 0.12, 0.05, 1.0 - k3), k3 * 0.6)
			_rblob(tex, f["p"], rr, float(f.get("rot", 0.0)), cool)
	for r in rings:
		var k4 := 1.0 - float(r["life"]) / float(r["max_life"])
		var c: Color = r["c"]
		var rad := lerpf(float(r["r"]), float(r["max"]), sqrt(k4) if r.get("dust", false) else k4)
		if r.get("wave", false):   # тест 3.5-s7: волна ЭМИ — мягкое свечение и яркий фронт
			var kw := sqrt(k4)
			rad = lerpf(float(r["r"]), float(r["max"]), kw)
			c.a = (1.0 - k4) * 0.3
			draw_arc(r["p"], rad, 0.0, TAU, 72, c, 6.0 + 16.0 * (1.0 - kw))
			c.a = (1.0 - k4 * k4) * 0.95
			draw_arc(r["p"], rad, 0.0, TAU, 72, c, 3.0)
		elif r.get("dust", false):
			c.a = (1.0 - k4) * 0.35
			draw_arc(r["p"], rad, 0.0, TAU, 56, c, 4.0 + 14.0 * (1.0 - k4))
		else:
			c.a = (1.0 - k4) * 0.85
			draw_arc(r["p"], rad, 0.0, TAU, 48, c, 2.0 + 3.0 * (1.0 - k4))
	for s3 in sparks:
		var c2: Color = s3["c"]
		c2.a = clampf(float(s3["life"]) * 4.0, 0.0, 1.0)
		var p: Vector2 = s3["p"]
		var v: Vector2 = s3["v"]
		draw_line(p, p - v * 0.03, c2, 2.0)
	for n in ([] if texts_in_hud() else numbers):
		var a2 := clampf(float(n["life"]) * 2.0, 0.0, 1.0)
		var c3: Color = n["c"]
		c3.a = a2
		draw_string(Hud.ui_font(), n["p"], n["t"], HORIZONTAL_ALIGNMENT_CENTER, -1, int(n["size"]), c3)
	for z in zaps:
		var zc: Color = z.get("c", Color(0.8, 0.95, 1.0, 0.9))
		if z.has("max"):
			zc.a *= clampf(float(z["life"]) / float(z["max"]), 0.0, 1.0)
		draw_line(z["a"], z["b"], zc, float(z.get("w", 2.0)))
	for fl in flares:
		var k := clampf(float(fl["life"]) / float(fl["max"]), 0.0, 1.0)
		var tr: PackedVector2Array = fl["trail"]
		for j in range(1, tr.size()):
			var a := float(j) / tr.size()
			draw_line(tr[j - 1], tr[j], Color(0.92, 0.92, 0.95, 0.45 * a * k), 2.0 + 5.0 * (1.0 - a))
		var fp: Vector2 = fl["p"]
		var fs := float(fl.get("s", 1.0))
		var fk := 0.8 + 0.2 * sin(float(fl["life"]) * 40.0 + float(fl.get("ph", 0.0))) # мерцание магниевой ловушки
		_blob(_soft, fp, 34.0 * fs * (0.6 + 0.4 * k) * fk, Color(1.0, 0.8, 0.45, 0.55 * k))
		_blob(_soft, fp, 14.0 * fs * (0.6 + 0.4 * k), Color(1.0, 0.97, 0.85, 0.9 * k))
		draw_circle(fp, 5.0 * fs * (0.5 + 0.5 * k) * fk, Color(1, 1, 0.95, k))


## Слой на земле: выжженные пятна от взрывов (под самолётами, над объектами биома)
class FxGround:
	extends Node2D
	var fx: Fx
	var marks: Array = []

	func _ready() -> void:
		z_index = -7

	## Тест 3.5-s4 (п. 14): воронки от бомб — держатся CRATER_LIFE секунд и плавно гаснут; не больше
	## CRATER_MAX (старые уходят первыми). В 3D их рисует render3d._sync_craters по рельефу.
	const CRATER_LIFE := 75.0
	const CRATER_FADE := 20.0
	const CRATER_MAX := 40
	var craters: Array = []

	func crater(p: Vector2, r: float) -> void:
		craters.append({"p": p, "r": clampf(r * 0.75, 30.0, 140.0), "life": CRATER_LIFE, "rot": randf() * TAU})
		if craters.size() > CRATER_MAX:
			craters.pop_front()

	func scorch(p: Vector2, r: float, air: bool) -> void:
		# сбитый в воздухе падает рядом — пятно меньше и смещено «вниз-вправо», как тень
		var off := Vector2(r * 0.6, r * 0.9) if air else Vector2.ZERO
		marks.append({"p": p + off, "r": r, "life": 25.0, "rot": randf() * TAU})
		if marks.size() > 160:
			marks.pop_front()

	func _process(delta: float) -> void:
		for i in range(marks.size() - 1, -1, -1):
			marks[i]["life"] = float(marks[i]["life"]) - delta
			if float(marks[i]["life"]) <= 0.0:
				marks.remove_at(i)
		for i in range(craters.size() - 1, -1, -1):
			craters[i]["life"] = float(craters[i]["life"]) - delta
			if float(craters[i]["life"]) <= 0.0:
				craters.remove_at(i)
		queue_redraw()

	func _draw() -> void:
		if OS.get_cmdline_user_args().has("--nofx") or Render3D.enabled:
			return
		var ct := Fx.crater_tex()
		for c in craters:
			var ca := clampf(float(c["life"]) / CRATER_FADE, 0.0, 1.0)
			var cr: float = c["r"]
			draw_set_transform(c["p"], float(c["rot"]))
			draw_texture_rect(ct, Rect2(-Vector2(cr, cr), Vector2(cr, cr) * 2.0), false, Color(1, 1, 1, ca))
		draw_set_transform(Vector2.ZERO)
		for m in marks:
			var a := clampf(float(m["life"]) / 6.0, 0.0, 1.0) * 0.5
			var r: float = m["r"]
			draw_texture_rect(Fx._soft, Rect2(m["p"] - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0.06, 0.05, 0.04, a))
			draw_texture_rect(Fx._soft, Rect2(m["p"] - Vector2(r, r) * 0.45, Vector2(r, r) * 0.9), false, Color(0.02, 0.02, 0.02, a * 0.8))



## 3.2: слой свечения — аддитивное смешивание (вспышки, ореолы, угольки): огонь «светится» и на светлой земле
class FxGlow:
	extends Node2D
	var fx: Fx
	var flashes: Array = []
	var embers: Array = []

	func _ready() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		z_index = 1

	func _process(delta: float) -> void:
		for i in range(flashes.size() - 1, -1, -1):
			flashes[i]["life"] = float(flashes[i]["life"]) - delta
			if float(flashes[i]["life"]) <= 0.0:
				flashes.remove_at(i)
		for i in range(embers.size() - 1, -1, -1):
			var e: Dictionary = embers[i]
			e["p"] = e["p"] + e["v"] * delta
			e["v"] = (e["v"] as Vector2) * pow(0.12, delta)
			e["life"] = float(e["life"]) - delta
			if float(e["life"]) <= 0.0:
				embers.remove_at(i)
		if embers.size() > 600:
			embers = embers.slice(embers.size() - 600)
		queue_redraw()

	func _draw() -> void:
		if OS.get_cmdline_user_args().has("--nofx"):
			return
		for f in flashes:
			var k := 1.0 - float(f["life"]) / float(f["max"])
			var r := lerpf(float(f["r0"]), float(f["r1"]), sqrt(k))
			var c: Color = f["c"]
			c.a *= (1.0 - k)
			draw_texture_rect(Fx._soft, Rect2(f["p"] - Vector2(r, r), Vector2(r, r) * 2.0), false, c)
		for e in embers:
			var a := clampf(float(e["life"]) / float(e["max"]) * 1.6, 0.0, 1.0)
			var p: Vector2 = e["p"]
			var v: Vector2 = e["v"]
			var c2: Color = e["c"]
			c2.a = a
			draw_line(p, p - v * 0.045, c2, 2.0)
