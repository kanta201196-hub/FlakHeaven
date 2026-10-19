class_name ModuleParts
## Т-3 (решение владельца 16.10): модули прокачки видны на модели самолёта, ступени по уровню модуля
## ур. 1–2 / 3–4 / 5 (docs/tasks/3d-models-handoff.md):
##   engine  — сопло шире → + кольцо форсажной камеры → + голубой факел (PlaneFx, не меш);
##   armor   — плиты на бортах кабины → + плиты на бортах фюзеляжа → + рама бронестекла на фонаре;
##   gun_dmg — ствол курсовой пушки в носу → + дульный тормоз → + кожух ствола;
##   radio   — штыревая антенна на спине → + антенна на киле → + обтекатель-«таблетка» на спине;
##   seeker  — стеклянная головка на ракетах В-В (seeker_head, вызывает render3d / hangar3d для подвесов).
## Детали — простые меши кодом; места берутся с самой модели (нос, фонарь, спина, киль — по её треугольникам,
## сопла — PlaneFx.SPEC), поэтому одна таблица на все 6 самолётов. Оси модели: длина 1, нос +X, верх +Y.

const IDS := ["engine", "armor", "gun_dmg", "radio"]

static var _anchors := {}
static var _mats := {}


## Ступень детали по уровню модуля: 0 — модуля нет
static func stage(lvl: int) -> int:
	return 0 if lvl <= 0 else (1 if lvl <= 2 else (2 if lvl <= 4 else 3))


## Узел для деталей под моделью (key — «fighter_1» и т. п.); детали собирает update
static func attach(model: Node3D, key: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = "module_parts"
	holder.set_meta("key", key)
	holder.set_meta("sig", "")
	model.add_child(holder)
	if not _anchors.has(key):
		# мерим по облегчённой боевой модели (те же оси, что у модели ангара, в 5 раз меньше треугольников)
		var path := "res://models/battle/fh_battle_%s.glb" % key
		if ResourceLoader.exists(path):
			var inst: Node3D = (load(path) as PackedScene).instantiate()
			_anchors[key] = _measure(inst, key)
			inst.free()
		else:
			_anchors[key] = {}
	return holder


## levels — уровни модулей игрока (Player.taken); детали пересобираются, только когда меняется ступень
static func update(holder: Node3D, levels: Dictionary) -> void:
	var st := {}
	var sig := ""
	for id in IDS:
		st[id] = stage(int(levels.get(id, 0)))
		sig += str(st[id])
	if sig == String(holder.get_meta("sig", "")):
		return
	holder.set_meta("sig", sig)
	for c in holder.get_children():
		c.queue_free()
	var a: Dictionary = _anchors.get(String(holder.get_meta("key")), {})
	if a.is_empty():
		return
	_engine(holder, a, st["engine"])
	_armor(holder, a, st["armor"])
	_gun(holder, a, st["gun_dmg"])
	_radio(holder, a, st["radio"])


static func set_transparency(holder: Node3D, v: float) -> void:
	for c in holder.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).transparency = v


## «Глазастик» на ракете В-В (меш ракеты длиной 1, нос +X): стеклянная головка, крупнее с уровнем, на ступени 3 — зрачок
static func seeker_head(wmi: Node3D, st: int, tier: int) -> void:
	if st <= 0:
		return
	# тест 3.5-s8: ракета с каждой ступенью толще (weapons_hq.py aam: R 0,030 → 0,038 → 0,048)
	var r: float = [0.03, 0.038, 0.048][clampi(tier, 1, 3) - 1] * [1.0, 1.0, 1.25, 1.45][st]
	var nose_x: float = [0.36, 0.44, 0.47][clampi(tier, 1, 3) - 1]
	var g := _sphere(r, r * 1.5, _mat("glass"))
	g.position = Vector3(nose_x, 0, 0)
	wmi.add_child(g)
	var eye := _sphere(r * 0.45, r * 0.45, _mat("eye"))
	eye.position = Vector3(nose_x + r * 0.9, 0, 0)
	wmi.add_child(eye)
	if st >= 3:
		var hl := _sphere(r * 0.16, r * 0.16, _mat("glint"))
		hl.position = Vector3(nose_x + r * 1.25, r * 0.22, r * 0.12)
		wmi.add_child(hl)


# ---------- детали ----------

