class_name SeaProps
extends RefCounted
## «Архипелаг Таласора» (Biome.sea): модели биома 2 (game/models/biome2) на берегах пролива.
## Композиции — docs/biome2/placement-variants.md, раздел 2 (решение Kanta 18.10.2026: берём все 6):
## 1 гавань (причалы и склады у воды, дома выше по склону, лодки, волнорез), 2 мыс с маяком (буи, РЛС, остов
## на отмели), 3 батарея на вершине (орудия дугой к морю, бункер сзади, руины рядом), 4 пляж под обороной (ежи у
## кромки, доты, остовы барж на мели), 6 риф с остовом. 5 — морской конвой (convoy.gd). Запреты оттуда же:
## посёлок не на мысу и не на вершине, маяк не в бухте, батарея не на склоне и не у воды, остовы — только на мели.
## Правки Нагорья: модели не наползают друг на друга (keep), ничего не висит над водой, кроме того, что в воде стоит.
## Одна композиция на клетку рельефа (1 400 px): тип — по хэшу клетки, место — лучшая точка клетки по правилам;
## нет подходящего места — клетка остаётся природной. Соседние гавани не ближе клетки (как SETTLE_GAP Нагорья).

## вид: [файл, ширина px мин, макс] — ширина по X (модели нормированы: длина по X = 1, низ в y = 0);
## ≈ 6 px на метр (docs/biome2/models-pipeline.md)
const KINDS := {
	"s_gun": ["res://models/biome2/a01_battery_gun", 56.0, 64.0],
	"s_gun_broken": ["res://models/biome2/a01_battery_gun_broken", 56.0, 64.0],
	"s_bunker": ["res://models/biome2/a02_bunker_coast", 120.0, 140.0],
	"s_radar": ["res://models/biome2/a03_radar_mast", 50.0, 54.0],   # 9 m pad and fence at ~6 px/m (B2-Q05)
	"s_lighthouse": ["res://models/biome2/a04_lighthouse", 80.0, 90.0],
	"s_pier_a": ["res://models/biome2/a05_pier_a", 160.0, 210.0],
	"s_pier_b": ["res://models/biome2/a06_pier_b", 150.0, 200.0],
	"s_tetrapod": ["res://models/biome2/a07_tetrapod", 20.0, 26.0],
	"s_store_a": ["res://models/biome2/a08_warehouse_a", 140.0, 170.0],
	"s_store_b": ["res://models/biome2/a09_warehouse_b", 90.0, 110.0],
	"s_crane": ["res://models/biome2/a10_crane", 120.0, 140.0],
	"s_ruins": ["res://models/biome2/a11_tower_ruins", 100.0, 120.0],
	"s_house_1": ["res://models/biome2/a12_house_1", 50.0, 64.0],
	"s_house_2": ["res://models/biome2/a13_house_2", 50.0, 64.0],
	"s_house_3": ["res://models/biome2/a14_house_3", 60.0, 76.0],
	"s_house_4": ["res://models/biome2/a15_house_4", 54.0, 68.0],
	"s_house_5": ["res://models/biome2/a16_house_5", 48.0, 60.0],
	"s_house_6": ["res://models/biome2/a17_house_6", 56.0, 70.0],
	"s_house_7": ["res://models/biome2/a18_house_7", 46.0, 58.0],
	"s_house_8": ["res://models/biome2/a19_house_8", 52.0, 66.0],
	"s_bell": ["res://models/biome2/a20_bell_tower", 28.0, 32.0],
	"s_terrace": ["res://models/biome2/a21_terrace_wall", 56.0, 70.0],
	"s_buoy_red": ["res://models/biome2/a22_buoy_red", 11.0, 13.0],
	"s_buoy_green": ["res://models/biome2/a23_buoy_green", 11.0, 13.0],
	"s_boat_a": ["res://models/biome2/a24_boat_a", 52.0, 62.0],
	"s_boat_b": ["res://models/biome2/a25_boat_b", 56.0, 66.0],
	"s_wreck_a": ["res://models/biome2/a26_wreck_a", 70.0, 90.0],
	"s_wreck_b": ["res://models/biome2/a27_wreck_b", 170.0, 220.0],
	"s_wreck_plane": ["res://models/biome2/a28_wreck_plane_sea", 80.0, 95.0],
	"s_hedgehog": ["res://models/biome2/a29_hedgehog", 12.0, 15.0],
	"s_boom": ["res://models/biome2/a30_boom_net", 200.0, 240.0],
	"s_cliff_a": ["res://models/biome2/a31_cliff_a", 120.0, 200.0],
	"s_rock": ["res://models/biome2/a33_rock", 16.0, 36.0],
	"s_olive_a": ["res://models/biome2/a34_olive_a", 38.0, 50.0],
	"s_olive_b": ["res://models/biome2/a35_olive_b", 38.0, 50.0],
	"s_pine_a": ["res://models/biome2/a36_pine_a", 44.0, 58.0],
	"s_pine_b": ["res://models/biome2/a37_pine_b", 26.0, 34.0],
	"s_tree": ["res://models/biome2/a38_tree_leaf", 40.0, 54.0],
	"s_reed": ["res://models/biome2/a39_reed", 14.0, 22.0],
	"s_shrub": ["res://models/biome2/a40_shrub", 20.0, 34.0],
}
## ширины видов (мин, макс) отдельно от KINDS: Vector2 без вложенных Array — таблицу читает поток генерации
const SIZE := {
	"s_gun": Vector2(56.0, 64.0),
	"s_gun_broken": Vector2(56.0, 64.0),
	"s_bunker": Vector2(120.0, 140.0),
	"s_radar": Vector2(50.0, 54.0),
	"s_lighthouse": Vector2(80.0, 90.0),
	"s_pier_a": Vector2(160.0, 210.0),
	"s_pier_b": Vector2(150.0, 200.0),
	"s_tetrapod": Vector2(20.0, 26.0),
	"s_store_a": Vector2(140.0, 170.0),
	"s_store_b": Vector2(90.0, 110.0),
	"s_crane": Vector2(120.0, 140.0),
	"s_ruins": Vector2(100.0, 120.0),
	"s_house_1": Vector2(50.0, 64.0),
	"s_house_2": Vector2(50.0, 64.0),
	"s_house_3": Vector2(60.0, 76.0),
	"s_house_4": Vector2(54.0, 68.0),
	"s_house_5": Vector2(48.0, 60.0),
	"s_house_6": Vector2(56.0, 70.0),
	"s_house_7": Vector2(46.0, 58.0),
	"s_house_8": Vector2(52.0, 66.0),
	"s_bell": Vector2(28.0, 32.0),
	"s_terrace": Vector2(56.0, 70.0),
	"s_buoy_red": Vector2(11.0, 13.0),
	"s_buoy_green": Vector2(11.0, 13.0),
	"s_boat_a": Vector2(52.0, 62.0),
	"s_boat_b": Vector2(56.0, 66.0),
	"s_wreck_a": Vector2(70.0, 90.0),
	"s_wreck_b": Vector2(170.0, 220.0),
	"s_wreck_plane": Vector2(80.0, 95.0),
	"s_hedgehog": Vector2(12.0, 15.0),
	"s_boom": Vector2(200.0, 240.0),
	"s_cliff_a": Vector2(120.0, 200.0),
	"s_rock": Vector2(16.0, 36.0),
	"s_olive_a": Vector2(38.0, 50.0),
	"s_olive_b": Vector2(38.0, 50.0),
	"s_pine_a": Vector2(44.0, 58.0),
	"s_pine_b": Vector2(26.0, 34.0),
	"s_tree": Vector2(40.0, 54.0),
	"s_reed": Vector2(14.0, 22.0),
	"s_shrub": Vector2(20.0, 34.0),
}
## B2-Q08 (Kanta 07.11, close-up № 5): kinds that stand in the water get a contact-foam disc (BiomeProps
## _foam_disc) at the waterline: length × beam of the disc in model widths (the model's X axis is its length).
const FOAM_KIND := "s_foam"
const FOAM := {
	"s_boat_a": Vector2(1.18, 0.42), "s_boat_b": Vector2(1.18, 0.42),
	"s_wreck_a": Vector2(1.15, 0.42), "s_wreck_b": Vector2(1.12, 0.22), "s_wreck_plane": Vector2(0.7, 0.7),
	"s_rock": Vector2(1.25, 1.25), "s_tetrapod": Vector2(1.3, 1.3),
	"s_buoy_red": Vector2(1.7, 1.7), "s_buoy_green": Vector2(1.7, 1.7),
}
## Hulls broken in two get one disc per part instead (one ellipse round both drew a foam ring across the gap;
## the sunk stern of s_wreck_b shows only its bridge, so its disc hugs the bridge):
## x, y — centre along / across the hull, z, w — length × beam, all in model widths
const FOAM_SPLIT := {
	"s_wreck_b": [Vector4(0.26, 0.0, 0.66, 0.2), Vector4(-0.39, 0.01, 0.22, 0.2)],
}
## Half beam of piers and boats in model widths (from the .glb bounds), for the harbour overlap test
const PIER_BEAM := {"s_pier_a": 0.1, "s_pier_b": 0.045}
const BOAT_BEAM := {"s_boat_a": 0.14, "s_boat_b": 0.23}
const HOUSES := ["s_house_1", "s_house_2", "s_house_3", "s_house_4", "s_house_5", "s_house_6", "s_house_7", "s_house_8"]
const SMALL := ["s_shrub", "s_reed", "s_rock", "s_hedgehog", "s_tetrapod", "s_buoy_red", "s_buoy_green", "s_olive_a", "s_olive_b", "s_tree", "s_pine_a", "s_pine_b"]
# Worker-thread copies of the lists plan() reads: plan() runs on Terrain3D's chunk tasks, and an element of a
# const (read-only) Array comes back through one scratch slot per array, so threads reading HOUSES at once took
# each other's house (the BiomeProps race fixed in #488, tests/sea_props_thread_test.gd). Built when the script
# loads, on the main thread; the consts stay the source of truth.
static var _houses := PackedStringArray(HOUSES)
static var _small := PackedStringArray(SMALL)

