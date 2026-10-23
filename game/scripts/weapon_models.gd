class_name WeaponModels
## 3.4-t1 (п. 3): объёмное оружие на узлах подвески, вид меняется с уровнем (решение владельца 16.10).
## Ступени вида: 1 — ур. 1–2, 2 — ур. 3–4, 3 — ур. 5 и эволюция.
## Модель строится из простых форм: длина по +X = 1 (нос вперёд), центр в начале координат;
## снаружи масштабируется под длину оружия. Точка вылета снаряда — muzzle() (п. 37).

static var _cache := {}
static var _mats := {}
## Вид турелей (на выбор владельца): 1 — всё с живыми стрелками: остеклённые колпаки и кабина в корме;
## 2 — всё дистанционное: низкие обтекатели и металлический кормовой конус;
## 3 — смешанный: кормовая кабина стрелка + дистанционные башни сверху и снизу
static var turret_style := 3


static func tier(level: int, evo := false) -> int:
	if evo or level >= 5:
		return 3
	return 2 if level >= 3 else 1


## Узел с моделью (общий меш из кэша — копировать дёшево)
## side — место крепления (mounts): от него зависит вид турели; cls — класс самолёта
## (у «Кита» и «Грача» свои турели — модели Blender по фото владельца, 16.10)
## evo — эволюция (у турели — «Дикобраз»), plvl — уровень самолёта (окраска турели под обшивку)
## hq — ангарная версия (тест 3.5-s8: models/weapons/hq/, те же оси и габарит, детали и запечённая окраска)
static func make(weapon: String, t: int, side := "", cls := "", evo := false, plvl := 1, hq := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm: Mesh = turret_model(cls, t, side, evo, plvl) if weapon == "turret" else weapon_model(weapon, t, evo, hq)
	mi.mesh = tm if tm != null else mesh(weapon, t, side)
	# разбор каталога 16.10: подвесное — только на пилоне (ракеты — на пусковой рельс), не «приклеено» к крылу
	if side == "under":
		var pm := MeshInstance3D.new()
		pm.name = "pylon"
		pm.mesh = pylon_mesh(weapon, mi.mesh.get_aabb().end.y)
		mi.add_child(pm)
	# кормовая кабина стрелка неподвижна — поворачивается только шар со стволами (поворот гасит render3d)
	if weapon == "turret" and side == "tail" and tm != null:
		var cab := turret_model(cls, t, "cabin", evo, plvl)
		if cab != null:
			var cmi := MeshInstance3D.new()
			cmi.name = "cabin"
			cmi.mesh = cab
			mi.add_child(cmi)
	return mi


## Турели из Blender (game/tools/blender/turret_*.py → models/turrets): стволы +X, основание на y = 0.
## Масштаб — под размеры прежней турели (длина корпуса TURRET_MODELS.s), обшивка — в цвет самолёта.
## Т-4: файл по ступени (%d — 1 / 2 / 3: ур. 1–2 / 3–4 / 5), эволюция — свой файл «evo».
const TURRET_MODELS := {
	# стволы укорочены на ~40% (владелец 16.10); ступени: 1 — без тормозов, 2 — тормоза и бронещиток,
	# 3 — + короба лент и прицельная головка; эволюция «Дикобраз» — 4 ствола и антенна наведения
	"bomber": {"file": "res://models/turrets/turret_kit_t%d.glb", "evo": "res://models/turrets/turret_kit_quad.glb",
		"s": 0.3, "muzzle": Vector3(2.09, 0.43, 0.0),
		# окраска — средний тон обшивки «Кита 1» / «Кита 2» (Т-2: песочная окраска класса, splinter_camo.py kit)
		"body": [Color(0.45, 0.39, 0.27), Color(0.46, 0.4, 0.28)],
		# корма (пример владельца 16.10): кабина стрелка с фонарём и шаровая установка под килем
		"tail": "res://models/turrets/turret_kit_tail_ball_t%d.glb", "cabin": "res://models/turrets/turret_kit_tail_cabin.glb",
		"muzzle_tail": Vector3(1.36, 0.0, 0.0)},
	# S9-04 (Kanta 23.10: «каждый уровень заметно отличается»): 1 — малая (×0,88), один ствол без щитка;
	# 2 — два ствола один над другим, тормоза, рамка-щиток, короб ленты; 3 — крупная (×1,12), два ствола рядом
	# в кожухах, сплошной бронещиток, два короба, экраны, прицел. muzzle_t — дульный срез по ступени, k — размер
	"attacker": {"file": "res://models/turrets/turret_grach_t%d.glb", "s": 0.36, "muzzle": Vector3(1.17, 0.34, 0.18),
		"muzzle_t": [Vector3(0.792, 0.282, 0.0), Vector3(1.17, 0.34, 0.18), Vector3(1.16, 0.403, 0.0)],
		"k": [0.88, 1.0, 1.12],
		"body": [Color(0.3, 0.3, 0.24), Color(0.31, 0.31, 0.28)]},
}


## Тест 3.5-s3 («ракеты висят в воздухе»): нижняя поверхность модели самолёта на вертикали (x, z) в её осях
## (длина 1) — в бою пилон ставится под настоящее крыло, как в ангаре; NAN — промах. high — верхняя (спина под турель)
static var _faces := {}
static var _low := {}


static func surface_low(scene: PackedScene, x: float, z: float, high := false) -> float:
	var ck := "%s|%.4f|%.4f%s" % [scene.resource_path, x, z, "|h" if high else ""]
	if _low.has(ck):
		return _low[ck]
	if not _faces.has(scene.resource_path):
		var f := PackedVector3Array()
		var inst: Node3D = scene.instantiate()
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			var xf := Transform3D()
			var n: Node = mi
			while n != inst and n is Node3D:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			for v in mi.mesh.get_faces():
				f.append(xf * v)
		inst.free()
		_faces[scene.resource_path] = f
	var fs: PackedVector3Array = _faces[scene.resource_path]
	var best := NAN
	var p := Vector2(x, z)
	for i in range(0, fs.size(), 3):
		var a := fs[i]
		var a2 := Vector2(a.x, a.z)
		var v0 := Vector2(fs[i + 1].x, fs[i + 1].z) - a2
		var v1 := Vector2(fs[i + 2].x, fs[i + 2].z) - a2
		var v2 := p - a2
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-12:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var w := (v0.x * v2.y - v2.x * v0.y) / den
		if u < 0.0 or w < 0.0 or u + w > 1.0:
			continue
		var y := a.y + u * (fs[i + 1].y - a.y) + w * (fs[i + 2].y - a.y)
		if is_nan(best) or (y > best if high else y < best):
			best = y
	_low[ck] = best
	return best


## Пилон под крылом: высота PYLON_H над верхом модели (top), для ракет — длинный пусковой рельс
const PYLON_H := 0.07


static func pylon_mesh(weapon: String, top: float) -> Mesh:
	var key := "pylon_%s_%.3f" % [weapon, top]
	if _cache.has(key):
		return _cache[key]
	var rail := weapon in ["aam", "arm"]
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# стойка пилона: обтекаемая пластина, спереди скошена
	var body := _box(Vector3(0.5 if not rail else 0.36, PYLON_H, 0.03))
	st.append_from(body, 0, Transform3D(Basis(), Vector3(-0.02, top + PYLON_H * 0.5, 0)))
	var nose := _box(Vector3(0.1, PYLON_H * 0.7, 0.028))
	st.append_from(nose, 0, Transform3D(Basis(Vector3.BACK, -0.6), Vector3(0.24 if not rail else 0.17, top + PYLON_H * 0.55, 0)))
	if rail:   # пусковой рельс вдоль ракеты
		st.append_from(_box(Vector3(0.62, 0.012, 0.045)), 0, Transform3D(Basis(), Vector3(-0.02, top + 0.006, 0)))
	st.commit(am)
	am.surface_set_material(0, _mat("hull"))
	_cache[key] = am
	return am


## Глубина подвеса (длина 1): насколько ниже крыла центр модели — верх модели плюс пилон
## (у «Бабушкиного ковра» под фюзеляжем пилона нет: свой узел крепления — вычесть PYLON_H)
static func hang(weapon: String, t: int, evo := false) -> float:
	var m: Mesh = weapon_model(weapon, t, evo)
	if m == null:
		m = mesh(weapon, t)
	return m.get_aabb().end.y + PYLON_H


## Ракеты В-В и блоки НАР из Blender (tools/blender/weapons.py) по примерам владельца 16.10:
## ступени отличаются формой и деталями. Те же оси и длина 1, что у процедурных моделей ниже.
## Т-5: кассетные бомбы (балка → держатель на 4 → кассета) и ловушки (кассеты-«соты» в обшивке → контейнер на законцовке)
const WEAPON_GLB := {"aam": "res://models/weapons/aam_%d.glb", "rockets": "res://models/weapons/rockets_%d.glb",
	"bombs": "res://models/weapons/bombs_%d.glb", "flares": "res://models/weapons/flares_%d.glb",
	"arm": "res://models/weapons/arm_%d.glb"}   # Т-8: противорадарная ракета «Ласки»
## Т-6: эволюция — совсем другая модель (правило владельца): «Шмель», «Ливень», «Салют» (на спине),
## «Бабушкин ковёр» (под фюзеляжем, планка поперёк полёта — свой узел крепления, без пилона)
const EVO_GLB := "res://models/weapons/%s_evo.glb"
## U-08: экспериментальное оружие тяжёлого подвеса — одна модель без ступеней (tools/blender/exp_weapons.py)
const EXP_GLB := "res://models/weapons/exp_%s.glb"


## Тест 3.5-s8 (Kanta: «эволюция бомб нелогична — в конце они меньше и слабее»): шкала калибров по уровню
## оружия — на пилоне одна бомба, та же, что падает: ур. 1 «50» → 2 «100» → 3 «250» → 4 «500» → 5 «1000»
## (tools/blender/weapons_hq.py bombs 1…5, LADDER); модернизация — 8 бомб «250» («ковёр»). Урон не меняется.
static func bomb_t(level: int) -> int:
	return clampi(level, 1, 5)


## Падающая бомба (тест 3.5-s4, п. 10): vt 1–5 — модель калибра с подвеса (bombs_<vt>.glb, тот же масштаб,
## что на пилоне: доля PlaneArt.WEAPON_FRAC), BOMB_EVO_VT — бомба «ковра» (bombdrop_evo.glb, длина 1)
const BOMB_EVO_VT := 6
const DROP_EVO_GLB := "res://models/weapons/bombdrop_evo.glb"
## Длина модели в долях длины самолёта: калибры — как на подвеске (0,27), бомба «ковра» — 0,27 × 0,62
const DROP_LEN := [0.0, 0.27, 0.27, 0.27, 0.27, 0.27, 0.167]


static func drop_mesh(vt: int) -> Mesh:
	var t := clampi(vt, 1, BOMB_EVO_VT)
	if t == BOMB_EVO_VT:
		return _glb_mesh(DROP_EVO_GLB, 1.0, Color(), "glb_drop_evo") if ResourceLoader.exists(DROP_EVO_GLB) else null
	return weapon_model("bombs", t)


## Тест 3.5-s5 (п. 3): «Бабушкин ковёр» у «Кита» — кассета внутри бомбоотсека (weapons.py bombs evobay),
## а не планка снаружи: своя «ступень» модели CARPET_BAY_T. Точки 8 бомб в осях модели (длина 1 = подвес),
## по порядку сброса: ряды спереди назад, в ряду левая и правая — отсюда бомбы падают в бою
const CARPET_BAY_T := 9   # тест 3.5-s8: 1–5 — калибры бомб
const CARPET_BAY_GLB := "res://models/weapons/bombs_evo_bay.glb"
const CARPET_BAY_PTS := [Vector3(0.66, 0, -0.072), Vector3(0.66, 0, 0.072), Vector3(0.22, 0, -0.072), Vector3(0.22, 0, 0.072),
	Vector3(-0.22, 0, -0.072), Vector3(-0.22, 0, 0.072), Vector3(-0.66, 0, -0.072), Vector3(-0.66, 0, 0.072)]


## У самолёта есть бомбоотсек со створками (Т-5: tools/blender/bay_doors.py)
static func has_bay(cls_id: String, lvl: int) -> bool:
	return ResourceLoader.exists("res://models/mech/fh_bay_%s_%d.glb" % [cls_id, lvl])


## Тест 3.5-s8 (Kanta: «для ангара — супер качественные модели, они показываются близко»): ангарные версии
## тех же файлов — фаски, заклёпки, швы, ушки, трафарет, запечённые AO и грязь (tools/blender/weapons_hq.py).
## Оси и габарит как у боевых — подвес (hang) считается по боевой модели.
const HQ_DIR := "res://models/weapons/hq/"


static func weapon_model(weapon: String, t: int, evo := false, hq := false) -> Mesh:
	var file := ""
	if weapon == "bombs" and t == CARPET_BAY_T and ResourceLoader.exists(CARPET_BAY_GLB):
		file = CARPET_BAY_GLB
	elif evo and ResourceLoader.exists(EVO_GLB % weapon):
		file = EVO_GLB % weapon
	elif weapon in Weapons.EXP and ResourceLoader.exists(EXP_GLB % weapon):
		file = EXP_GLB % weapon
	elif WEAPON_GLB.has(weapon):
		file = WEAPON_GLB[weapon] % t
	if file == "" or not ResourceLoader.exists(file):
		return null
	if hq and ResourceLoader.exists(HQ_DIR + file.get_file()):
		file = HQ_DIR + file.get_file()
	return _glb_mesh(file, 1.0, Color(), "glb_" + file.get_file().get_basename() + ("_hq" if file.begins_with(HQ_DIR) else ""))


## part: "" — вся турель (бой), "body" — без люльки со стволами, "guns" — только они в своих осях (шарнир — 0)
static func turret_model(cls: String, t := 1, side := "", evo := false, plvl := 1, part := "") -> Mesh:
	var file := turret_file(cls, t, side, evo)
	if file == "":
		return null
	var spec: Dictionary = TURRET_MODELS[cls]
	var cols: Array = spec["body"]
	var tint: Color = cols[clampi(plvl, 1, cols.size()) - 1]
	var m := _glb_mesh(file, float(spec["s"]), tint, "turret_model_%s_%s_%s%s" % [cls, file.get_file(), tint.to_html(), part], part)
	if cls == "attacker" and side == "top" and m != null and part != "guns":
		var ks: Array = spec.get("k", [1.0, 1.0, 1.0])
		return _with_ring(m as ArrayMesh, float(spec["s"]) * float(ks[clampi(t, 1, 3) - 1]), tint)
	return m


static func turret_file(cls: String, t := 1, side := "", evo := false) -> String:
	var spec: Dictionary = TURRET_MODELS.get(cls, {})
	if spec.is_empty():
		return ""
	var file: String = spec["file"]
	if side in ["tail", "cabin"] and spec.has(side):
		file = spec[side]
	elif evo and spec.has("evo"):
		file = spec["evo"]
	if file.contains("%d"):
		file = file % clampi(t, 1, 3)
	return file if ResourceLoader.exists(file) else ""


static func _rel_xf(n: Node3D, root: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Т-2 (каталог: «погон под турель» у «Грача»): кольцевое основание верхней установки — пояс в цвет корпуса
## чуть шире основания башни (r 0.39 в осях GLB) и тёмный шов погона; нижняя часть уходит в обшивку
static func _with_ring(src: ArrayMesh, s: float, tint: Color) -> ArrayMesh:
	var key := "ring_%d_%s" % [src.get_instance_id(), tint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var am := src.duplicate() as ArrayMesh
	for si in src.get_surface_count():
		am.surface_set_material(si, src.surface_get_material(si))
	var collar := CylinderMesh.new()
	collar.top_radius = 0.47 * s
	collar.bottom_radius = 0.53 * s
	collar.height = 0.14 * s
	collar.radial_segments = 32
	var seam := TorusMesh.new()
	seam.inner_radius = 0.41 * s
	seam.outer_radius = 0.47 * s
	seam.rings = 32
	seam.ring_segments = 6
	var body := StandardMaterial3D.new()
	body.albedo_color = tint
	body.roughness = 0.86   # S9-03: краска матовая, как у самой турели (turret_light.py)
	body.metallic = 0.08
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	dark.roughness = 0.85
	dark.metallic = 0.12
	for part: Array in [[collar, Vector3(0, -0.03 * s, 0), body], [seam, Vector3(0, 0.035 * s, 0), dark]]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(part[0] as Mesh, 0, Transform3D(Basis.from_scale(Vector3(1, 0.5, 1)) if part[0] is TorusMesh else Basis(), part[1]))
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, part[2])
	_cache[key] = am
	return am


## Меш из GLB: все части в один ArrayMesh с масштабом s; материалы «body» перекрашиваются в tint
## part (турели, тест 3.5-s8): "" — корпус и узел «guns» вместе, "body" — без него, "guns" — только он, в своих осях
static func _glb_mesh(file: String, s: float, tint: Color, key: String, part := "") -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var root: Node = (load(file) as PackedScene).instantiate()
	var src: MeshInstance3D = null
	for c in root.find_children("*", "MeshInstance3D", true, false):
		src = c
		break
	if src == null:
		root.free()
		return null
	var srcs: Array = []   # [меш, преобразование в оси модели]
	var guns := root.find_child("guns", true, false) as MeshInstance3D
	var sc := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO)
	if part != "guns":
		srcs.append([src.mesh, sc * _rel_xf(src, root)])
	if guns != null and guns != src and part != "body":
		var gx := _rel_xf(guns, root)
		if part == "guns":
			gx.origin = Vector3.ZERO
		srcs.append([guns.mesh, sc * gx])
	if srcs.is_empty():
		root.free()
		return null
	# по поверхности на материал (корпус и стволы одного материала — одна поверхность, как было до деления)
	var sts := {}
	var mats := {}
	var order: Array = []
	for sm: Array in srcs:
		var me: Mesh = sm[0]
		for si in me.get_surface_count():
			var m: Material = me.surface_get_material(si)
			var mk := String(m.resource_name) if m != null else "_%d" % si
			if not sts.has(mk):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				sts[mk] = st
				mats[mk] = m
				order.append(mk)
			(sts[mk] as SurfaceTool).append_from(me, si, sm[1])
	var am := ArrayMesh.new()
	for mk: String in order:
		(sts[mk] as SurfaceTool).commit(am)
		var m: Material = mats[mk]
		if tint != Color() and m is StandardMaterial3D and String(m.resource_name).contains("body"):
			m = (m as StandardMaterial3D).duplicate()
			(m as StandardMaterial3D).albedo_color = tint
		am.surface_set_material(am.get_surface_count() - 1, m)
	root.free()
	_cache[key] = am
	return am


static func mesh(weapon: String, t: int, side := "") -> ArrayMesh:
	var key := "%s_%d" % [weapon, t]
	if weapon == "turret":
		key += "_%d_%s" % [turret_style, side]
	if _cache.has(key):
		return _cache[key]
	var parts: Array = []   # [меш-примитив, Transform3D, материал]
	match weapon:
		"enemy_msl":
			# тест 3.5-s5 (п. 11): ракета врага — тёмный корпус, красная головка и пояс (не спутать с нашими белыми)
			var body := 0.78
			var r := 0.06
			parts.append([_cyl(r, body), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-0.05, 0, 0)), "dark"])
			parts.append([_cone(r, 0.17), Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(body * 0.5 + 0.035, 0, 0)), "band"])
			parts.append([_cyl(r * 1.04, 0.07), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(body * 0.12, 0, 0)), "band"])
			for a in 4:
				parts.append([_box(Vector3(0.14, 0.01, r * 4.2)), Transform3D(Basis(Vector3.RIGHT, a * PI / 4.0 + PI / 4.0), Vector3(-body * 0.5 + 0.03, 0, 0)), "steel"])
		"aam":
			# 3.5: ракеты — «качество вместо количества» (1 ракета с точки), поэтому с уровнем ракета
			# не множится, а тяжелеет: обычная → крупнее, на пилоне → тяжёлая, с ускорителем
			var r: float = [0.045, 0.055, 0.066][t - 1]
			_missile(parts, Vector3.ZERO, 1.0, r)
			if t >= 2:
				parts.append([_box(Vector3(0.45, 0.06, 0.02)), Transform3D(Basis(), Vector3(0, r + 0.03, 0)), "dark"])
			if t == 3:
				parts.append([_cyl(r * 1.15, 0.22), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-0.32, 0, 0)), "dark"])
		"rockets":
			# малый блок → большой блок → два блока
			var r := 0.13 if t == 1 else 0.18
			var pods: Array = [0.0] if t < 3 else [-0.17, 0.17]
			for z: float in pods:
				_pod(parts, Vector3(0, 0, z), 1.0, r, 7 if t == 1 else 12)
		"bombs":
			# 2 бомбы → 4 → кассета
			if t == 3:
				parts.append([_cyl(0.16, 1.0), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3.ZERO), "olive"])
				parts.append([_cone(0.16, 0.18), Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(0.59, 0, 0)), "olive"])
				for a in 4:
					parts.append([_box(Vector3(0.16, 0.012, 0.2)), Transform3D(Basis(Vector3.RIGHT, a * PI / 2.0), Vector3(-0.42, 0, 0)), "dark"])
			else:
				var n := 2 if t == 1 else 4
				for i in n:
					var z := (i - (n - 1) / 2.0) * 0.16
					_bomb(parts, Vector3(0, 0, z))
		"gunpod":
			# 1 ствол → 2 → 3 ствола в кожухе
			parts.append([_cyl(0.12, 0.75), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-0.1, 0, 0)), "dark"])
			var nb := t
			for i in nb:
				var z := (i - (nb - 1) / 2.0) * 0.07
				parts.append([_cyl(0.022, 0.55), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.5, 0, z)), "steel"])
			if t == 3:
				parts.append([_cyl(0.13, 0.25), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.4, 0, 0)), "dark"])
		"turret":
			_turret(parts, t, side)
		"flares":
			# малый кассетник → большой → два
			var boxes: Array = [0.0] if t < 3 else [-0.14, 0.14]
			for z3: float in boxes:
				var s := 0.75 if t == 1 else 1.0
				parts.append([_box(Vector3(0.9 * s, 0.14 * s, 0.22 * s)), Transform3D(Basis(), Vector3(0, 0, z3)), "olive"])
				for c in 4:
					parts.append([_cyl(0.035 * s, 0.02), Transform3D(Basis(), Vector3((c - 1.5) * 0.18 * s, 0.075 * s, z3)), "dark"])
		_:
			parts.append([_box(Vector3(1.0, 0.1, 0.12)), Transform3D(), "steel"])
	var am := ArrayMesh.new()
	# по поверхности на материал: светлый металл, тёмный металл, оливковый, красная полоса
	for mname in ["steel", "dark", "olive", "band", "white", "hull", "glass"]:
		var s2 := SurfaceTool.new()
		s2.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any := false
		for p in parts:
			if p[2] != mname:
				continue
			s2.append_from(p[0], 0, p[1])
			any = true
		if any:
			s2.commit(am)
			am.surface_set_material(am.get_surface_count() - 1, _mat(mname))
	_cache[key] = am
	return am


