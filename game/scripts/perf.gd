class_name Perf
extends Node
## Замер времени кадра по системам (флаг --perf, только для разработки). Узлы-метки с разным
## process_priority ставят отметки времени между группами систем; Render3D дополнительно меряет свои
## подшаги через Perf.mark(). Раз в 10 с печатает среднее по кадру, мс, и счётчики сцены.

static var on := false
static var _acc := {}          # имя -> сумма мкс за окно
static var _t := 0
static var _frames := 0
static var _win := 0.0

const GROUPS := [["spawner", 10], ["enemies", 20], ["projectiles", 30], ["fx", 40], ["pickups", 50],
	["hud", 60], ["render3d", 70], ["boom3d", 80]]

var _probes: Array[Node] = []
var _prev_us := 0
var _ft_max := 0.0
var _spikes := 0
var _win_len := 10.0
var _last := 0


static func mark(name: String) -> void:
	if not on:
		return
	var now := Time.get_ticks_usec()
	_acc[name] = int(_acc.get(name, 0)) + now - _t
	_t = now


## Подшаг внутри системы (не сдвигает метку групп): t0 — прошлое значение, вернёт новое
static func sub(name: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	_acc[name] = int(_acc.get(name, 0)) + now - t0
	return now


## Наибольшее значение за окно (мкс), печатается в мс как «имя=…»
static func peak(name: String, us: int) -> void:
	_peaks[name] = maxi(int(_peaks.get(name, 0)), us)


static var _peaks := {}


static func begin() -> void:
	if on:
		_t = Time.get_ticks_usec()


## Приоритет обработки для системы (0 — как было)
static func prio(group: String) -> int:
	if not on:
		return 0
	for g in GROUPS:
		if g[0] == group:
			return int(g[1])
	return 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perfwin="):
			_win_len = float(a.substr(10))
	# метка перед каждой группой и в самом конце; всё до первой группы — «main и прочее»
	var names := ["other"]
	for g in GROUPS:
		names.append(g[0])
	var pr := [-100000, 5, 15, 25, 35, 45, 55, 65, 75, 85]
	for i in pr.size():
		var n := _Probe.new()
		n.process_priority = pr[i]
		n.label = "" if i == 0 else String(names[i - 1])
		n.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(n)
		_probes.append(n)
	_last = Time.get_ticks_usec()
	get_tree().node_added.connect(_on_added)
	for n in get_tree().root.find_children("*", "", true, false):
		_on_added(n)


## Системы — в свою группу приоритета (порядок обработки внутри группы не меняется)
func _on_added(n: Node) -> void:
	var g := ""
	if n is Enemy:
		g = "enemies"
	elif n is Spawner:
		g = "spawner"
	elif n is Projectiles:
		g = "projectiles"
	elif n is Fx or (n.get_parent() is Fx):
		g = "fx"
	elif n is Pickups:
		g = "pickups"
	elif n is Hud:
		g = "hud"
	elif n is Render3D:
		g = "render3d"
	elif n is Boom3D:
		g = "boom3d"
	if g != "":
		n.process_priority = prio(g)


func _process(delta: float) -> void:
	# этот узел — с приоритетом по умолчанию 0, отдельно не мерим; печать раз в 10 с
	_win += delta / maxf(Engine.time_scale, 0.001)
	_frames += 1
	var now := Time.get_ticks_usec()
	if _prev_us > 0:
		var ft := (now - _prev_us) / 1000.0
		_ft_max = maxf(_ft_max, ft)
		if ft > 33.0:
			_spikes += 1
	_prev_us = now
	if _win < _win_len:
		return
	var m := Main.I
	var line := "PERF t=%d %d кадров макс=%.0fмс рывков>33мс=%d" % [int(m.run_time) if m != null else 0, _frames, _ft_max, _spikes]
	_ft_max = 0.0
	_spikes = 0
	line += " fps=%d" % Engine.get_frames_per_second()
	var keys := _acc.keys()
	keys.sort_custom(func(a, b): return int(_acc[a]) > int(_acc[b]))
	var tot := 0.0
	for k in keys:
		var ms := float(_acc[k]) / 1000.0 / _frames
		tot += ms if not "." in String(k) else 0.0
		line += " %s=%.2f" % [k, ms]
	for k in _peaks:
		line += " %s=%.1fмс" % [k, _peaks[k] / 1000.0]
	_peaks.clear()
	line += " | сумма=%.2f мс процесс=%.2f" % [tot, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]
	line += " | врагов=%d пуль=%d узлов=%d draws=%d tris=%dk" % [
		m.get_tree().get_nodes_in_group("enemies").size() if m != null else 0,
		m.projectiles.get_child_count() if m != null and m.projectiles != null else 0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)]
	if Boom3D.I != null:
		var pc := []
		for a in Boom3D.I._parts:
			pc.append((a as Array).size())
		line += " частицы=%s" % str(pc)
	print(line)
	print(_vp_report())
	print(_tri_report())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perfshot=") and m != null:
			m.get_viewport().get_texture().get_image().save_png("user://perf_%s_%04d.png" % [a.substr(11), int(m.run_time)])
	_acc.clear()
	_frames = 0
	_win = 0.0