## доли клеток по композициям («Сколько чего на одну карту», вариант A): остальное — только природа
const COMP_KEYS: PackedStringArray = ["harbor", "cape", "battery", "beach", "reef"]
const COMP_SHARE: PackedFloat32Array = [0.2, 0.16, 0.16, 0.05, 0.2]

var _bp: BiomeProps
var _t: Terrain3D
var _put := {}
var _keep := []   # [центр, радиус] — занятые места клетки
var _rng: RandomNumberGenerator
var _ctx := {}


func _init(bp: BiomeProps) -> void:
	_bp = bp
	_t = bp._t


static func comp_of(key: Vector2i) -> String:
	var r := float(hash(key) % 10007) / 10007.0
	# упакованные массивы без вложенных Array: comp_of зовётся и из потока генерации
	for i in COMP_SHARE.size():
		if r < COMP_SHARE[i]:
			return COMP_KEYS[i]
		r -= COMP_SHARE[i]
	return ""


func plan(key: Vector2i, ctx: Dictionary) -> Dictionary:
	_rng = RandomNumberGenerator.new()
	_rng.seed = hash(key) ^ 0x5ea41
	_ctx = ctx
	_put = {}
	_keep = []
	var o := Vector2(key.x, key.y) * Terrain3D.CHUNK
	match comp_of(key):
		"harbor":
			# соседняя клетка с гаванью и бо́льшим хэшем — эта уступает (гавани не слипаются)
			var alone := true
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var nk := Vector2i(key.x + dx, key.y + dz)
					if nk != key and comp_of(nk) == "harbor" and hash(nk) > hash(key):
						alone = false
			if alone:
				_harbor(o)
		"cape":
			_cape(o)
		"battery":
			_battery(o)
		"beach":
			_beach(o)
		"reef":
			_reef(o)
	_nature(o)
	return _put


