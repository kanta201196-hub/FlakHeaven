class_name BiomeProps
extends RefCounted
## B-41: модели биома из Meshy (game/models/biome) на рельефе B-26.
## Расстановка детерминирована по клетке рельефа: скалы — на склонах и в горах, кусты — в долинах,
## деревья — у оазисов и кишлаков, юрты — у кишлаков, мешки — у крепостей, обломки техники — редко.
## Каждый вид в клетке — один MultiMesh (один вызов отрисовки), дочерний к куску рельефа:
## кусок выгружается — модели уходят вместе с ним.

const DIR := "res://models/biome/"
## вид: [файл, ширина в px мира мин, макс]
const KINDS := {
	"outcrop": ["b01_rock_outcrop", 70.0, 140.0],
	"boulders": ["b02_boulders", 40.0, 90.0],
	"spire": ["b03_rock_spire", 35.0, 60.0],
	"poplar": ["b04_poplar", 16.0, 24.0],
	"orchard": ["b05_orchard_tree", 34.0, 50.0],
	"shrub": ["b06_shrub", 14.0, 30.0],
	"truck": ["b07_wreck_truck", 55.0, 65.0],
	"tank": ["b08_wreck_tank", 58.0, 68.0],
	"yurt": ["b09_yurt", 34.0, 44.0],
	"sandbag": ["b10_sandbag_post", 40.0, 55.0],
}

## T4-05: облегчённые деревья для пресетов ниже «Максимального» (11–14 тыс. треуг. у полной модели).
## 3.4-t1 (п. 17): вместо зелёного шара — «карточки» из картинок той же модели Meshy: две скрещённые
## с видом сбоку и одна горизонтальная с видом сверху (tools/model_lab/bake_impostor.gd), 6 треугольников.
const LITE := {"poplar": "b04_poplar", "orchard": "b05_orchard_tree"}

var _meshes := {}   # вид → Mesh (или null, если модели нет)
var _t: Terrain3D


func _init(terrain: Terrain3D) -> void:
	_t = terrain


func _mesh(kind: String) -> Mesh:
	if LITE.has(kind) and Settings.gfx < Settings.GFX_MAX:
		var lk := kind + "_lite"
		if not _meshes.has(lk):
			_meshes[lk] = _lite_tree(kind)
		return _meshes[lk]
	return _full_mesh(kind)


## Дерево-карточки в габаритах полной модели (модели нормированы: ширина по X/Z = 1, низ в y = 0)
func _lite_tree(kind: String) -> Mesh:
	var full := _full_mesh(kind)
	var size := full.get_aabb().size if full != null else Vector3(1.0, 1.4, 1.0)
	var h := size.y
	var w := maxf(size.x, size.z)
	var side_s := maxf(h, w)   # кадр «сбоку» — квадрат со стороной max(h, w), центр на середине высоты
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ang in [0.0, PI / 2.0]:
		var ax := Vector3(cos(ang), 0, sin(ang)) * side_s * 0.5
		var y0 := h * 0.5 - side_s * 0.5
		_card(st, Vector3(0, y0, 0) - ax, Vector3(0, y0, 0) + ax, Vector3(0, y0 + side_s, 0) + ax, Vector3(0, y0 + side_s, 0) - ax, Vector3(-sin(ang), 0, cos(ang)))
	st.commit(am)
	am.surface_set_material(0, _card_mat(DIR + LITE[kind] + "_side.png"))
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yt := h * (0.72 if kind == "poplar" else 0.66)
	var r := w * 0.5
	_card(st2, Vector3(-r, yt, r), Vector3(r, yt, r), Vector3(r, yt, -r), Vector3(-r, yt, -r), Vector3.UP)
	st2.commit(am)
	am.surface_set_material(1, _card_mat(DIR + LITE[kind] + "_top.png"))
	return am


func _card(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var vs := [a, b, c, d]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uv[k])
		st.add_vertex(vs[k])