static func _engine(h: Node3D, a: Dictionary, st: int) -> void:
	if st <= 0:
		return
	for j: Vector3 in a["jets"]:
		var r: float = a["jet_r"]
		# сопло шире: раструб чуть больше штатного, тёмный металл с внутренней «сажей»
		var noz := _tube(r * 1.28, r * 1.05, 0.03, _mat("steel"))
		noz.position = j + Vector3(-0.012, 0, 0)
		h.add_child(noz)
		var soot := _disc(r * 1.05, _mat("dark"))
		soot.position = j + Vector3(-0.026, 0, 0)
		h.add_child(soot)
		if st >= 2:   # кольцо форсажной камеры — цвета побежалости
			var ring := _tube(r * 1.36, r * 1.25, 0.008, _mat("heat"))
			ring.position = j + Vector3(0.012, 0, 0)
			h.add_child(ring)
	h.set_meta("blue_flame", st >= 3)


static func _armor(h: Node3D, a: Dictionary, st: int) -> void:
	if st <= 0:
		return
	var c: Vector3 = a["canopy"]
	var hw: float = a["canopy_hw"]
	for s in [-1.0, 1.0]:
		# накладные плиты на бортах кабины: две пластины с заклёпочным швом
		for k in 2:
			var p := _box(Vector3(0.05, 0.022, 0.004), _mat("armor"))
			p.position = Vector3(c.x - 0.02 + k * 0.052, c.y - a["canopy_h"] * 0.75, s * (hw + 0.002))
			h.add_child(p)
		if st >= 2:   # плиты на бортах фюзеляжа за кабиной
			var f: Vector3 = a["mid"]
			for k in 3:
				var p2 := _box(Vector3(0.045, 0.02, 0.004), _mat("armor"))
				p2.position = Vector3(f.x + 0.05 - k * 0.05, f.y, s * (float(a["mid_hw"]) + 0.002))
				h.add_child(p2)
	if st >= 3:   # бронестекло: толстое лобовое стекло перед фонарём в тёмной раме
		var ln: float = a["canopy_len"]
		var hh: float = a["canopy_h"]
		var x := c.x + ln * 0.5
		var gl := _box(Vector3(0.004, hh * 0.55, hw * 0.95), _mat("glass"))
		gl.position = Vector3(x, c.y - hh * 0.55, 0)
		gl.rotation = Vector3(0, 0, 0.6)   # наклон назад, как козырёк
		h.add_child(gl)
		for z in [-hw * 0.55, hw * 0.55]:
			var post := _box(Vector3(0.004, hh * 0.6, 0.003), _mat("armor"))
			post.position = Vector3(x, c.y - hh * 0.55, z * 0.85)
			post.rotation = Vector3(0, 0, 0.6)
			h.add_child(post)


static func _gun(h: Node3D, a: Dictionary, st: int) -> void:
	if st <= 0:
		return
	var n: Vector3 = a["gun"]
	var ln := 0.06 + 0.012 * st
	var b := _rod(0.0035, ln, _mat("steel"))
	b.position = n + Vector3(ln * 0.5 - 0.02, 0, 0)
	h.add_child(b)
	if st >= 2:   # дульный тормоз
		var mb := _rod(0.0065, 0.012, _mat("dark"))
		mb.position = n + Vector3(ln - 0.022, 0, 0)
		h.add_child(mb)
	if st >= 3:   # кожух ствола
		var sh := _rod(0.0062, ln * 0.45, _mat("armor"))
		sh.position = n + Vector3(ln * 0.18 - 0.02, 0, 0)
		h.add_child(sh)


static func _radio(h: Node3D, a: Dictionary, st: int) -> void:
	if st <= 0:
		return
	var sp: Vector3 = a["spine"]
	var whip := _box(Vector3(0.003, 0.05, 0.003), _mat("dark"))
	whip.position = sp + Vector3(0, 0.025, 0)
	whip.rotation = Vector3(0, 0, 0.35)   # штырь отклонён назад
	h.add_child(whip)
	var base := _rod(0.004, 0.006, _mat("steel"))
	base.position = sp
	base.rotation = Vector3(0, 0, PI / 2.0)
	h.add_child(base)
	if st >= 2:   # антенна на киле: штанга назад с кончика киля
		var f: Vector3 = a["fin"]
		var rod := _rod(0.0022, 0.06, _mat("dark"))
		rod.position = f + Vector3(-0.02, -0.004, 0)
		h.add_child(rod)
	if st >= 3:   # обтекатель-«таблетка» на спине за кабиной
		var dome := _sphere(0.026, 0.008, _mat("radome"))
		dome.scale = Vector3(1.0, 1.0, 0.75)
		dome.position = sp + Vector3(0.06, 0.004, 0)
		h.add_child(dome)


# ---------- места на модели ----------

