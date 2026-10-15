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

var _meshes := {}   # вид → Mesh (или null, если модели нет)
var _t: Terrain3D


func _init(terrain: Terrain3D) -> void:
	_t = terrain


func _mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		var m: Mesh = null
		var path: String = DIR + KINDS[kind][0] + ".glb"
		if ResourceLoader.exists(path):
			var scene := (load(path) as PackedScene).instantiate()
			var mi := _find_mesh(scene)
			if mi != null:
				m = mi.mesh
			scene.free()
		_meshes[kind] = m
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
func build(key: Vector2i, parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x5eed41
	var ox := key.x * Terrain3D.CHUNK
	var oz := key.y * Terrain3D.CHUNK
	var put := {}   # вид → Array[Transform3D]
	var obj: Dictionary = _t._obj(key) if _t._bg != null else {}
	var keep_out := []  # [центр, радиус] — внутри объектов биома не ставим
	if not obj.is_empty():
		keep_out.append([obj["pos"], float(obj["size"]) * 0.5])
	# вокруг объектов биома — их окружение
	if not obj.is_empty():
		var p0: Vector2 = obj["pos"]
		var r0 := float(obj["size"]) * 0.5
		match obj["name"]:
			"o_oasis", "o_village":
				for i in rng.randi_range(8, 14):
					_ring(rng, put, "poplar" if rng.randf() < 0.55 else "orchard", p0, r0 * 0.9, r0 * 1.5, keep_out)
				if obj["name"] == "o_village":
					for i in rng.randi_range(1, 3):
						_ring(rng, put, "yurt", p0, r0 * 1.1, r0 * 1.6, keep_out)
			"o_fort":
				for i in rng.randi_range(2, 4):
					_ring(rng, put, "sandbag", p0, r0 * 1.05, r0 * 1.35, keep_out)
			"o_rocks_big", "o_rocks_small":
				# группа скал вместо выдавленной картинки: крупный выход породы и валуны вокруг
				var big: bool = obj["name"] == "o_rocks_big"
				_add_sized(rng, put, "outcrop", p0, r0 * (1.1 if big else 0.8))
				for i in rng.randi_range(3, 6):
					_ring(rng, put, "boulders", p0, r0 * 0.5, r0 * 1.2, [])
				if big and rng.randf() < 0.6:
					_ring(rng, put, "spire", p0, r0 * 0.6, r0 * 0.9, [])
			"o_wreck", "o_crater":
				_ring(rng, put, "tank" if rng.randf() < 0.5 else "truck", p0, r0 * 0.9, r0 * 1.4, keep_out)
	# по рельефу клетки
	var tries := 70
	for i in tries:
		var p := Vector2(ox + rng.randf() * Terrain3D.CHUNK, oz + rng.randf() * Terrain3D.CHUNK)
		var h := _t.height(p.x, p.y) / maxf(_t.ceiling, 1.0)
		var slope := _slope(p)
		var roll := rng.randf()
		var kind := ""
		if h > 0.25 and h < 0.7 and slope < 0.9:
			if roll < 0.10:
				kind = "outcrop"
			elif roll < 0.16:
				kind = "spire"
			elif roll < 0.26:
				kind = "boulders"
		elif h < 0.12 and slope < 0.25:
			if roll < 0.18:
				kind = "shrub"
			elif roll < 0.21:
				kind = "boulders"
			elif roll < 0.215:
				kind = "orchard"
		elif roll < 0.08:
			kind = "boulders"
		if kind != "":
			_add(rng, put, kind, p, keep_out)
	# редкие одиночные находки в долинах: обломки техники, юрта кочевников
	if rng.randf() < 0.12:
		var p := Vector2(ox + rng.randf_range(200, 1200), oz + rng.randf_range(200, 1200))
		if _t.height(p.x, p.y) < _t.ceiling * 0.08:
			_add(rng, put, "tank" if rng.randf() < 0.5 else "truck", p, keep_out)
	if rng.randf() < 0.06:
		var p := Vector2(ox + rng.randf_range(200, 1200), oz + rng.randf_range(200, 1200))
		if _t.height(p.x, p.y) < _t.ceiling * 0.06:
			_add(rng, put, "yurt", p, keep_out)
			_add(rng, put, "shrub", p + Vector2(50, 20), keep_out)
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
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mmi)


func _ring(rng: RandomNumberGenerator, put: Dictionary, kind: String, c: Vector2, r_min: float, r_max: float, keep_out: Array) -> void:
	var a := rng.randf() * TAU
	_add(rng, put, kind, c + Vector2.from_angle(a) * rng.randf_range(r_min, r_max), [])


func _add(rng: RandomNumberGenerator, put: Dictionary, kind: String, p: Vector2, keep_out: Array) -> void:
	for k in keep_out:
		if p.distance_to(k[0]) < float(k[1]):
			return
	_add_sized(rng, put, kind, p, rng.randf_range(float(KINDS[kind][1]), float(KINDS[kind][2])))


func _add_sized(rng: RandomNumberGenerator, put: Dictionary, kind: String, p: Vector2, w: float) -> void:
	var s := _t.surface(p.x, p.y)
	# высоко в горах модель ближе к камере и кажется крупнее — уменьшаем (вид сверху, перспектива)
	w *= lerpf(1.0, 0.55, clampf((s.y - _t.base_y) / maxf(_t.ceiling, 1.0), 0.0, 1.0))
	# модель не выше 30 px до плоскости боя (как объекты биома в render3d.gd)
	var mesh := _mesh(kind)
	if mesh != null:
		var hk := mesh.get_aabb().size.y
		w = minf(w, (-30.0 - s.y) / maxf(hk, 0.01))
	if w < 4.0:
		return
	# утапливаем на 4 % ширины, чтобы на склоне не висело на краю
	var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, w, w)), s - Vector3(0, w * 0.04, 0))
	if not put.has(kind):
		put[kind] = []
	put[kind].append(t)


func _slope(p: Vector2) -> float:
	var e := 20.0
	var dx := _t.height(p.x + e, p.y) - _t.height(p.x - e, p.y)
	var dz := _t.height(p.x, p.y + e) - _t.height(p.x, p.y - e)
	return Vector2(dx, dz).length() / (2.0 * e)