func _card_mat(path: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # свет уже «запечён» в картинку
	m.albedo_color = Color(0.92, 0.92, 0.9)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


func _full_mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		_meshes[kind] = null
		var path: String = DIR + KINDS[kind][0] + ".glb"
		if ResourceLoader.exists(path):
			var scene := (load(path) as PackedScene).instantiate()
			var mi := _find_mesh(scene)
			if mi != null:
				_meshes[kind] = mi.mesh
			scene.free()
	return _meshes[kind]


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


## Модели для клетки рельефа key; parent — кусок рельефа
## Высота модели каждого вида (для расчёта в потоке: сами модели грузит только главный поток)
func mesh_heights() -> Dictionary:
	var out := {}
	for kind in KINDS:
		var mesh := _mesh(kind)
		out[kind] = mesh.get_aabb().size.y if mesh != null else -1.0
	return out


func build(key: Vector2i, parent: Node3D) -> void:
	apply(plan(key, _t._ctx(key)), parent)


## Расстановка моделей в клетке — чистый расчёт по снимку ctx (Terrain3D._ctx), можно в потоке
func plan(key: Vector2i, ctx: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x5eed41
	var ox := key.x * Terrain3D.CHUNK
	var oz := key.y * Terrain3D.CHUNK
	var put := {}   # вид → Array[Transform3D]
	var obj: Dictionary = (ctx["objs"] as Dictionary).get(key, {})
	var keep_out := []  # [центр, радиус] — внутри объектов биома не ставим
	if not obj.is_empty():
		keep_out.append([obj["pos"], float(obj["size"]) * 0.5])
	# вокруг объектов биома — их окружение (поселения стоят на дне долин — см. terrain3d.gd)
	if not obj.is_empty():
		var p0: Vector2 = obj["pos"]
		var r0 := float(obj["size"]) * 0.5
		match obj["name"]:
			"o_oasis", "o_village":
				# сады — на ровном дне у поселения; тополя — рядами вдоль арыков
				for i in rng.randi_range(5, 9):
					_ring_zone(rng, put, "orchard", p0, r0 * 0.9, r0 * 1.5, ["floor"], ctx)
				var a0 := rng.randf() * TAU
				for i in rng.randi_range(5, 8):
					var q := p0 + Vector2.from_angle(a0) * r0 * 1.15 + Vector2.from_angle(a0 + PI / 2) * (i - 3.5) * 26.0
					if _zone(q, ctx) == "floor":
						_add(rng, put, "poplar", q, keep_out, ctx)
				if obj["name"] == "o_village":
					for i in rng.randi_range(1, 2):
						_ring_zone(rng, put, "yurt", p0, r0 * 1.2, r0 * 1.7, ["floor", "fan"], ctx)
			"o_fort":
				# посты из мешков — у крепости и на дороге рядом (застава)
				for i in rng.randi_range(2, 3):
					_ring_zone(rng, put, "sandbag", p0, r0 * 1.05, r0 * 1.35, ["floor", "fan"], ctx)
				var rp := _road_point(p0 + Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300)))
				if rp.distance_to(p0) < 700.0:
					_add_sized(rng, put, "sandbag", rp + Vector2(30, 0).rotated(rng.randf() * TAU), 48.0, ctx)
			"o_rocks_big", "o_rocks_small":
				# группа скал вместо выдавленной картинки: выход породы и валуны-осыпь вокруг
				var big: bool = obj["name"] == "o_rocks_big"
				if _zone(p0, ctx) in ["river", "road"]:
					p0 += Vector2(r0 * 2.0, 0)
				_add_sized(rng, put, "outcrop", p0, r0 * (1.1 if big else 0.8), ctx)
				for i in rng.randi_range(3, 6):
					_ring_zone(rng, put, "boulders", p0, r0 * 0.5, r0 * 1.2, ["floor", "fan", "slope"], ctx)
				if big and rng.randf() < 0.6:
					_ring_zone(rng, put, "spire", p0, r0 * 0.6, r0 * 0.9, ["fan", "slope", "crest"], ctx)
	# по зонам рельефа: каждый вид — там, где он бывает в природе (правила — s4-landscape-rules.md)
	for i in 90:
		if Settings.gfx == 0 and i % 2 == 1:   # «Низкое»: мелочи по зонам вдвое реже
			continue
		var p := Vector2(ox + rng.randf() * Terrain3D.CHUNK, oz + rng.randf() * Terrain3D.CHUNK)
		var z := _zone(p, ctx)
		var roll := rng.randf()
		var kind := ""
		match z:
			"bank":    # берег: тополя и кусты у воды — зелёная полоса вдоль реки
				kind = "poplar" if roll < 0.22 else ("shrub" if roll < 0.55 else "")
			"floor":   # дно долины: редкие кусты и камни, принесённые рекой
				kind = "shrub" if roll < 0.14 else ("boulders" if roll < 0.17 else "")
			"fan":     # конусы выноса и осыпи у подножия: валуны, кусты
				kind = "boulders" if roll < 0.2 else ("shrub" if roll < 0.3 else "")
			"slope":   # склон: выходы пород, редкие валуны
				kind = "outcrop" if roll < 0.08 else ("boulders" if roll < 0.13 else "")
			"crest":   # гребень: скальные зубцы
				kind = "spire" if roll < 0.035 else ""
		if kind != "":
			_add(rng, put, kind, p, keep_out, ctx)
	# сгоревшая техника — только на дороге или у обочины (на гору ей не заехать)
	if rng.randf() < 0.22:
		var q := _road_point(Vector2(ox + rng.randf_range(100, 1300), oz + rng.randf_range(100, 1300)))
		if _zone(q, ctx) == "road" and _in_chunk(q, ox, oz):
			var n := rng.randi_range(1, 3)   # колонна: машины одна за другой вдоль дороги
			var dir := _road_dir(q)
			for i in n:
				var w := q + dir * (i * 90.0) + dir.orthogonal() * rng.randf_range(-14, 14)
				_add_vehicle(rng, put, "tank" if rng.randf() < 0.4 else "truck", w, dir, ctx)
	# юрты кочевников — летние пастбища: пологие места в стороне от дороги, недалеко от воды
	if rng.randf() < 0.08:
		var q := Vector2(ox + rng.randf_range(200, 1200), oz + rng.randf_range(200, 1200))
		if _zone(q, ctx) in ["floor", "fan"] and absf(_t.river_field(q.x, q.y)) > Terrain3D.D_ROAD + 60.0:
			_add(rng, put, "yurt", q, keep_out, ctx)
			_add(rng, put, "yurt", q + Vector2(60, 25), keep_out, ctx)
			_add(rng, put, "shrub", q + Vector2(-40, 30), keep_out, ctx)
	return put


