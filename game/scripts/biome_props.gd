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
	"boulders": ["b02_boulders", 22.0, 50.0],   # правка Kanta 18.10 (п. 5): камни мельче (было 40–90)
	"spire": ["b03_rock_spire", 35.0, 60.0],
	"poplar": ["b04_poplar", 16.0, 24.0],
	"orchard": ["b05_orchard_tree", 34.0, 50.0],
	"shrub": ["b06_shrub", 14.0, 30.0],
	"truck": ["b07_wreck_truck", 55.0, 65.0],
	"tank": ["b08_wreck_tank", 58.0, 68.0],
	"yurt": ["b09_yurt", 34.0, 44.0],
	"sandbag": ["b10_sandbag_post", 40.0, 55.0],
	"plane": ["b11_wreck_plane", 110.0, 130.0],   # сцены прошедших боёв (Terrain3D.scenes)
	"bridge": ["", 58.0, 66.0],        # L-07: модели кодом (AdobeBuild.bridge): мост дороги через ручей
	"footbridge": ["", 150.0, 165.0],  # и пешеходный через реку
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
	if kind in ["bridge", "footbridge"]:
		return AdobeBuild.bridge(kind == "footbridge")
	if not _meshes.has(kind):
		_meshes[kind] = null
		var path: String = DIR + KINDS[kind][0] + ".glb"
		if ResourceLoader.exists(path):
			var scene := (load(path) as PackedScene).instantiate()
			var mi := _find_mesh(scene)
			if mi != null:
				_meshes[kind] = _merged(scene) if _count_meshes(scene) > 1 else mi.mesh
			scene.free()
	return _meshes[kind]


func _count_meshes(n: Node) -> int:
	var k := 1 if n is MeshInstance3D else 0
	for c in n.get_children():
		k += _count_meshes(c)
	return k