# ---------- поле берега ----------

## px от кромки воды: > 0 — суша, < 0 — вода (в воде — условно: доля глубины × 100)
func shore(p: Vector2) -> float:
	var v := absf(_t.river_field(p.x, p.y))
	return v - Terrain3D.SEA_W if v >= Terrain3D.SEA_W else -Terrain3D.sea_depth(v) * 100.0


## Единичный вектор от суши к воде (по полю берега)
func seaward(p: Vector2) -> Vector2:
	var e := 10.0
	var g := Vector2(absf(_t.river_field(p.x + e, p.y)) - absf(_t.river_field(p.x - e, p.y)),
		absf(_t.river_field(p.x, p.y + e)) - absf(_t.river_field(p.x, p.y - e)))
	return -g.normalized() if g.length_squared() > 1e-10 else Vector2.RIGHT


## Доля воды на окружности радиуса r вокруг p (мыс — много воды вокруг, бухта — мало)
func water_frac(p: Vector2, r: float) -> float:
	var n := 0
	for i in 16:
		var q := p + Vector2.from_angle(TAU * i / 16.0) * r
		if shore(q) < 0.0:
			n += 1
	return n / 16.0


func h01(p: Vector2) -> float:
	return _t.height(p.x, p.y, _ctx) / maxf(_t.ceiling, 1.0)