## Точка вылета снаряда в координатах модели (длина 1): для ракет и бомб — центр, для стволов — дульный срез
static func muzzle(weapon: String, cls := "", side := "", t := 0) -> Vector3:
	if weapon == "turret" and TURRET_MODELS.has(cls):
		var spec: Dictionary = TURRET_MODELS[cls]
		if t > 0 and spec.has("muzzle_t") and not (side == "tail" and spec.has("tail")):   # S9-04: срез по ступени
			return (spec["muzzle_t"][clampi(t, 1, 3) - 1] as Vector3) * float(spec["s"])
		return (spec.get("muzzle_tail" if side == "tail" and spec.has("tail") else "muzzle") as Vector3) * float(spec["s"])
	match weapon:
		"gunpod":
			return Vector3(0.78, 0, 0)
		"turret":
			return Vector3(0.72, 0.05, 0) * TURRET_K
		"rockets":
			return Vector3(0.5, 0, 0)
		"aam":
			return Vector3(0.5, 0, 0)
	return Vector3.ZERO


# ---------- турели ----------
# Стволы по +X (турель повёрнута стволами назад — yaw из mounts), срез у x = 0.72 до масштаба TURRET_K;
# основание верхней/нижней — на y = 0 (поверхность фюзеляжа); у кормовой начало координат — конец фюзеляжа.
# Ступени: 1 — спарка лёгких пушек, 2 — спарка тяжёлых с дульными тормозами, 3 — то же + прицел-радар.
const TURRET_K := 0.8