## Модель из многих частей (остов самолёта — 23 детали) — в одну сетку для MultiMesh: части с одним
## материалом сливаются в одну поверхность
func _merged(root: Node) -> Mesh:
	var parts := []
	_collect(root, Transform3D.IDENTITY, parts)
	var by_mat := {}
	for pr in parts:
		var mesh: Mesh = pr[0]
		for si in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(si)
			if pr[2] != null:
				mat = pr[2]
			if not by_mat.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = st
			(by_mat[mat] as SurfaceTool).append_from(mesh, si, pr[1])
	var am := ArrayMesh.new()
	for mat in by_mat:
		var st: SurfaceTool = by_mat[mat]
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	return am


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([(n as MeshInstance3D).mesh, t, (n as MeshInstance3D).material_override])
	for c in n.get_children():
		_collect(c, t, out)


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
	# тест 3.5-s4 (п. 20): и объекты соседних клеток (у края клетки, сдвинутые от реки), и с запасом
	# на размер валуна/дерева — модели не наползают на кишлак, обломки, воронку
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var no: Dictionary = (ctx["objs"] as Dictionary).get(Vector2i(key.x + dx, key.y + dz), {})
			if not no.is_empty() and not (no["name"] in ["o_rocks_big", "o_rocks_small"]):
				keep_out.append([no["pos"], float(no["size"]) * maxf(AdobeBuild.footprint(no["name"]), 0.5) + 30.0])
	# сцены прошедших боёв (Terrain3D.scenes): техника и мешки этой клетки; вокруг них и пятен — без кустов
	var scn: Dictionary = ctx.get("scenes", {})
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for it in scn.get(Vector2i(key.x + dx, key.y + dz), []):
				keep_out.append([it["p"], float(it["r"]) + 12.0])
	for it in scn.get(key, []):
		if KINDS.has(it["k"]):
			_add_scene(rng, put, it, ctx)
	# вокруг объектов биома — их окружение (поселения стоят на дне долин — см. terrain3d.gd)
	if not obj.is_empty():
		var p0: Vector2 = obj["pos"]
		var r0 := float(obj["size"]) * 0.5
		match obj["name"]:
			"o_oasis", "o_village":
				# тест 3.5-s4 (п. 17): сады — пятнами там, где на земле огороды и сады (AdobeBuild.ground_mask),
				# а не кольцом вокруг; тополя — рядами по краю садов (вдоль арыков)
				var vr := int(obj.get("var", 0))
				var sz0 := float(obj["size"])
				var trees := 0
				var want := rng.randi_range(14, 20) if obj["name"] == "o_oasis" else rng.randi_range(10, 16)
				for i in 70:
					if trees >= want:
						break
					var q := p0 + Vector2.from_angle(rng.randf() * TAU) * sz0 * 0.75 * sqrt(rng.randf())
					var gm := AdobeBuild.ground_mask(obj["name"], vr, (q - p0).rotated(-float(obj["rot"])) / sz0)
					if gm.y < 0.45 or gm.x > 0.5 or not (_zone(q, ctx) in ["floor", "fan"]):
						continue
					trees += 1
					_add(rng, put, "orchard", q, [], ctx)
					if rng.randf() < 0.45:   # сад — группа деревьев
						_add(rng, put, "orchard", q + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(30.0, 45.0), [], ctx)
				var a0 := rng.randf() * TAU
				var rr := sz0 * maxf(AdobeBuild.footprint(obj["name"]), 0.5) * AdobeBuild.outline(vr, a0 - float(obj["rot"])) * 0.95
				for i in rng.randi_range(5, 8):
					var q := p0 + Vector2.from_angle(a0) * rr + Vector2.from_angle(a0 + PI / 2) * (i - 3.5) * 26.0
					if _zone(q, ctx) == "floor":
						_add(rng, put, "poplar", q, [], ctx)
				if obj["name"] == "o_village":
					for i in rng.randi_range(1, 2):
						_ring_zone(rng, put, "yurt", p0, r0 * 1.2, r0 * 1.7, ["floor", "fan"], ctx)
			"o_fort":
				# L-08: застава — посты из мешков на дороге по обе стороны крепости (перекрывают проезд)
				# и 1–2 поста с тыла, со стороны гор; не кольцом наугад
				var rp := _road_point(p0)
				if rp.distance_to(p0) < 700.0:
					var nrm := (p0 - rp).normalized()
					var tan := nrm.orthogonal()
					for sg: float in [-1.0, 1.0]:
						var q := _road_point(rp + tan * sg * r0 * 1.4)
						_add_sized(rng, put, "sandbag", q + nrm * 34.0, 48.0, ctx)
					for i in rng.randi_range(1, 2):
						var q := p0 + nrm.rotated(rng.randf_range(-0.6, 0.6)) * r0 * 1.15
						if _zone(q, ctx) in ["floor", "fan"]:
							_add(rng, put, "sandbag", q, [], ctx)
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
			"floor":   # дно долины: редкие кусты; камни — только те, что принесла река (ближе к руслу)
				kind = "shrub" if roll < 0.14 else ("boulders" if roll < 0.16 and absf(_t.river_field(p.x, p.y)) < 200.0 else "")
			"fan":     # конусы выноса и осыпи у подножия: валуны грудами, кусты
				kind = "boulders" if roll < 0.07 else ("shrub" if roll < 0.17 else "")
			"slope":   # склон: выходы пород, редкие груды валунов под ними
				kind = "outcrop" if roll < 0.08 else ("boulders" if roll < 0.1 else "")
			"crest":   # гребень: скальные зубцы
				kind = "spire" if roll < 0.035 else ""
		if kind == "boulders":
			# карта расстановки (18.10.2026): валуны лежат грудами — осыпь, а не ровная «сыпь» по всей карте
			for j in rng.randi_range(3, 5):
				var q := p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 70.0) * (0.0 if j == 0 else 1.0)
				if _zone(q, ctx) in ["floor", "fan", "slope"]:
					_add(rng, put, kind, q, keep_out, ctx)
		elif kind != "":
			_add(rng, put, kind, p, keep_out, ctx)
			if kind == "outcrop":   # п. 5: откуда камни — осыпь из 2–4 валунов под выходом породы, вниз по склону
				var down := _downhill(p, ctx)
				for j in rng.randi_range(2, 4):
					_add(rng, put, "boulders", p + down * rng.randf_range(50.0, 110.0) + down.orthogonal() * rng.randf_range(-35.0, 35.0), keep_out, ctx)
	# L-06: в зелёной полосе вдоль реки — сады группами и тополя по краю полей
	for i in 160:
		if Settings.gfx == 0 and i % 2 == 1:
			continue
		var p := Vector2(ox + rng.randf() * Terrain3D.CHUNK, oz + rng.randf() * Terrain3D.CHUNK)
		var roll := rng.randf()
		if _t.green(p.x, p.y) < 0.45 or not (_zone(p, ctx) in ["bank", "floor"]):
			continue
		if roll < 0.5:
			_add(rng, put, "orchard", p, keep_out, ctx)
			if roll < 0.3:
				_add(rng, put, "orchard", p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(30.0, 45.0), keep_out, ctx)
		elif roll < 0.55:
			_add(rng, put, "poplar", p, keep_out, ctx)
	# сгоревшая техника — только на дороге или у обочины (на гору ей не заехать)
	if rng.randf() < 0.22:
		var q := _road_point(Vector2(ox + rng.randf_range(100, 1300), oz + rng.randf_range(100, 1300)))
		if _zone(q, ctx) == "road" and _in_chunk(q, ox, oz):
			var n := rng.randi_range(1, 3)   # колонна: машины одна за другой вдоль дороги
			var dir := _road_dir(q)
			for i in n:
				var off := dir.orthogonal() * rng.randf_range(-14, 14)
				if _t.in_river_guard(q + dir * (i * 90.0) + off, 14.0):   # M-35: к реке не съезжает — к другой обочине
					off = -off
				var w := q + dir * (i * 90.0) + off
				if _t.in_river_guard(w, 14.0):
					for k in 3:   # как _add_vehicle: остальная клетка — без сдвига случайных чисел
						rng.randf()
					continue
				_add_vehicle(rng, put, "tank" if rng.randf() < 0.4 else "truck", w, dir, ctx)
	_bridges(rng, put, obj, key, ctx)
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
		mmi.name = kind
		var small: bool = kind in ["shrub", "boulders", "poplar", "orchard"]
		# 3.5 (правка 7): «Низкое» — модели биома без теней (вдвое меньше вызовов отрисовки), «Среднее» — мелкие без теней
		var no_shadow := Settings.gfx == 0 or (Settings.gfx == 1 and small)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if no_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mmi)
		# оптимизация (после #105): на «Максимальном» деревья полной детализации (11–14 тыс. треуг.) тень
		# отбрасывают «карточками» той же модели (6 треуг.) — в садах у кишлаков это ~0,6 млн треуг. в проходе теней
		if not no_shadow and LITE.has(kind) and Settings.gfx >= Settings.GFX_MAX:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var lk: String = kind + "_lite"
			if not _meshes.has(lk):
				_meshes[lk] = _lite_tree(kind)
			var mm2 := MultiMesh.new()
			mm2.transform_format = MultiMesh.TRANSFORM_3D
			mm2.mesh = _meshes[lk]
			mm2.instance_count = arr.size()
			for j in arr.size():
				mm2.set_instance_transform(j, arr[j])
			var sh := MultiMeshInstance3D.new()
			sh.multimesh = mm2
			sh.name = kind + "_shadow"
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			parent.add_child(sh)