func slope(p: Vector2) -> float:
	return _bp._slope(p, _ctx)


## True when the ground within r of p is level: 8 rim points and the centre differ by at most tol px in height
## and none of them is on a steep slope (a pad or a gun pit must not overhang a cliff)
func _level(p: Vector2, r: float, tol: float) -> bool:
	var h0 := _t.height(p.x, p.y, _ctx)
	if slope(p) > 0.25:
		return false
	for i in 8:
		var q := p + Vector2.from_angle(TAU * i / 8.0) * r
		if absf(_t.height(q.x, q.y, _ctx) - h0) > tol or slope(q) > 0.45:
			return false
	return true


func room(p: Vector2, r: float) -> bool:
	for k in _keep:
		if p.distance_to(k[0]) < r + float(k[1]):
			return false
	return true


## Лучшая точка клетки по оценке score (меньше — лучше; INF — не годится)
func _best(o: Vector2, tries: int, score: Callable, margin := 160.0) -> Vector2:
	var best := Vector2.INF
	var bs := INF
	for i in tries:
		var p := o + Vector2(_rng.randf_range(margin, Terrain3D.CHUNK - margin), _rng.randf_range(margin, Terrain3D.CHUNK - margin))
		var s: float = score.call(p)
		if s < bs:
			bs = s
			best = p
	return best


## Поставить модель: w — ширина, yaw — направление оси X модели (угол в плоскости мира), y — высота (NAN — по рельефу)
func put(kind: String, p: Vector2, w: float, yaw: float, r_keep := -1.0, y := NAN, tilt := 0.0) -> void:
	var s := _t.surface(p.x, p.y, _ctx)
	var hk: float = (_ctx["hk"] as Dictionary).get(kind, -1.0)
	var yy := s.y if is_nan(y) else y
	if hk >= 0.0:
		w = minf(w, (-30.0 - yy) / maxf(hk, 0.01))   # не выше 30 px до плоскости боя (как модели Нагорья)
	if w < 4.0:
		return
	var b := Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, tilt)
	var sink := w * 0.04 if is_nan(y) else 0.0
	var t := Transform3D(b.scaled(Vector3(w, w, w)), Vector3(p.x, yy - sink, p.y))
	if not _put.has(kind):
		_put[kind] = []
	_put[kind].append(t)
	if not is_nan(y) and FOAM.has(kind) and shore(p) < 0.0:
		var fs: Vector2 = FOAM[kind]
		var parts: Array = FOAM_SPLIT.get(kind, [Vector4(0.0, 0.0, fs.x, fs.y)])
		if not _put.has(FOAM_KIND):
			_put[FOAM_KIND] = []
		for f: Vector4 in parts:
			var fb := Basis(Vector3.UP, -yaw) * Basis.from_scale(Vector3(w * f.z, 1.0, w * f.w))
			var c := p + Vector2(f.x, f.y).rotated(yaw) * w   # model X lies along from_angle(yaw) in (x, z)
			_put[FOAM_KIND].append(Transform3D(fb, Vector3(c.x, water_y(p) + 0.6, c.y)))
	if r_keep > 0.0:
		_keep.append([p, r_keep])


## True when capsule c ([a, b, half_beam]) keeps at least gap px from every capsule in caps
func _caps_clear(caps: Array, c: Array, gap: float) -> bool:
	for o: Array in caps:
		if _seg_dist(c[0], c[1], o[0], o[1]) < float(c[2]) + float(o[2]) + gap:
			return false
	return true


## Shortest distance between segments a–b and c–d (zero when they cross)
static func _seg_dist(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var r := b - a
	var s := d - c
	var den := r.cross(s)
	if absf(den) > 1e-6:
		var tt := (c - a).cross(s) / den
		var uu := (c - a).cross(r) / den
		if tt >= 0.0 and tt <= 1.0 and uu >= 0.0 and uu <= 1.0:
			return 0.0
	return minf(minf(Geometry2D.get_closest_point_to_segment(a, c, d).distance_to(a), Geometry2D.get_closest_point_to_segment(b, c, d).distance_to(b)),
		minf(Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c), Geometry2D.get_closest_point_to_segment(d, a, b).distance_to(d)))