static func _turret(parts: Array, t: int, side: String) -> void:
	var st := turret_style
	var n0 := parts.size()
	if side == "tail":
		# корма: фюзеляж заканчивается установкой — остеклённой кабиной стрелка или металлическим конусом
		if st == 2:
			_tail_remote(parts, t)
		else:
			_tail_cabin(parts, t)
	elif st == 1:
		_dome(parts, t)
	else:
		_barbette(parts, t)
	for i in range(n0, parts.size()):
		parts[i][1] = Transform3D(Basis.from_scale(Vector3.ONE * TURRET_K)) * (parts[i][1] as Transform3D)


## Остеклённый колпак стрелка на погоне: стрелок под стеклом, пушки — из прорези спереди
static func _dome(parts: Array, t: int) -> void:
	parts.append([_cyl(0.22, 0.05), Transform3D(Basis(), Vector3(0, 0.02, 0)), "hull"])
	parts.append([_hemi(0.19), Transform3D(Basis().scaled(Vector3(1.15, 0.85, 1.0)), Vector3(0, 0.045, 0)), "glass"])
	parts.append([_torus(0.185, 0.2), Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3(1.15, 1.0, 0.85)), Vector3(0, 0.045, 0)), "hull"])
	parts.append([_cyl(0.18, 0.016), Transform3D(Basis(), Vector3(0, 0.11, 0)), "hull"])
	parts.append([_box(Vector3(0.12, 0.07, 0.16)), Transform3D(Basis(), Vector3(0.2, 0.06, 0)), "dark"])
	_barrels(parts, t, 0.24, 0.06, 0.06)
	if t == 3:
		parts.append([_sphere(0.05), Transform3D(Basis().scaled(Vector3(1.6, 0.8, 1.0)), Vector3(-0.05, 0.03, 0.2)), "hull"])