## Модели в сцену (главный поток): каждый вид — один MultiMesh
func apply(put: Dictionary, parent: Node3D) -> void:
	for kind in put:
		var mesh := _mesh(kind)
		if mesh == null:
			continue
		var arr: Array = put[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = arr.size()
		for j in arr.size():
			mm.set_instance_transform(j, arr[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var small: bool = kind in ["shrub", "boulders", "poplar", "orchard"]
		# 3.5 (правка 7): «Низкое» — модели биома без теней (вдвое меньше вызовов отрисовки), «Среднее» — мелкие без теней
		var no_shadow := Settings.gfx == 0 or (Settings.gfx == 1 and small)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if no_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mmi)


func _add(rng: RandomNumberGenerator, put: Dictionary, kind: String, p: Vector2, keep_out: Array, ctx: Dictionary) -> void:
	for k in keep_out:
		if p.distance_to(k[0]) < float(k[1]):
			return
	_add_sized(rng, put, kind, p, rng.randf_range(float(KINDS[kind][1]), float(KINDS[kind][2])), ctx)


func _add_sized(rng: RandomNumberGenerator, put: Dictionary, kind: String, p: Vector2, w: float, ctx: Dictionary) -> void:
	var s := _t.surface(p.x, p.y, ctx)
	# высоко в горах модель ближе к камере и кажется крупнее — уменьшаем (вид сверху, перспектива)
	w *= lerpf(1.0, 0.55, clampf((s.y - _t.base_y) / maxf(_t.ceiling, 1.0), 0.0, 1.0))
	# модель не выше 30 px до плоскости боя (как объекты биома в render3d.gd)
	var hk: float = (ctx["hk"] as Dictionary).get(kind, -1.0)
	if hk >= 0.0:
		w = minf(w, (-30.0 - s.y) / maxf(hk, 0.01))
	if w < 4.0:
		return
	# утапливаем на 4 % ширины, чтобы на склоне не висело на краю
	var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, w, w)), s - Vector3(0, w * 0.04, 0))
	if not put.has(kind):
		put[kind] = []
	put[kind].append(t)