func size(kind: String) -> float:
	var w: Vector2 = SIZE[kind]
	return _rng.randf_range(w.x, w.y)


## Уровень воды у точки в воде (рельеф под водой ровный — дно пролива и есть поверхность воды в шейдере)
func water_y(p: Vector2) -> float:
	return _t.surface(p.x, p.y, _ctx).y


# ---------- 1. гавань ----------

func _harbor(o: Vector2) -> void:
	# берег не на мысу (вода на ~половине окружности) и с пологим склоном за ним — там встаёт посёлок
	var p := _best(o, 60, func(q: Vector2) -> float:
		var sd := shore(q)
		if sd < 2.0 or sd > 24.0:
			return INF
		var wf := water_frac(q, 320.0)
		if wf < 0.25 or wf > 0.55:
			return INF
		var n := -seaward(q)
		var back := q + n * 220.0
		if shore(back) < 150.0 or h01(back) > 0.3:
			return INF
		return slope(q + n * 120.0) + absf(wf - 0.4))
	if p == Vector2.INF:
		return
	var sea := seaward(p)
	var n := -sea
	var t := n.orthogonal()
	# причалы — 2–3 в воду поперёк берега; у каждого 1–2 лодки.
	# B2-Q10 (Kanta 07.11: «наложение моделей»): in a curved bay the piers converged and the boats, set at a fixed
	# 26–34 px from the pier axis, sank into the deck. Each pier and boat is now a capsule (segment + half beam);
	# a new one is placed only clear of all the others, with a gap
	var caps: Array = []   # [a, b, half_beam]
	var np := _rng.randi_range(2, 3)
	for i in np:
		var a := (i - (np - 1) * 0.5) * _rng.randf_range(130.0, 160.0)
		var root := _snap_shore(p + t * a)
		if root == Vector2.INF:
			continue
		var sw := seaward(root)
		var kind := "s_pier_a" if i % 2 == 0 else "s_pier_b"
		var w := size(kind)
		var c := root + sw * w * 0.42
		if shore(c + sw * w * 0.45) > -2.0:
			continue   # конец причала на суше — бухта слишком мелкая
		var pc := [c - sw * w * 0.5, c + sw * w * 0.5, w * PIER_BEAM[kind]]
		if not _caps_clear(caps, pc, 40.0):
			continue   # would cross or crowd a pier already built: no room for boats between them
		caps.append(pc)
		put(kind, c, w, sw.angle(), 0.0, water_y(c) + 1.0)
		_keep.append([c, w * 0.15])
		_keep.append([c + sw * w * 0.3, w * 0.15])
		for b in _rng.randi_range(1, 2):
			var bk := "s_boat_a" if _rng.randf() < 0.5 else "s_boat_b"
			var bw := size(bk)
			var side := 1.0 if b == 0 else -1.0
			for k in 4:
				var yaw := sw.angle() + _rng.randf_range(-0.12, 0.12)
				var off: float = pc[2] + bw * BOAT_BEAM[bk] + _rng.randf_range(4.0, 10.0)
				var bq := c + sw * _rng.randf_range(-0.05, 0.3) * w + sw.orthogonal() * side * off
				var bd := Vector2.from_angle(yaw) * bw * 0.5
				var bc := [bq - bd, bq + bd, bw * BOAT_BEAM[bk]]
				if shore(bq) < -3.0 and shore(bq + bd) < 0.0 and shore(bq - bd) < 0.0 and _caps_clear(caps, bc, 3.0):
					caps.append(bc)
					put(bk, bq, bw, yaw, 30.0, water_y(bq))
					break
	# склады и кран у воды
	for sg: float in [-1.0, 1.0]:
		var kind := "s_store_a" if sg < 0.0 else "s_store_b"
		var w := size(kind)
		var q := p + n * (40.0 + w * 0.25) + t * sg * _rng.randf_range(70.0, 110.0)
		if shore(q) > 15.0 and slope(q) < 0.35 and room(q, w * 0.3):
			put(kind, q, w, t.angle(), w * 0.45)
	var cq := _snap_shore(p + t * _rng.randf_range(-40.0, 40.0))
	if cq != Vector2.INF:
		cq += n * 28.0
		if room(cq, 40.0):
			put("s_crane", cq, size("s_crane"), t.angle() + PI * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0), 45.0)
	# волнорез: ряд тетраподов у входа в гавань, на мели
	var bw := p + sea * 260.0 + t * _rng.randf_range(-220.0, -160.0)
	for i in _rng.randi_range(8, 12):
		var q := bw + t * i * 20.0 + Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-5, 5))
		if shore(q) < -2.0 and shore(q) > -60.0:
			put("s_tetrapod", q, size("s_tetrapod"), _rng.randf() * TAU, 0.0, water_y(q) - 4.0, _rng.randf_range(-0.4, 0.4))
	# посёлок: дома выше по склону веером, фасадом к морю; не на мысу и не на вершине
	var homes := 0
	var want := _rng.randi_range(16, 26)
	var bell := false
	for i in 140:
		if homes >= want:
			break
		var d := _rng.randf_range(110.0, 460.0)
		var q := p + n * d + t * _rng.randf_range(-1.0, 1.0) * (160.0 + d * 0.5)
		var kind: String = _houses[_rng.randi() % _houses.size()]
		var w := size(kind)
		if shore(q) < 60.0 or slope(q) > 0.55 or h01(q) > 0.45 or not room(q, w * 0.42):
			continue
		var face := (q - p).normalized().angle() + PI * 0.5 + _rng.randf_range(-0.25, 0.25)
		put(kind, q, w, face, w * 0.5)
		homes += 1
		if not bell and homes > want / 2 and room(q + t * 70.0, 22.0) and slope(q + t * 70.0) < 0.4:
			put("s_bell", q + t * 70.0, size("s_bell"), face, 22.0)
			bell = true
		# стенки террас ниже домов по склону и оливы в садах
		if _rng.randf() < 0.35:
			var wq := q - n * (w * 0.6)
			if shore(wq) > 40.0 and room(wq, 20.0):
				put("s_terrace", wq, size("s_terrace"), t.angle() + _rng.randf_range(-0.2, 0.2), 0.0)
		if _rng.randf() < 0.5:
			var oq := q + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(45.0, 70.0)
			var ok := "s_olive_a" if _rng.randf() < 0.5 else "s_olive_b"
			if shore(oq) > 50.0 and room(oq, 18.0):
				put(ok, oq, size(ok), _rng.randf() * TAU, 18.0)