## Дистанционная башня: низкий обтекатель цвета обшивки, пушки из подвижной маски; стрелок — у прицела в кабине
static func _barbette(parts: Array, t: int) -> void:
	parts.append([_sphere(0.22), Transform3D(Basis().scaled(Vector3(1.45, 0.4, 1.0)), Vector3(-0.02, 0.0, 0)), "hull"])
	parts.append([_cyl(0.23, 0.03), Transform3D(Basis(), Vector3(-0.02, 0.0, 0)), "dark"])   # погон
	parts.append([_box(Vector3(0.09, 0.08, 0.2)), Transform3D(Basis(), Vector3(0.3, 0.04, 0)), "dark"])
	_barrels(parts, t, 0.33, 0.04, 0.07)
	if t == 3:
		parts.append([_sphere(0.05), Transform3D(Basis().scaled(Vector3(1.6, 0.8, 1.0)), Vector3(-0.05, 0.03, 0.2)), "hull"])


## Кормовая кабина стрелка: остеклённый «фонарь» — продолжение фюзеляжа, спарка под ним
static func _tail_cabin(parts: Array, t: int) -> void:
	parts.append([_cyl(0.13, 0.32), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-0.06, 0, 0)), "hull"])
	parts.append([_cyl(0.135, 0.2), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.07, 0, 0)), "glass"])
	parts.append([_hemi(0.135), Transform3D(Basis(Vector3.BACK, -PI / 2.0).scaled(Vector3(1.0, 0.9, 1.0)), Vector3(0.17, 0, 0)), "glass"])
	for xr: float in [0.0, 0.1, 0.17]:
		parts.append([_torus(0.13, 0.145), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(xr, 0, 0)), "hull"])
	parts.append([_sphere(0.09), Transform3D(Basis().scaled(Vector3(1.2, 0.8, 1.0)), Vector3(0.22, -0.13, 0)), "dark"])
	_barrels(parts, t, 0.26, -0.13, 0.07)
	if t == 3:
		parts.append([_sphere(0.05), Transform3D(Basis().scaled(Vector3(1.6, 0.8, 1.0)), Vector3(0.0, 0.14, 0)), "hull"])