func _add(rng: RandomNumberGenerator, put: Dictionary, kind: String, p: Vector2, keep_out: Array, ctx: Dictionary) -> void:
	for k in keep_out:
		if p.distance_to(k[0]) < float(k[1]):
			return
	_add_sized(rng, put, kind, p, rng.randf_range(float(KINDS[kind][1]), float(KINDS[kind][2])), ctx)


func _add_sized(rng: RandomNumberGenerator, put: Dictionary, kind: String, p: Vector2, w: float, ctx: Dictionary) -> void:
	# M-35: ни один предмет биома (дерево, куст, валун, юрта, мешки) не залезает кроной/краем в охранную зону реки
	if _t.river_guard_dist(p, w * 0.45) < 0.0:
		rng.randf()   # как при постановке: остальная клетка расставляется так же, как до зоны
		return
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


## L-07 (правка Kanta): деревянные мосты — где дорога пересекает ручей посёлка; пешеходный — от оазиса
## через реку к дороге и изредка там, где поля на обоих берегах (крестьянам ходить на поля)
func _bridges(rng: RandomNumberGenerator, put: Dictionary, obj: Dictionary, key: Vector2i, ctx: Dictionary) -> void:
	var ox := key.x * Terrain3D.CHUNK
	var oz := key.y * Terrain3D.CHUNK
	for s in (ctx["sides"] as Dictionary).get(key, []):
		if float(s[2]) >= 0.0:
			continue
		var f0 := _t.river_field(s[0].x, s[0].y) - Terrain3D.D_ROAD
		var f1 := _t.river_field(s[1].x, s[1].y) - Terrain3D.D_ROAD
		if f0 * f1 > 0.0 or f0 == f1:
			continue
		var q: Vector2 = (s[0] as Vector2).lerp(s[1], f0 / (f0 - f1))
		if _in_chunk(q, ox, oz):
			_put_bridge(put, "bridge", q, _road_dir(q).angle(), KINDS["bridge"][1], ctx)
	var spots := []
	for dx in [-1, 0, 1]:   # точка реки у оазиса может лежать в соседней клетке
		for dz in [-1, 0, 1]:
			var o: Dictionary = (ctx["objs"] as Dictionary).get(Vector2i(key.x + dx, key.y + dz), {})
			if not o.is_empty() and o["name"] == "o_oasis":
				spots.append(_t._river_point(o["pos"]))
	if rng.randf() < 0.14:
		var q := _t._field_point(Vector2(ox + rng.randf_range(200, 1200), oz + rng.randf_range(200, 1200)), 0.0)
		var n := _river_normal(q)
		if _t.green(q.x + n.x * 110.0, q.y + n.y * 110.0) > 0.4 and _t.green(q.x - n.x * 110.0, q.y - n.y * 110.0) > 0.4:
			spots.append(q)
	for q: Vector2 in spots:
		if _in_chunk(q, ox, oz) and absf(_t.river_field(q.x, q.y)) < 6.0:
			_put_bridge(put, "footbridge", q, _river_normal(q).angle(), rng.randf_range(KINDS["footbridge"][1], KINDS["footbridge"][2]), ctx)


