class_name Terrain3D
extends Node3D
## B-26: рельеф «Нагорья Шахрисанг» — бесконечная земля из кусков сетки высот.
## Хребты и ущелья из шума (гребневой fbm + маска гор), под поселениями земля выровнена.
## Высота считается одной функцией height() — по ней же ставятся наземные цели, пятна и объекты,
## поэтому один и тот же участок карты всегда одинаковый (зерно — от мира, а не от вылета).
## Координаты: x, z — как 2D-мир (px), y — вверх; base_y — дно долин, рельеф не выше ceiling.

const CHUNK := 1400.0          # совпадает с Background.CHUNK: объекты биома и куски рельефа — одна сетка
const N := 56                  # ячеек сетки по стороне куска (~25 px)
const FLAT_OBJS := {"o_village": 1.0, "o_fort": 1.0, "o_oasis": 1.0, "o_crater": 0.6, "o_wreck": 0.6}

var base_y := -500.0
var ceiling := 470.0           # максимальная высота рельефа над дном долин
var material: Material
var _chunks := {}              # Vector2i → MeshInstance3D
var _objs_cache := {}          # Vector2i → объект биома клетки (или пусто)
var _mask := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _hill := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _bg: Background


func setup(depth: float, mat: Material, bg: Background) -> void:
	base_y = -depth
	ceiling = maxf(depth - 30.0, 0.0)   # запас на крен и толщину моделей у плоскости боя
	material = mat
	_bg = bg
	_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mask.seed = 7311
	_mask.frequency = 1.0 / 5200.0
	_mask.fractal_type = FastNoiseLite.FRACTAL_FBM
	_mask.fractal_octaves = 2
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.seed = 1291
	_ridge.frequency = 1.0 / 2100.0
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5
	_ridge.fractal_gain = 0.5
	_hill.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hill.seed = 4417
	_hill.frequency = 1.0 / 650.0
	_hill.fractal_octaves = 3
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp.seed = 977
	_warp.frequency = 1.0 / 3000.0
	clear()


func clear() -> void:
	for k in _chunks:
		(_chunks[k] as Node).queue_free()
	_chunks.clear()
	_objs_cache.clear()


## Высота рельефа над дном долин (0 … ceiling) в точке мира
func height(x: float, z: float) -> float:
	# лёгкое искривление координат — хребты не выстраиваются по сетке шума
	var wx := x + _warp.get_noise_2d(x, z) * 520.0
	var wz := z + _warp.get_noise_2d(x + 913.0, z - 377.0) * 520.0
	var m := smoothstep(-0.12, 0.38, _mask.get_noise_2d(wx, wz))      # где горы
	var r := clampf((_ridge.get_noise_2d(wx, wz) + 1.0) * 0.5, 0.0, 1.0) # гребни
	var mountains := m * pow(r, 1.7)
	var hills := (_hill.get_noise_2d(x, z) + 1.0) * 0.5
	var h := mountains * 0.95 + hills * 0.07 * (1.0 - m * 0.5)
	h *= _flat(x, z)
	return clampf(h, 0.0, 1.0) * ceiling


## Точка мира на поверхности рельефа
func surface(x: float, z: float) -> Vector3:
	return Vector3(x, base_y + height(x, z), z)


## Под кишлаками, крепостями, оазисами земля ровная (вес 0 — плоско, 1 — рельеф как есть)
func _flat(x: float, z: float) -> float:
	if _bg == null:
		return 1.0
	var cx := int(floorf(x / CHUNK))
	var cz := int(floorf(z / CHUNK))
	var k := 1.0
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var o := _obj(Vector2i(cx + dx, cz + dz))
			if o.is_empty() or not FLAT_OBJS.has(o["name"]):
				continue
			var r: float = float(o["size"]) * 0.55
			var d := Vector2(x, z).distance_to(o["pos"])
			var f := smoothstep(r, r * 2.2, d)
			k = minf(k, lerpf(1.0 - float(FLAT_OBJS[o["name"]]), 1.0, f))
	return k


func _obj(key: Vector2i) -> Dictionary:
	if not _objs_cache.has(key):
		_objs_cache[key] = _bg.chunk_object(key.x, key.y)
	return _objs_cache[key]