## Нос, фонарь (верх горба кабины), спина, киль, сопла — по треугольникам модели (кэш по ключу)
static func _measure(model: Node3D, key: String) -> Dictionary:
	var faces := PackedVector3Array()
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var xf := _local_xf(mi, model)
		for v in mi.mesh.get_faces():
			faces.append(xf * v)
	if faces.is_empty():
		return {}
	_index(faces)
	var a := {}
	# нос: самая передняя точка у оси
	var nose := Vector3(-1, 0, 0)
	var fin := Vector3(0, -1, 0)
	for v in faces:
		if absf(v.z) < 0.02 and v.x > nose.x:
			nose = v
		if v.x < -0.18 and v.y > fin.y:
			fin = v
	# фонарь: самый высокий верх на оси в передней половине
	var best := Vector3(0, -1, 0)
	for i in 46:
		var x := 0.02 + i * 0.01
		var y := _surf(faces, x, 0.0, false)
		if not is_nan(y) and y > best.y and x < nose.x - 0.05:
			best = Vector3(x, y, 0)
	if best.y < -0.5:
		best = Vector3(nose.x - 0.2, 0.03, 0)
	a["canopy"] = best
	# длина горба: где верх опускается на 40% высоты горба над спиной за ним
	var back_y := _surf(faces, best.x - 0.18, 0.0, false)
	back_y = best.y - 0.02 if is_nan(back_y) else back_y
	var hump := maxf(best.y - back_y, 0.01)
	var x0 := best.x
	while x0 > best.x - 0.2 and _surf_or(faces, x0, 0.0, back_y) > back_y + hump * 0.4:
		x0 -= 0.005
	var x1 := best.x
	while x1 < nose.x and _surf_or(faces, x1, 0.0, back_y) > back_y + hump * 0.4:
		x1 += 0.005
	a["canopy_len"] = maxf(x1 - x0, 0.06)
	a["canopy_h"] = hump
	a["canopy_hw"] = _half_width(faces, best.x - 0.01, best.y - hump)
	# спина за кабиной, середина фюзеляжа
	var sx := best.x - 0.16
	var sy := _surf(faces, sx, 0.0, false)
	a["spine"] = Vector3(sx, (back_y if is_nan(sy) else sy) - 0.002, 0)
	var mx := best.x - 0.15
	var mlo := _surf(faces, mx, 0.0, true)
	var mhi := _surf(faces, mx, 0.0, false)
	var my := 0.0 if is_nan(mlo) else (mlo + mhi) * 0.5
	a["mid"] = Vector3(mx, my, 0)
	a["mid_hw"] = _half_width(faces, mx, my)
	a["fin"] = fin
	# пушка: в носу сбоку, ниже оси на треть высоты носа
	var gx := nose.x - 0.07
	var glo := _surf(faces, gx, 0.0, true)
	var ghi := _surf(faces, gx, 0.0, false)
	var gy := nose.y if is_nan(glo) else lerpf(glo, ghi, 0.35)
	a["gun"] = Vector3(gx, gy, _half_width(faces, gx, gy) * 0.8)
	# сопла: точки огня PlaneFx (пикс. картинки) → оси модели; высота — середина сечения перед соплом
	var jets: Array = []
	var spec: Dictionary = PlaneFx.SPEC.get(key, {})
	var cls := key.get_slice("_", 0)
	var tex := PlaneArt.plane_tex(cls, int(key.get_slice("_", 1)))
	var tw := float(tex.get_width()) if tex != null else 200.0
	# картинка и модель «Осы» не совпадают по размаху и длине — срез сопла ищем на самой модели:
	# от точки картинки вдоль оси вперёд до обшивки, по ширине — самое толстое сечение рядом
	var rsum := 0.0
	for p: Vector2 in spec.get("jet", []):
		var jx := p.x / tw - 0.06
		var jz := p.y / tw
		while jx < 0.0 and is_nan(_surf(faces, jx, jz, true)):
			jx += 0.004
		var bz := jz
		var bt := -1.0
		for k in 13:
			var z := jz + (k - 6) * 0.004
			var lo := _surf(faces, jx + 0.012, z, true)
			var hi := _surf(faces, jx + 0.012, z, false)
			if not is_nan(lo) and hi - lo > bt:
				bt = hi - lo
				bz = z
		var lo2 := _surf(faces, jx + 0.012, bz, true)
		var hi2 := _surf(faces, jx + 0.012, bz, false)
		jets.append(Vector3(jx, 0.012 if is_nan(lo2) else (lo2 + hi2) * 0.5, bz))
		rsum += maxf(bt, 0.02) * 0.5
	a["jets"] = jets
	a["jet_r"] = rsum / maxf(1.0, jets.size()) * 0.85
	return a