func _river_normal(q: Vector2) -> Vector2:
	var e := 8.0
	var g := Vector2(_t.river_field(q.x + e, q.y) - _t.river_field(q.x - e, q.y), _t.river_field(q.x, q.y + e) - _t.river_field(q.x, q.y - e))
	return g.normalized() if g.length_squared() > 1e-10 else Vector2.RIGHT


## Мост: пролёт вдоль ang, настил — на уровне берегов (концов пролёта), а не дна русла
func _put_bridge(put: Dictionary, kind: String, q: Vector2, ang: float, span: float, ctx: Dictionary) -> void:
	var d := Vector2.from_angle(ang) * span * 0.5
	var y := maxf(_t.surface(q.x + d.x, q.y + d.y, ctx).y, _t.surface(q.x - d.x, q.y - d.y, ctx).y)
	var lift := 0.015 if kind == "footbridge" else -0.06 + 0.012   # конец настила — на уровне берега
	var t := Transform3D(Basis(Vector3.UP, -ang).scaled(Vector3(span, span, span)), Vector3(q.x, y + lift * span, q.y))
	if not put.has(kind):
		put[kind] = []
	put[kind].append(t)


## Направление вниз по склону (единичный вектор; на ровном — случайное, но детерминированное от точки)
func _downhill(p: Vector2, ctx: Dictionary) -> Vector2:
	var e := 20.0
	var g := Vector2(_t.height(p.x + e, p.y, ctx) - _t.height(p.x - e, p.y, ctx), _t.height(p.x, p.y + e, ctx) - _t.height(p.x, p.y - e, ctx))
	return -g.normalized() if g.length_squared() > 1e-6 else Vector2.from_angle(p.x * 0.013 + p.y * 0.007)