## Держим куски рельефа под видимой областью; новые строим не больше budget за кадр
func sync(view: Rect2, budget := 2) -> void:
	var want := {}
	for cx in range(int(floorf(view.position.x / CHUNK)), int(floorf(view.end.x / CHUNK)) + 1):
		for cz in range(int(floorf(view.position.y / CHUNK)), int(floorf(view.end.y / CHUNK)) + 1):
			want[Vector2i(cx, cz)] = true
	# сначала ближние к центру
	var c := view.get_center() / CHUNK
	var keys := want.keys()
	keys.sort_custom(func(a, b): return Vector2(a).distance_squared_to(c) < Vector2(b).distance_squared_to(c))
	for key in keys:
		if _chunks.has(key):
			continue
		if budget <= 0:
			break
		budget -= 1
		_chunks[key] = _build(key)
	for key in _chunks.keys():
		if not want.has(key):
			(_chunks[key] as Node).queue_free()
			_chunks.erase(key)
	if _objs_cache.size() > 400:
		_objs_cache.clear()


func _build(key: Vector2i) -> MeshInstance3D:
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var step := CHUNK / N
	var W := N + 3   # +1 узел и по одному с каждой стороны — нормали на стыках кусков совпадают
	var hs := PackedFloat32Array()
	hs.resize(W * W)
	for j in W:
		for i in W:
			hs[j * W + i] = height(ox + (i - 1) * step, oz + (j - 1) * step)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var cols := PackedColorArray()
	var V := N + 1
	verts.resize(V * V)
	norms.resize(V * V)
	tans.resize(V * V * 4)
	cols.resize(V * V)
	for j in V:
		for i in V:
			var gi := (j + 1) * W + (i + 1)
			var hx := hs[gi + 1] - hs[gi - 1]
			var hz := hs[gi + W] - hs[gi - W]
			var n := Vector3(-hx, 2.0 * step, -hz).normalized()
			var vi := j * V + i
			verts[vi] = Vector3(ox + i * step, base_y + hs[gi], oz + j * step)
			norms[vi] = n
			var t := Vector3(2.0 * step, hx, 0.0).normalized()
			tans[vi * 4] = t.x
			tans[vi * 4 + 1] = t.y
			tans[vi * 4 + 2] = t.z
			tans[vi * 4 + 3] = -1.0
			# затенение впадин: насколько точка ниже среднего соседей (в R), высота 0…1 (в G)
			var avg := (hs[gi - 1] + hs[gi + 1] + hs[gi - W] + hs[gi + W]) * 0.25
			var cav := clampf(0.5 + (hs[gi] - avg) / 30.0, 0.0, 1.0)
			cols[vi] = Color(cav, hs[gi] / maxf(ceiling, 1.0), 0.0, 1.0)
	var idx := PackedInt32Array()
	idx.resize(N * N * 6)
	var p := 0
	for j in N:
		for i in N:
			var a := j * V + i
			var b := a + 1
			var c2 := a + V
			var d := c2 + 1
			# диагональ по меньшему перепаду — меньше «пилы» на гребнях
			if absf(hs[(j + 1) * W + i + 1] - hs[(j + 2) * W + i + 2]) < absf(hs[(j + 1) * W + i + 2] - hs[(j + 2) * W + i + 1]):
				idx[p] = a; idx[p + 1] = b; idx[p + 2] = d
				idx[p + 3] = a; idx[p + 4] = d; idx[p + 5] = c2
			else:
				idx[p] = a; idx[p + 1] = b; idx[p + 2] = c2
				idx[p + 3] = b; idx[p + 4] = d; idx[p + 5] = c2
			p += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TANGENT] = tans
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi


## Самая высокая точка рельефа рядом с p (для стенда скриншотов)
func find_peak(p: Vector2, radius := 6000.0) -> Vector2:
	var best := p
	var best_h := -1.0
	var s := 250.0
	var x := -radius
	while x <= radius:
		var z := -radius
		while z <= radius:
			var h := height(p.x + x, p.y + z)
			if h > best_h:
				best_h = h
				best = Vector2(p.x + x, p.y + z)
			z += s
		x += s
	return best