## Вызовы отрисовки по вьюпортам: основной и слой боя (наклонная камера), видимые и тени
func _vp_report() -> String:
	var out := "VP"
	var vps: Array = [get_viewport()]
	if Render3D.I != null and Render3D.I._combat_vp != null:
		vps.append(Render3D.I._combat_vp)
	if Render3D.I != null and Render3D.I._psh_vp != null:
		vps.append(Render3D.I._psh_vp)
	for vp: Viewport in vps:
		var rid := vp.get_viewport_rid()
		out += " %s: вид=%d/%dk тени=%d/%dk кадр=%.1fмс" % [vp.name.left(10),
			RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1000,
			RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1000,
			RenderingServer.viewport_get_measured_render_time_cpu(rid)]
	out += " | 2D: %d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return out


static var _mesh_tris := {}


static func mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var k := mesh.get_rid()
	if _mesh_tris.has(k):
		return _mesh_tris[k]
	var t := 0
	for i in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(i)
		var idx = a[Mesh.ARRAY_INDEX]
		t += (idx.size() if idx != null and idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	_mesh_tris[k] = t
	return t


## Треугольники и объекты в кадре камеры по видам (без видеокарты: по дереву сцены и рамкам видимости)
func _tri_report() -> String:
	var R := Render3D.I
	if R == null or R.cam == null:
		return "TRIS нет 3D"
	var planes := R.cam.get_frustum()
	var by := {}
	var cnt := {}
	for n in R.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var aabb := gi.global_transform * gi.get_aabb()
		var inside := true
		for pl: Plane in planes:
			if pl.distance_to(aabb.get_support(-pl.normal)) > 0.0:
				inside = false
				break
		if not inside:
			continue
		var t := 0
		var draws := 1
		if gi is MeshInstance3D:
			t = mesh_tris((gi as MeshInstance3D).mesh)
			draws = maxi((gi as MeshInstance3D).mesh.get_surface_count(), 1) if (gi as MeshInstance3D).mesh != null else 0
		elif gi is MultiMeshInstance3D:
			var mm := (gi as MultiMeshInstance3D).multimesh
			if mm != null:
				var vis := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
				t = mesh_tris(mm.mesh) * vis
				draws = mm.mesh.get_surface_count() if mm.mesh != null else 0
		var key := _cat(gi, R)
		by[key] = int(by.get(key, 0)) + t
		cnt[key] = int(cnt.get(key, 0)) + draws
	var keys := by.keys()
	keys.sort_custom(func(a, b): return int(by[a]) > int(by[b]))
	var out := "TRIS"
	var tot := 0
	var dr := 0
	for k in keys:
		tot += int(by[k])
		dr += int(cnt[k])
		out += " %s=%dk/%d" % [k, int(by[k]) / 1000, cnt[k]]
	return out + " | всего %dk треуг., ~%d вызовов (без теней), gfx=%d наклон=%d" % [tot / 1000, dr, Settings.gfx, int(Tuning.g("cam_tilt"))]


func _cat(n: Node, R: Render3D) -> String:
	if _roots.is_empty() or Engine.get_process_frames() != _roots_f:
		_roots.clear()
		_roots_f = Engine.get_process_frames()
		for id in R._units:
			var u: Dictionary = R._units[id]
			_roots[u["node"]] = "%s:%s" % [u["kind"], (u["tex"] as Texture2D).resource_path.get_file().get_basename()]
	var c := n
	while c != null and c != R:
		if _roots.has(c):
			return _roots[c] + ("" if n is MeshInstance3D or n is MultiMeshInstance3D else "+")
		if c is Terrain3D:
			if n is MultiMeshInstance3D:
				var mm := (n as MultiMeshInstance3D).multimesh
				return "props:" + String(n.name).left(12)
			return "terrain:" + n.get_class()
		if c.get_script() != null and c.get_script().get_global_name() != "":
			return String(c.get_script().get_global_name())
		c = c.get_parent()
	var mesh_n := ""
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		mesh_n = (n as MeshInstance3D).mesh.get_class()
		var mo := (n as MeshInstance3D).material_override
		if mo is ShaderMaterial and (mo as ShaderMaterial).shader != null:
			mesh_n += "/" + str((mo as ShaderMaterial).shader.get_instance_id() % 1000)
	return "r3d:" + n.get_class() + ":" + mesh_n + ":" + str(n.get_parent().name).left(10)


var _roots := {}
var _roots_f := -1


class _Probe:
	extends Node
	var label := ""

	func _process(_d: float) -> void:
		if label == "":
			Perf.begin()
		else:
			Perf.mark(label)