## Точка кромки берега рядом с p (по полю берега, со стороны суши на 2 px)
func _snap_shore(p: Vector2) -> Vector2:
	for i in 6:
		var sd := shore(p)
		if sd >= 1.0 and sd <= 6.0:
			return p
		if sd < 0.0:
			p -= seaward(p) * maxf(-sd * 0.6, 6.0)
		else:
			p += seaward(p) * maxf(sd - 3.0, 2.0)
	return p if absf(shore(p)) < 12.0 else Vector2.INF


# ---------- 2. мыс с маяком ----------

func _cape(o: Vector2) -> void:
	# B2-Q08 (Kanta 07.11, close-up № 6: the lighthouse stood on the very edge, part of its fence over the
	# water): the whole fenced yard (half the model width + a strip of shore) must be on land
	var lw := size("s_lighthouse")
	var p := _best(o, 80, func(q: Vector2) -> float:
		var sd := shore(q)
		if sd < lw * 0.5 + 10.0 or sd > lw * 0.5 + 70.0 or slope(q) > 0.5:
			return INF
		for i in 12:
			if shore(q + Vector2.from_angle(TAU * i / 12.0) * (lw * 0.5 + 6.0)) < 4.0:
				return INF
		var wf := water_frac(q, 260.0)
		return INF if wf < 0.55 else 1.0 - wf)
	if p == Vector2.INF:
		return
	var sea := seaward(p)
	var n := -sea
	put("s_lighthouse", p, lw, sea.angle() + PI, 55.0)
	var hq := p + n * 70.0 + n.orthogonal() * 40.0
	if shore(hq) > 25.0 and slope(hq) < 0.5 and room(hq, 28.0):
		put("s_house_5", hq, size("s_house_5"), n.angle(), 30.0)
	var rq := p + n * 170.0
	if shore(rq) > 80.0 and slope(rq) < 0.5 and room(rq, 30.0):
		put("s_radar", rq, size("s_radar"), _rng.randf() * TAU, 30.0)
	# буи у отмели: красный по одну сторону фарватера, зелёный — по другую
	for sg: float in [-1.0, 1.0]:
		var bq := p + sea * _rng.randf_range(170.0, 240.0) + sea.orthogonal() * sg * _rng.randf_range(90.0, 140.0)
		if shore(bq) < -10.0:
			var k := "s_buoy_red" if sg < 0.0 else "s_buoy_green"
			put(k, bq, size(k), 0.0, 0.0, water_y(bq))
	# остов на отмели у мыса — причина маяка
	if _rng.randf() < 0.6:
		_wreck_near(p + sea * 120.0, 160.0)