## Кормовая дистанционная установка: металлический конус, сверху маленькое окно прицела
static func _tail_remote(parts: Array, t: int) -> void:
	parts.append([_cyl(0.12, 0.3), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-0.05, 0, 0)), "hull"])
	parts.append([_cone(0.12, 0.18), Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(0.19, 0, 0)), "hull"])
	parts.append([_hemi(0.05), Transform3D(Basis(), Vector3(-0.08, 0.11, 0)), "glass"])
	parts.append([_box(Vector3(0.1, 0.1, 0.16)), Transform3D(Basis(), Vector3(0.24, -0.02, 0)), "dark"])
	_barrels(parts, t, 0.28, -0.02, 0.06)
	if t == 3:
		parts.append([_sphere(0.05), Transform3D(Basis().scaled(Vector3(1.6, 0.8, 1.0)), Vector3(0.0, 0.12, 0.06)), "hull"])


## Спарка пушек от x0 до среза 0.72
static func _barrels(parts: Array, t: int, x0: float, y: float, gap: float) -> void:
	var r := 0.014 if t == 1 else 0.019
	var ln := 0.72 - x0
	for i in 2:
		var z := (i - 0.5) * gap
		parts.append([_cyl(r, ln), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(x0 + ln * 0.5, y, z)), "steel"])
		parts.append([_cyl(r * 1.8, ln * 0.3), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(x0 + ln * 0.15, y, z)), "dark"])
		if t >= 2:
			parts.append([_cyl(r * 1.6, 0.05), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.695, y, z)), "dark"])