func _slope(p: Vector2, ctx: Dictionary) -> float:
	var e := 20.0
	var dx := _t.height(p.x + e, p.y, ctx) - _t.height(p.x - e, p.y, ctx)
	var dz := _t.height(p.x, p.y + e, ctx) - _t.height(p.x, p.y - e, ctx)
	return Vector2(dx, dz).length() / (2.0 * e)


## Зона рельефа в точке: river (русло с мокрым берегом — охранная зона M-35), road (дорога),
## bank (полоса за охранной зоной), floor (дно долины),
## fan (конусы выноса и осыпи), slope (склон), crest (гребень)
func _zone(p: Vector2, ctx: Dictionary) -> String:
	var v := _t.river_field(p.x, p.y)
	var a := absf(v)
	if a < Terrain3D.RIVER_GUARD:   # M-35: охранная зона реки (вода и мокрый берег) — сюда ничего не ставим
		return "river"
	if absf(v - Terrain3D.D_ROAD) < 16.0:
		return "road"
	if a < Terrain3D.RIVER_GUARD + 40.0:   # прибрежная полоса тополей и кустов — сразу за охранной зоной
		return "bank"
	var sd := absf(_t.stream_field(p.x, p.y, ctx))   # L-09: ручей посёлка — вода и зелень по берегам
	if sd < Terrain3D.STREAM_W * 2.5:
		return "river"
	if sd < Terrain3D.STREAM_W * 2.5 + 35.0:
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


## Элемент сцены прошедшего боя: модель с заданным поворотом, по склону не кренится (сцены — на дне долин)
func _add_scene(rng: RandomNumberGenerator, put: Dictionary, it: Dictionary, ctx: Dictionary) -> void:
	var kind: String = it["k"]
	var w := float(it["w"]) * rng.randf_range(0.92, 1.08)
	var p: Vector2 = it["p"]
	var s := _t.surface(p.x, p.y, ctx)
	var hk: float = (ctx["hk"] as Dictionary).get(kind, -1.0)
	if hk >= 0.0:
		w = minf(w, (-30.0 - s.y) / maxf(hk, 0.01))
	if w < 4.0:
		return
	var t := Transform3D(Basis(Vector3.UP, -float(it["yaw"])).scaled(Vector3(w, w, w)), s - Vector3(0, w * 0.03, 0))
	if not put.has(kind):
		put[kind] = []
	put[kind].append(t)


## Машина стоит вдоль дороги (нос по направлению дороги, лёгкий разворот)
func _add_vehicle(rng: RandomNumberGenerator, put: Dictionary, kind: String, p: Vector2, dir: Vector2, ctx: Dictionary) -> void:
	var w := rng.randf_range(float(KINDS[kind][1]), float(KINDS[kind][2]))
	var s := _t.surface(p.x, p.y, ctx)
	var yaw := -dir.angle() + rng.randf_range(-0.35, 0.35) + (PI if rng.randf() < 0.5 else 0.0)
	var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w, w, w)), s - Vector3(0, w * 0.03, 0))
	if not put.has(kind):
		put[kind] = []
	put[kind].append(t)