# ---------- 3. батарея на вершине ----------

func _battery(o: Vector2) -> void:
	var p := _best(o, 70, func(q: Vector2) -> float:
		if shore(q) < 180.0:
			return INF
		var h := h01(q)
		if h < 0.25 or slope(q) > 0.14:
			return INF
		return -h)
	if p == Vector2.INF:
		return
	# куда смотреть: ближайшая вода из 12 направлений
	var face := Vector2.RIGHT
	var best := INF
	for i in 12:
		var d := Vector2.from_angle(TAU * i / 12.0)
		for k in range(1, 9):
			if shore(p + d * k * 160.0) < 0.0:
				if k < best:
					best = k
					face = d
				break
	var side := face.orthogonal()
	for i in 3:
		var a := (i - 1) * 0.55
		# орудие бывает разбитым (Kanta 19.10: «целое и разбитое», как башни «Левиафана») — след прежних налётов
		var gk := "s_gun_broken" if _rng.randf() < 0.3 else "s_gun"
		var gw := size(gk)
		# B2-Q10 (Kanta 07.11: «площадка орудия прям на обрыве»): the slope was checked at the centre only, so a pit
		# could hang half over a cliff. Now the whole pad must be level; try a few distances, else skip this gun
		for dist: float in [80.0, 60.0, 105.0, 130.0, 45.0]:
			var q := p + face.rotated(a) * dist
			if _level(q, gw * 0.55, gw * 0.16):
				put(gk, q, gw, face.rotated(a).angle(), 34.0)
				break
	var bq := p - face * 90.0
	if slope(bq) < 0.35:
		put("s_bunker", bq, size("s_bunker"), side.angle(), 70.0)
	# руины старой крепости рядом, на той же высоте
	if _rng.randf() < 0.7:
		var rq := p + side * (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(200.0, 260.0)
		if shore(rq) > 120.0 and slope(rq) < 0.35 and room(rq, 60.0):
			put("s_ruins", rq, size("s_ruins"), _rng.randf() * TAU, 60.0)


# ---------- 4. пляж под обороной ----------

func _beach(o: Vector2) -> void:
	var p := _best(o, 60, func(q: Vector2) -> float:
		var sd := shore(q)
		if sd < 0.0 or sd > 10.0:
			return INF
		var n := -seaward(q)
		var s := 0.0
		for k in [60.0, 140.0, 220.0]:
			s += slope(q + n * k)
		var wf := water_frac(q, 300.0)
		return INF if wf < 0.3 or wf > 0.6 or s > 0.45 else s)
	if p == Vector2.INF:
		return
	var sea := seaward(p)
	var n := -sea
	var t := n.orthogonal()
	for i in range(-8, 9):
		var q := _snap_shore(p + t * i * 34.0)
		if q == Vector2.INF:
			continue
		q += seaward(q) * _rng.randf_range(4.0, 14.0)
		put("s_hedgehog", q, size("s_hedgehog"), _rng.randf() * TAU, 8.0)
	for sg: float in [-1.0, 1.0]:
		var q := p + n * 150.0 + t * sg * 170.0
		if shore(q) > 100.0 and slope(q) < 0.3 and room(q, 60.0):
			put("s_bunker", q, size("s_bunker") * 0.8, t.angle() + PI, 60.0)   # амбразуры (ось +Z модели) — к морю
	# остовы десантных барж и самолёта на мели перед пляжем — следы неудачной высадки
	for i in _rng.randi_range(2, 3):
		_wreck_near(p + sea * _rng.randf_range(80.0, 150.0) + t * _rng.randf_range(-220.0, 220.0), 80.0, "s_wreck_a")


# ---------- 6. риф ----------

func _reef(o: Vector2) -> void:
	# мель вдали от фарватера (по нему ходит конвой)
	var p := _best(o, 50, func(q: Vector2) -> float:
		var sd := shore(q)
		if sd > -8.0 or sd < -55.0 or absf(_t._river_raw(q.x, q.y)) < Convoy.FAIRWAY + 220.0:
			return INF
		return absf(sd + 30.0))
	if p == Vector2.INF:
		return
	_wreck_near(p, 40.0, "s_wreck_b" if _rng.randf() < 0.45 else "")
	if _rng.randf() < 0.4:
		_wreck_near(p + Vector2.from_angle(_rng.randf() * TAU) * 160.0, 60.0, "s_wreck_plane")
	for i in _rng.randi_range(2, 5):
		var q := p + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(60.0, 150.0)
		if shore(q) < 0.0 and shore(q) > -40.0 and room(q, 15.0):
			put("s_rock", q, size("s_rock"), _rng.randf() * TAU, 15.0, water_y(q) - 6.0)


## Остов на мели около c (не на глубине и не на суше), корпус вдоль берега, с креном
func _wreck_near(c: Vector2, r: float, kind := "") -> void:
	if kind == "":
		kind = "s_wreck_a"
	for i in 10:
		var q := c + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, r)
		var sd := shore(q)
		var w := size(kind)
		if sd < -6.0 and sd > -45.0 and room(q, w * 0.4) and shore(q + seaward(q) * w * 0.3) < 0.0 and shore(q - seaward(q) * w * 0.3) < 0.0:
			var yaw := seaward(q).orthogonal().angle() + _rng.randf_range(-0.5, 0.5)
			# B2-Q08: the rebuilt hulls are taller than the old scans; at 3 % they floated like boxes on the water.
			# Sunk to about half the side height (the barge to its gunwale band, the ship's stern deck nearly awash)
			var sink := 0.06 if kind == "s_wreck_b" else (0.05 if kind == "s_wreck_a" else 0.03)
			put(kind, q, w, yaw, w * 0.4, water_y(q) - w * sink, _rng.randf_range(-0.25, 0.25))
			return