func _slope(p: Vector2, ctx: Dictionary) -> float:
	var e := 20.0
	var dx := _t.height(p.x + e, p.y, ctx) - _t.height(p.x - e, p.y, ctx)
	var dz := _t.height(p.x, p.y + e, ctx) - _t.height(p.x, p.y - e, ctx)
	return Vector2(dx, dz).length() / (2.0 * e)


## Зона рельефа в точке: river (русло), road (дорога), bank (берег), floor (дно долины),
## fan (конусы выноса и осыпи), slope (склон), crest (гребень)
func _zone(p: Vector2, ctx: Dictionary) -> String:
	var v := _t.river_field(p.x, p.y)
	var a := absf(v)
	if a < Terrain3D.D_RIVER * 1.3:
		return "river"
	if absf(v - Terrain3D.D_ROAD) < 16.0:
		return "road"
	if a < Terrain3D.D_RIVER * 3.0:
		return "bank"
	var h := _t.height(p.x, p.y, ctx) / maxf(_t.ceiling, 1.0)
	var sl := _slope(p, ctx)
	if absf(_t.valley(p.x, p.y, ctx)) < Terrain3D.D_FLOOR and sl < 0.15:
		return "floor"
	if h < 0.16 and sl < 0.45:
		return "fan"
	if h > 0.55 and sl < 0.6:
		return "crest"
	return "slope"


## Ближайшая к p точка дороги (2 шага Ньютона по полю долин)
func _road_point(p: Vector2) -> Vector2:
	for i in 4:
		var v := _t.river_field(p.x, p.y)
		var e := 8.0
		var g := Vector2(_t.river_field(p.x + e, p.y) - _t.river_field(p.x - e, p.y), _t.river_field(p.x, p.y + e) - _t.river_field(p.x, p.y - e)) / (2.0 * e)
		if g.length_squared() < 1e-12:
			break
		p -= g * (v - Terrain3D.D_ROAD) / g.length_squared()
	return p


func _road_dir(p: Vector2) -> Vector2:
	var e := 8.0
	var g := Vector2(_t.river_field(p.x + e, p.y) - _t.river_field(p.x - e, p.y), _t.river_field(p.x, p.y + e) - _t.river_field(p.x, p.y - e))
	return g.orthogonal().normalized() if g.length_squared() > 0.0 else Vector2.RIGHT


func _in_chunk(p: Vector2, ox: float, oz: float) -> bool:
	return p.x >= ox and p.x < ox + Terrain3D.CHUNK and p.y >= oz and p.y < oz + Terrain3D.CHUNK


func _ring_zone(rng: RandomNumberGenerator, put: Dictionary, kind: String, c: Vector2, r_min: float, r_max: float, zones: Array, ctx: Dictionary) -> void:
	for t in 4:
		var q := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(r_min, r_max)
		if _zone(q, ctx) in zones:
			_add(rng, put, kind, q, [], ctx)
			return


## Машина стоит вдоль дороги (нос по направлению дороги, лёгкий разворот)
func _add_vehicle(rng: RandomNumberGenerator, put: Dictionary, kind: String, p: Vector2, dir: Vector2, ctx: Dictionary) -> void:
	var w := rng.randf_range(float(KINDS[kind][1]), float(KINDS[kind][2]))
	var s := _t.surface(p.x, p.y, ctx)
	var yaw := -dir.angle() + rng.randf_range(-0.35, 0.35) + (PI if rng.randf() < 0.5 else 0.0)
	var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w, w, w)), s - Vector3(0, w * 0.03, 0))
	if not put.has(kind):
		put[kind] = []
	put[kind].append(t)