# ---------- формы ----------

static func _hemi(r: float) -> SphereMesh:
	var s := _sphere(r)
	s.is_hemisphere = true
	s.height = r
	s.radial_segments = 20
	s.rings = 8
	return s


static func _torus(ri: float, ro: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = ri
	t.outer_radius = ro
	t.rings = 24
	t.ring_segments = 4
	return t


static func _missile(parts: Array, at: Vector3, length: float, r: float) -> void:
	var body := length * 0.78
	parts.append([_cyl(r, body), Transform3D(Basis(Vector3.BACK, PI / 2.0), at + Vector3(-0.05, 0, 0)), "white"])
	parts.append([_cone(r, length * 0.16), Transform3D(Basis(Vector3.BACK, -PI / 2.0), at + Vector3(body * 0.5 - 0.05 + length * 0.08, 0, 0)), "white"])
	parts.append([_cyl(r * 1.02, length * 0.05), Transform3D(Basis(Vector3.BACK, PI / 2.0), at + Vector3(body * 0.3, 0, 0)), "band"])
	for a in 4:
		parts.append([_box(Vector3(0.12, 0.008, r * 4.0)), Transform3D(Basis(Vector3.RIGHT, a * PI / 4.0 + PI / 4.0), at + Vector3(-body * 0.5 + 0.02, 0, 0)), "steel"])


static func _pod(parts: Array, at: Vector3, length: float, r: float, holes: int) -> void:
	parts.append([_cyl(r, length * 0.82), Transform3D(Basis(Vector3.BACK, PI / 2.0), at), "olive"])
	parts.append([_cone(r, length * 0.1), Transform3D(Basis(Vector3.BACK, PI / 2.0), at + Vector3(-length * 0.46, 0, 0)), "olive"])
	# дульные отверстия на переднем торце
	for i in holes:
		var a := TAU * i / holes
		var rr := r * (0.55 if i % 2 == 0 or holes < 10 else 0.25)
		parts.append([_cyl(r * 0.16, 0.02), Transform3D(Basis(Vector3.BACK, PI / 2.0), at + Vector3(length * 0.41, sin(a) * rr, cos(a) * rr)), "dark"])


static func _bomb(parts: Array, at: Vector3) -> void:
	parts.append([_sphere(0.1), Transform3D(Basis().scaled(Vector3(3.2, 1, 1)), at), "olive"])
	for a in 4:
		parts.append([_box(Vector3(0.12, 0.008, 0.16)), Transform3D(Basis(Vector3.RIGHT, a * PI / 2.0), at + Vector3(-0.33, 0, 0)), "dark"])


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	return c


static func _cone(r: float, h: float) -> CylinderMesh:
	var c := _cyl(r, h)
	c.top_radius = 0.0
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


static func _mat(n: String) -> StandardMaterial3D:
	if _mats.has(n):
		return _mats[n]
	var m := StandardMaterial3D.new()
	match n:
		"steel":
			m.albedo_color = Color(0.62, 0.64, 0.66)
			m.metallic = 0.6
			m.roughness = 0.4
		"dark":
			m.albedo_color = Color(0.16, 0.17, 0.18)
			m.metallic = 0.4
			m.roughness = 0.55
		"olive":
			m.albedo_color = Color(0.4, 0.42, 0.33)
			m.roughness = 0.7
		"band":
			m.albedo_color = Color(0.75, 0.2, 0.15)
			m.roughness = 0.6
		"white":
			m.albedo_color = Color(0.88, 0.89, 0.9)
			m.roughness = 0.45
		"hull":   # окраска пилонов: нейтральный серый, не спорит с окраской самолёта
			# S9-03: матовая краска (было metallic 0,55 / roughness 0,45 — в ангаре пилон отсвечивал голубым)
			m.albedo_color = Color(0.42, 0.43, 0.43)
			m.metallic = 0.1
			m.roughness = 0.86
		"glass":  # остекление: тёмное, с бликом
			m.albedo_color = Color(0.4, 0.55, 0.62, 0.45)
			m.metallic = 0.85
			m.roughness = 0.06
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[n] = m
	return m


## 3.4-t1 (п. 37): точка вылета снаряда в мире (2D) для узла si группы g самолёта игрока —
## ракета с её пилона, очередь — из ствола контейнера, турель — из своей башни, повёрнутой на aim.
## Совпадает с тем, где 3D-модуль стоит на самолёте (Render3D._sync_weapons).
static func muzzle_world(p: Player, g: Hardpoint, si: int, aim := NAN) -> Vector2:
	var gi := p.groups.find(g)
	var tex := PlaneArt.plane_tex(p.cls_id, p.plane_lvl)
	var tex1 := PlaneArt.plane_tex(p.cls_id, 1)
	if gi < 0 or tex == null or tex1 == null:
		return p.global_position
	var pts := mounts(p.cls_id, p.plane_lvl, gi, g)
	if pts.is_empty():
		return p.global_position
	var pt: Vector2 = (pts[si % pts.size()] as Dictionary)["p"]
	var side: String = (pts[si % pts.size()] as Dictionary)["side"]
	var k := Tuning.g("plane_len") * p.size / float(tex1.get_width())   # пикселей мира на пиксель картинки
	var len_px: float = PlaneArt.WEAPON_FRAC.get(g.weapon, 0.25) * Tuning.g("plane_len") / k
	var mz := muzzle(g.weapon, p.cls_id, side, tier(g.level, g.evo)) * len_px
	var local := pt + Vector2(mz.x, mz.z)
	if not is_nan(aim):   # турель: ствол смотрит на цель
		local = pt + Vector2(mz.x, 0.0).rotated(aim - p.heading)
	return p.global_position + (local * k).rotated(p.heading)



## Точка турели сверху на крыле (пиксели картинки): по размаху — между мотогондолами
## (WING_TURRET_Z доли полуразмаха), по хорде — середина крыла на этой линии. side: -1 левое, 1 правое
## Тест 3.5-s3 (Kanta): «Кит 1» — посередине между двигателями (просвет между гондолами на 0,62–0,68),
## «Кит 2» — ближе к середине консоли
const WING_TURRET_Z := {"bomber_1": 0.65, "bomber_2": 0.62}
static var _wing_pts := {}


static func wing_point(cls_id: String, lvl: int, side: float, zf_override := -1.0) -> Vector2:
	var key := "%s_%d" % [cls_id, lvl]
	var ck := key if zf_override < 0.0 else "%s_%.2f" % [key, zf_override]
	if not _wing_pts.has(ck):
		var t := PlaneArt.plane_tex(cls_id, lvl)
		var s := PlaneArt.shape_info(cls_id, lvl)
		var res := Vector2.ZERO
		if t != null and not s.is_empty():
			var img := t.get_image()
			if img.is_compressed():
				img.decompress()
			var w := img.get_width()
			var h := img.get_height()
			var zf: float = WING_TURRET_Z.get(key, 0.35) if zf_override < 0.0 else zf_override
			var row := 0
			var best0 := 0
			var best1 := -1
			# у законцовки строка может пройти мимо крыла — сдвигаемся к оси, пока не найдём хорду
			while best1 - best0 < 3 and zf > 0.05:
				row = int(h / 2.0 + float(s["half"]) * zf)
				# самый длинный непрерывный отрезок по строке — хорда крыла (без мотогондол спереди)
				best0 = 0
				best1 = -1
				var run0 := -1
				for x in w + 1:
					var on := x < w and img.get_pixel(x, clampi(row, 0, h - 1)).a > 0.4
					if on and run0 < 0:
						run0 = x
					elif not on and run0 >= 0:
						# у законцовки (zf_override > 0.8) — отрезок ближе всего к линии крыла, а не самый длинный:
						# дальше по строке бывают стабилизаторы
						var better := x - run0 > best1 - best0
						if zf_override > 0.8 and best1 >= 0:
							var wx := float(s["wing_x"]) + w / 2.0
							better = absf((run0 + x) * 0.5 - wx) < absf((best0 + best1) * 0.5 - wx)
						if better:
							best0 = run0
							best1 = x
						run0 = -1
				zf -= 0.02
			res = Vector2((best0 + best1) / 2.0 - w / 2.0, row - h / 2.0)
		_wing_pts[ck] = res
	var r: Vector2 = _wing_pts[ck]
	return Vector2(r.x, absf(r.y) * signf(side))


## Точки крепления оружия (пиксели картинки самолёта, центр картинки, нос по +X) и сторона:
##   "under" — под крылом на пилоне (НАР, ракеты, бомбы, контейнеры — как на настоящих самолётах);
##   встроенные турели — как у реальных бомбардировщиков и штурмовиков:
##   "tail" — кормовая установка в хвосте фюзеляжа (стволы назад), "top" — верхняя за кабиной,
##   "bottom" — нижняя под фюзеляжем. yaw — куда смотрят стволы без цели (0 — вперёд, PI — назад).
const KIT_TOP_TURRET := 0.4   # верхняя турель «Кита»: доля длины от носа


static func mounts(cls_id: String, lvl: int, gi: int, g: Hardpoint) -> Array:
	var out: Array = []
	var bay_grp := g.weapon == "bombs" and g.name.begins_with("Бомбоотсек") and has_bay(cls_id, lvl)
	# тест 3.5-s5 (п. 3): «Бабушкин ковёр» в бомбоотсеке — кассета внутри, на месте обычных бомб
	# (по центру их точек), видна при открытых створках; бомбы сыплются из люка
	if g.evo and bay_grp and ResourceLoader.exists(CARPET_BAY_GLB):
		var bp := PlaneArt.slot_points(cls_id, lvl, gi, g)
		if not bp.is_empty():
			var c := Vector2.ZERO
			for q: Vector2 in bp:
				c += q
			out.append({"p": c / bp.size(), "side": "bay", "yaw": 0.0, "t": CARPET_BAY_T})
			return out
	# Т-6: «Салют» — одна пусковая на спине за кабиной, «Бабушкин ковёр» — одна планка под фюзеляжем
	if g.evo and g.weapon in ["flares", "bombs"] and ResourceLoader.exists(EVO_GLB % g.weapon):
		var sh := PlaneArt.shape_info(cls_id, lvl)
		if not sh.is_empty():
			var top := g.weapon == "flares"
			out.append({"p": Vector2(float(sh["nose"]) - float(sh["len"]) * (0.55 if top else 0.5), 0.0),
				"side": "top" if top else "belly", "yaw": 0.0})
			return out
	# Т-5: ловушки встроены в корпус, а не на пилоне: ступень 1 — две кассеты на спине у хвоста,
	# 2 — крупнее, плюс у корня крыла, 3 — плюс контейнеры на законцовках. «t» — какую модель ставить
	if g.weapon == "flares" and not g.evo:
		var fs := PlaneArt.shape_info(cls_id, lvl)
		if not fs.is_empty():
			var ft := tier(g.level)
			var fz: float = maxf(float(fs["fus"]) * 0.55, 3.0)
			for sd in [-1.0, 1.0]:
				out.append({"p": Vector2(float(fs["nose"]) - float(fs["len"]) * 0.68, fz * sd), "side": "top", "yaw": 0.0, "t": mini(ft, 2)})
			if ft >= 2:
				for sd in [-1.0, 1.0]:
					out.append({"p": wing_point(cls_id, lvl, sd, 0.2), "side": "wing", "yaw": 0.0, "t": 2})
			if ft >= 3:
				for sd in [-1.0, 1.0]:
					out.append({"p": wing_point(cls_id, lvl, sd, 0.96), "side": "tip", "yaw": 0.0, "t": 3})
			return out
	if not g.builtin:
		# Т-5: у «Кита» бомбы — в бомбоотсеке под створками (render3d / hangar3d открывают их), без пилона
		for pt: Vector2 in PlaneArt.slot_points(cls_id, lvl, gi, g):
			var mt := {"p": pt, "side": "bay" if bay_grp else "under", "yaw": 0.0}
			if g.weapon == "bombs":   # тест 3.5-s8: калибр бомбы — по уровню (1–5), а не по ступени вида
				mt["t"] = bomb_t(g.level)
			out.append(mt)
		return out
	var s := PlaneArt.shape_info(cls_id, lvl)
	if s.is_empty():
		return out
	var L: float = s["len"]
	var tail: float = s["tail"]
	var nose: float = s["nose"]
	var order: Array
	if cls_id == "bomber":
		# тест 3.5-s7 (Kanta): турели «Кита» только на корпусе — кормовая под килем и верхняя на спине фюзеляжа
		order = [["tail", tail + L * 0.035, PI, 0.0], ["top", nose - L * KIT_TOP_TURRET, PI, 0.0]]
	else:
		# штурмовик: стрелок за кабиной (верхняя; тест 3.5-s3 — на фюзеляже за фонарём, не на нём), вторая — нижняя
		order = [["top", nose - L * 0.5, PI, 0.0], ["bottom", nose - L * 0.45, PI, 0.0], ["tail", tail + L * 0.035, PI, 0.0]]
	for i in g.slots:
		var o: Array = order[i % order.size()]
		out.append({"p": Vector2(o[1], o[3]), "side": o[0], "yaw": o[2]})
	return out