# ---------- природа ----------

## Маквис и сосны по зонам: у воды — тростник и камни (скалистый берег — скалы), на пологих склонах у моря —
## оливы, кусты, лиственные; выше — сосны (пинии), на гребнях — камни. Ровной сыпи нет — группами
func _nature(o: Vector2) -> void:
	for i in 200:
		if Settings.gopt("props") == 0 and i % 2 == 1:
			continue
		var p := o + Vector2(_rng.randf() * Terrain3D.CHUNK, _rng.randf() * Terrain3D.CHUNK)
		var roll := _rng.randf()
		var sd := shore(p)
		if sd < 0.0:
			continue
		var sl := slope(p)
		var h := h01(p)
		var kind := ""
		var n := 1
		if sd < 30.0:
			if sl > 0.35:
				kind = "s_cliff_a" if roll < 0.05 else ("s_rock" if roll < 0.14 else "")
			else:
				kind = "s_reed" if roll < 0.06 else ""
				n = 4
		elif h > 0.55:
			kind = "s_rock" if roll < 0.06 else ("s_pine_b" if roll < 0.09 else "")
		elif h > 0.18 or sl > 0.3:
			# скала-столб (a32) убрана по замечанию Kanta 19.10: на круче — обычная скала
			kind = "s_pine_a" if roll < 0.08 else ("s_pine_b" if roll < 0.14 else ("s_shrub" if roll < 0.22 else ("s_rock" if roll < 0.235 and sl > 0.45 else "")))
			n = 3 if kind in ["s_pine_a", "s_pine_b"] else 1
		else:
			kind = "s_olive_a" if roll < 0.06 else ("s_olive_b" if roll < 0.11 else ("s_shrub" if roll < 0.24 else ("s_tree" if roll < 0.27 else "")))
			n = 2 if kind == "s_shrub" else 1
		if kind == "":
			continue
		for j in n:
			var q := p + (Vector2.ZERO if j == 0 else Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(25.0, 60.0))
			var w := size(kind)
			var s2 := shore(q)
			# крона и камни не нависают над водой (кромка + полширины)
			if s2 < w * 0.5 + (0.0 if kind in ["s_reed", "s_rock", "s_cliff_a"] else 12.0) or not room(q, w * 0.4):
				continue
			if kind == "s_cliff_a":
				put(kind, q, w, seaward(q).angle() + PI * 0.5, w * 0.4)
			else:
				put(kind, q, w, _rng.randf() * TAU, w * 0.3 if _small.has(kind) else w * 0.45)