static func _local_xf(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D()
	var c: Node = n
	while c != null and c != root and c is Node3D:
		xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


## Полуширина фюзеляжа на высоте y в сечении x: до первой вертикали, где обшивка не перекрывает y
static func _half_width(faces: PackedVector3Array, x: float, y: float) -> float:
	var z := 0.0
	while z < 0.12:
		var lo := _surf(faces, x, z + 0.003, true)
		var hi := _surf(faces, x, z + 0.003, false)
		if is_nan(lo) or lo > y or hi < y:
			break
		z += 0.003
	return maxf(z, 0.01)


static func _surf_or(faces: PackedVector3Array, x: float, z: float, d: float) -> float:
	var y := _surf(faces, x, z, false)
	return d if is_nan(y) else y


## Сетка по плану (x, z): ячейка → номера треугольников, чтобы вертикаль проверяла только соседей
const CELL := 0.02
static var _grid := {}


static func _index(faces: PackedVector3Array) -> void:
	_grid = {}
	for i in range(0, faces.size(), 3):
		var lo := Vector2(minf(faces[i].x, minf(faces[i + 1].x, faces[i + 2].x)), minf(faces[i].z, minf(faces[i + 1].z, faces[i + 2].z)))
		var hi := Vector2(maxf(faces[i].x, maxf(faces[i + 1].x, faces[i + 2].x)), maxf(faces[i].z, maxf(faces[i + 1].z, faces[i + 2].z)))
		for gx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			for gz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
				var k := Vector2i(gx, gz)
				var arr: PackedInt32Array = _grid.get(k, PackedInt32Array())
				arr.append(i)
				_grid[k] = arr   # PackedInt32Array — значение, не ссылка


static func _surf(faces: PackedVector3Array, x: float, z: float, low: bool) -> float:
	var best := NAN
	var p := Vector2(x, z)
	for i: int in _grid.get(Vector2i(floori(x / CELL), floori(z / CELL)), PackedInt32Array()):
		var a := faces[i]
		var a2 := Vector2(a.x, a.z)
		var v0 := Vector2(faces[i + 1].x, faces[i + 1].z) - a2
		var v1 := Vector2(faces[i + 2].x, faces[i + 2].z) - a2
		var v2 := p - a2
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-12:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var w := (v0.x * v2.y - v2.x * v0.y) / den
		if u < 0.0 or w < 0.0 or u + w > 1.0:
			continue
		var y := a.y + u * (faces[i + 1].y - a.y) + w * (faces[i + 2].y - a.y)
		if is_nan(best) or (low and y < best) or (not low and y > best):
			best = y
	return best


# ---------- меши ----------

static func _mat(n: String) -> StandardMaterial3D:
	if _mats.has(n):
		return _mats[n]
	var m := StandardMaterial3D.new()
	match n:
		"steel":
			m.albedo_color = Color(0.32, 0.33, 0.34)
			m.metallic = 0.7
			m.roughness = 0.4
		"dark":
			m.albedo_color = Color(0.07, 0.07, 0.08)
			m.roughness = 0.6
		"heat":   # побежалость: от бронзы к синеве
			m.albedo_color = Color(0.55, 0.38, 0.3)
			m.metallic = 0.8
			m.roughness = 0.3
		"armor":
			m.albedo_color = Color(0.3, 0.31, 0.29)
			m.metallic = 0.5
			m.roughness = 0.55
		"glass":
			m.albedo_color = Color(0.55, 0.75, 0.8, 0.35)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.3
			m.roughness = 0.05
		"eye":
			m.albedo_color = Color(0.05, 0.08, 0.1)
			m.roughness = 0.1
		"glint":
			m.albedo_color = Color(1, 1, 1)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"radome":
			m.albedo_color = Color(0.82, 0.8, 0.72)
			m.roughness = 0.6
	_mats[n] = m
	return m


static func _mi(mesh: Mesh, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _box(size: Vector3, m: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(b, m)


## Цилиндр вдоль X
static func _rod(r: float, ln: float, m: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = ln
	c.radial_segments = 10
	c.rings = 1
	var mi := _mi(c, m)
	mi.rotation = Vector3(0, 0, -PI / 2.0)
	return mi


## Раструб вдоль X: радиус r0 сзади, r1 спереди, открытые торцы
static func _tube(r0: float, r1: float, ln: float, m: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r0
	c.height = ln
	c.radial_segments = 14
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	var mm := m.duplicate() as StandardMaterial3D
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := _mi(c, mm)
	mi.rotation = Vector3(0, 0, -PI / 2.0)
	return mi


static func _disc(r: float, m: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.002
	c.radial_segments = 14
	c.rings = 1
	var mi := _mi(c, m)
	mi.rotation = Vector3(0, 0, -PI / 2.0)
	return mi


static func _sphere(r: float, h: float, m: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h * 2.0
	s.radial_segments = 12
	s.rings = 6
	return _mi(s, m)
