class_name LeviathanParts
extends RefCounted
## «Левиафан» (Б-3, Архипелаг): части на корпусе — 2 башни главного калибра, 2 пусковые, РЛС и 6 ЗСУ
## (модели — tools/model_lab/b2_leviathan.py, места — models/biome2/leviathan_sockets.json). Только вид:
## урон, фазы и снаряды считает Warship. Здесь — наведение башен и ЗСУ на игрока, вращение антенны РЛС,
## пуск ракет (крышки контейнеров открываются при захвате цели, ракета с факелом и дымом выходит из контейнера
## и уходит туда, где её дальше ведёт Projectiles; крышки закрываются после пуска), разрушение частей по ходу боя
## (взрыв, разбитая модель, дым и огонь над ней). Замечания Kanta 19.10.

const SOCKETS := "res://models/biome2/leviathan_sockets.json"
const MODEL := {"main_turret": "e_lev_turret", "launcher": "e_lev_launcher", "radar": "e_lev_radar", "zsu": "e_lev_zsu"}
## Части выбиваются по ходу боя, по доле прочности корабля (номер гнезда → доля, ниже которой часть разбита).
## Порядок гнёзд — как в sockets.json: 0–1 башни, 2–3 пусковые, 4 РЛС, 5–10 ЗСУ. Сначала ЗСУ по бортам
## (фаза 1), РЛС и пусковые — во второй половине, башни главного калибра — к концу (фаза 3 — их залпы).
const BREAK_AT := [0.12, 0.04, 0.42, 0.3, 0.55, 0.93, 0.86, 0.79, 0.72, 0.62, 0.22]
const LID_OPEN := 1.9           # угол открытой крышки, рад
const LID_SPEED := 4.5          # раскрытие, рад/с
const EMERGE := 0.38            # сколько летит наша 3D-ракета от контейнера до ракеты Projectiles, с
const MSL_M := 6.5              # длина ракеты в контейнере, м

static var _sock: Dictionary = {}
static var _scenes := {}


static func _data() -> Dictionary:
	if _sock.is_empty() and FileAccess.file_exists(SOCKETS):
		var j = JSON.parse_string(FileAccess.get_file_as_string(SOCKETS))
		if j is Dictionary:
			_sock = j
	return _sock


static func _scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		var p := "res://models/battle/fh_battle_%s.glb" % name
		_scenes[name] = load(p) if ResourceLoader.exists(p) else null
	return _scenes[name]


## Повесить части на модель корабля (inst — сцена GLB корпуса, длина 1). Старые (из пула моделей) — убрать.
static func attach(inst: Node3D, owner_id: int) -> Dictionary:
	var old := inst.get_node_or_null("LevParts")
	if old != null:
		old.free()
	var d := _data()
	if d.is_empty():
		return {}
	var holder := Node3D.new()
	holder.name = "LevParts"
	inst.add_child(holder)
	var len_m := float(d.get("length_m", 250.0))
	var part_m: Dictionary = d.get("part_m", {})
	var parts: Array = []
	for s: Dictionary in d["sockets"]:
		var kind: String = s["kind"]
		var n: Array = s["norm"]
		var slot := Node3D.new()
		slot.position = Vector3(float(n[0]), float(n[1]), float(n[2]))
		slot.rotation.y = deg_to_rad(float(s.get("yaw_deg", 0.0)))
		slot.scale = Vector3.ONE * float(part_m.get(kind, 10.0)) / len_m
		holder.add_child(slot)
		var p := {"kind": kind, "slot": slot, "broken": false, "yaw": 0.0, "fx": 0.0, "lids": [], "open": 0.0, "hold": 0.0}
		_set_model(p, false)
		parts.append(p)
	return {"owner": owner_id, "parts": parts, "holder": holder, "launch_n": -1, "salvo_n": -1, "msl": [], "cell": 0}


static func _set_model(p: Dictionary, broken: bool) -> void:
	var slot: Node3D = p["slot"]
	for c in slot.get_children():
		c.queue_free()
	var sc := _scene(String(MODEL[p["kind"]]) + ("_broken" if broken else ""))
	if sc == null:
		return
	var m: Node3D = sc.instantiate()
	slot.add_child(m)
	p["model"] = m
	p["broken"] = broken
	p["turret"] = m.find_child("turret", true, false)
	p["gun"] = m.find_child("guns", true, false) if p["kind"] == "main_turret" else m.find_child("gun", true, false)
	p["antenna"] = m.find_child("antenna", true, false)
	var lids: Array = []
	for i in 8:
		var l := m.find_child("lid_%d" % i, true, false) as Node3D
		if l != null:
			lids.append({"n": l, "i": i, "a": 0.0, "want": 0.0, "t": 0.0, "side": -1.0 if l.position.z < 0.0 else 1.0})
	p["lids"] = lids
	if p["turret"] != null and not broken:
		(p["turret"] as Node3D).rotation.y = float(p["yaw"])


## Каждый кадр после _place корпуса. u — запись Render3D (node → сцена корпуса), ws — корабль.
static func update(u: Unit3D, ws: Warship, delta: float) -> void:
	var root: Node3D = u.node
	if root.get_child_count() == 0:
		return
	var inst := root.get_child(0) as Node3D
	var st: Dictionary = u.lev
	if st.is_empty() or int(st["owner"]) != ws.get_instance_id() or not is_instance_valid(st["holder"]):
		st = attach(inst, ws.get_instance_id())
		u.lev = st
		if st.is_empty():
			return
	var frac := ws.hp / maxf(ws.max_hp, 1.0)
	var pl := Main.I.player
	var target := Vector3.INF
	if pl != null and is_instance_valid(pl) and pl.hp > 0.0:
		target = Vector3(pl.global_position.x, 0.0, pl.global_position.y)
	var parts: Array = st["parts"]
	for i in parts.size():
		var p: Dictionary = parts[i]
		if not p["broken"] and i < BREAK_AT.size() and frac < float(BREAK_AT[i]):
			_break(p)
		if p["broken"]:
			_burn(p, delta)
		_aim(p, target, delta)
		if p["antenna"] != null and not p["broken"]:
			(p["antenna"] as Node3D).rotation.y += delta * 1.7
	_launchers(st, ws, delta)
	if int(st["salvo_n"]) != ws.fx_salvo:
		var first := int(st["salvo_n"]) < 0
		st["salvo_n"] = ws.fx_salvo
		if not first:
			for p: Dictionary in parts:
				if p["kind"] == "main_turret" and not p["broken"]:
					_muzzle(p)


## Залп главного калибра (кольцо снарядов Warship): вспышки у дульных срезов и клубы дыма
static func _muzzle(p: Dictionary) -> void:
	var g := p["gun"] as Node3D
	if g == null or not Boom3D.active():
		return
	var b := Boom3D.ensure()
	var s := _px_m(p) * 2.5
	for z in [-0.0635, 0.0635]:
		var at := g.global_transform * Vector3(0.6, 0.0, z)
		var fw := (g.global_transform.basis.x).normalized()
		b._flash(at, s * 2.6, 0.08, Color(1.0, 0.85, 0.55, 1.0))
		b._fire(at, fw * s * 14.0, s * 0.5, s * 1.2, 0.15, 1.0)
		for i in 3:
			b._smoke(at + fw * s * (0.5 + i), fw * s * randf_range(3.0, 6.0) + Boom3D._rdir() * s, s * 0.6, s * randf_range(2.0, 3.0),
				randf_range(1.5, 2.2), Color(0.55, 0.54, 0.52, 0.55), 0.0, 3.0, 2.0, 0.03 * i)


## Башни и ЗСУ — поворот к игроку (плавно), стволы чуть приподняты
static func _aim(p: Dictionary, target: Vector3, delta: float) -> void:
	var t := p["turret"] as Node3D
	if t == null or p["broken"] or target == Vector3.INF:
		return
	var slot: Node3D = p["slot"]
	var loc := slot.global_transform.affine_inverse() * target
	var want := atan2(-loc.z, loc.x)
	var lim := PI * 0.8 if p["kind"] == "main_turret" else PI * 0.9
	want = clampf(want, -lim, lim)
	var spd := deg_to_rad(28.0 if p["kind"] == "main_turret" else 90.0)
	p["yaw"] = rotate_toward(float(p["yaw"]), want, spd * delta)
	t.rotation.y = float(p["yaw"])
	var g := p["gun"] as Node3D
	if g != null:
		g.rotation.z = lerpf(g.rotation.z, deg_to_rad(12.0 if p["kind"] == "main_turret" else 24.0), delta * 2.0)


## Часть выбита: взрыв на месте, модель — разбитая
static func _break(p: Dictionary) -> void:
	var at: Vector3 = (p["slot"] as Node3D).global_position
	var s := _px_m(p) * (9.0 if p["kind"] == "main_turret" else 5.0)
	_set_model(p, true)
	if not Boom3D.active():
		return
	var b := Boom3D.ensure()
	b._flash(at + Vector3(0, s * 0.5, 0), s * 3.0, 0.12, Color(1.0, 0.9, 0.75, 1.0))
	b._core(at + Vector3(0, s * 0.3, 0), s * 0.5, s * 1.1, 0.3, 1.0, 0.8)
	for i in 6:
		var d := Boom3D._rdir(0.8)
		b._fire(at + d * s * 0.3, d * s * 2.0 + Vector3(0, s * 2.0, 0), s * 0.4, s * 0.9, randf_range(0.2, 0.4), 1.0, 8.0)
	for i in 8:
		var d2 := Boom3D._rdir(0.6)
		b._smoke(at + d2 * s * 0.4, d2 * s * 1.2 + Vector3(0, s * 1.5, 0), s * 0.6, s * randf_range(2.2, 3.2), randf_range(3.0, 4.5),
			Color(0.11, 0.105, 0.1, 0.7), 0.6, 5.0, 1.0, randf_range(0.0, 0.3))
	for i in 5:
		b._debris(at + Vector3(0, s * 0.4, 0), Boom3D._rdir(1.2) * randf_range(80.0, 160.0), s * randf_range(0.12, 0.25), Color(0.25, 0.25, 0.26), 1.0,
			"fire" if i < 2 else "smoke", false, 0.4)
	b._sparks(at + Vector3(0, s * 0.4, 0), 14, s * 9.0, 0.6, Color(1.0, 0.72, 0.3, 1.0), 0.6, 0.7)
	Main.I.sfx.play("explode_big", -8.0, 1.1, Vector2(at.x, at.z))


## Пикселей на метр у этой части (масштаб корабля на экране)
static func _px_m(p: Dictionary) -> float:
	var slot: Node3D = p["slot"]
	var d := _data()
	var part_m := float((d.get("part_m", {}) as Dictionary).get(p["kind"], 10.0))
	return slot.global_transform.basis.get_scale().x / maxf(part_m, 0.01)


## Разбитая часть горит и дымит: тёмный дым столбом (сносит ветром), языки огня у основания
static func _burn(p: Dictionary, delta: float) -> void:
	if not Boom3D.active():
		return
	var b := Boom3D.ensure()
	var big: bool = p["kind"] == "main_turret"
	var s := _px_m(p) * (4.0 if big else 2.4)
	var at: Vector3 = (p["slot"] as Node3D).global_position + Vector3(0, s * 0.6, 0)
	p["fx"] = float(p["fx"]) + delta * (9.0 if big else 6.0) * b._q
	while float(p["fx"]) >= 1.0:
		p["fx"] = float(p["fx"]) - 1.0
		var o := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * s * 0.5
		var gg := randf_range(0.08, 0.14)
		b._smoke(at + o, Vector3(0, s * randf_range(2.0, 3.0), 0), s * 0.6, s * randf_range(2.4, 3.6), randf_range(3.0, 4.5),
			Color(gg, gg * 0.95, gg * 0.9, 0.65), 0.35, 4.0, 0.5)
		if randf() < 0.45 and not b._lo:
			b._fire(at + o * 0.6, Vector3(0, s * randf_range(1.2, 2.0), 0), s * 0.3, s * 0.7, randf_range(0.2, 0.35), 0.8, 10.0)


# ---------- пусковые ----------

## Захват цели (красная линия) — открываются крышки контейнеров, из которых пойдёт залп; пуск (Warship.fx_launch)
## — из каждого открытого контейнера выходит ракета; крышки закрываются через 1,4 с после пуска.
static func _launchers(st: Dictionary, ws: Warship, delta: float) -> void:
	var parts: Array = st["parts"]
	var cells: Array = []    # [часть, крышка] — целые контейнеры
	for p: Dictionary in parts:
		if p["kind"] == "launcher":
			for l: Dictionary in p["lids"]:
				cells.append([p, l])
	if int(st["launch_n"]) < 0:
		st["launch_n"] = ws.fx_launch
	if ws._sam_lock > 0.0 and st.get("chosen", []).is_empty() and not cells.is_empty():
		var n := ws.fx_salvo_size()
		var ch: Array = []
		for k in n:
			# по очереди из обеих пусковых: следующий контейнер по кругу
			ch.append(cells[(int(st["cell"]) + k * 3) % cells.size()])
		st["cell"] = (int(st["cell"]) + 1) % maxi(cells.size(), 1)
		st["chosen"] = ch
		for c: Array in ch:
			(c[1] as Dictionary)["want"] = 1.0
	if ws.fx_launch != int(st["launch_n"]):
		st["launch_n"] = ws.fx_launch
		var ch2: Array = st.get("chosen", [])
		var ms: Array = Main.I.projectiles.missiles
		var k := 0
		for c: Array in ch2:
			var l: Dictionary = c[1]
			if not is_instance_valid(l["n"]):   # пусковую разбило во время захвата — крышки уже другие
				k += 1
				continue
			l["t"] = 1.4
			var real: Dictionary = {}
			for j in range(ms.size() - 1, -1, -1):   # ракеты этого залпа — последние в списке
				var m: Dictionary = ms[j]
				if m.get("lev_k", -1) == k:
					real = m
					break
			_emit_missile(st, c[0], l, real)
			k += 1
		st["chosen"] = []
	for c: Array in cells:
		var l: Dictionary = c[1]
		if float(l["t"]) > 0.0:
			l["t"] = float(l["t"]) - delta
			if float(l["t"]) <= 0.0:
				l["want"] = 0.0
		l["a"] = move_toward(float(l["a"]), float(l["want"]) * LID_OPEN, LID_SPEED * delta)
		(l["n"] as Node3D).rotation.x = float(l["a"]) * float(l["side"])
	_fly(st, delta)


## Ракета выходит из контейнера: вспышка и выброс дыма из колодца, дальше — наша 3D-ракета с факелом
static func _emit_missile(st: Dictionary, p: Dictionary, l: Dictionary, real: Dictionary) -> void:
	var lid: Node3D = l["n"]
	var slot: Node3D = p["slot"]
	# центр проёма: крышка лежит на проёме, шарнир (origin крышки) — у внешней кромки
	var cell := slot.global_transform * (lid.position + Vector3(0, -0.02, -0.0795 * float(l["side"])))
	var up := slot.global_transform.basis.y.normalized()
	var pxm := _px_m(p)
	var mi := MeshInstance3D.new()
	mi.mesh = WeaponModels.mesh("enemy_msl", 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	slot.add_child(mi)
	mi.global_position = cell
	(st["msl"] as Array).append({"mi": mi, "p0": cell, "up": up, "t": 0.0, "real": real, "pxm": pxm, "trail": 0.0})
	if real.size() > 0:
		real["lev_hold"] = EMERGE
	if Boom3D.active():
		var b := Boom3D.ensure()
		var s := pxm * 2.2
		b._flash(cell + up * s * 0.4, s * 2.4, 0.1, Color(1.0, 0.85, 0.6, 1.0))
		b._fire(cell, up * s * 6.0, s * 0.5, s * 1.0, 0.22, 1.0, 6.0)
		for i in 5:   # выброс газов из колодца и газоотвода — белый клуб у палубы
			var d := Boom3D._rdir(0.4)
			d.y = absf(d.y) * 0.4
			b._smoke(cell + d * s * 0.5, d * s * 4.0 + up * s * 1.5, s * 0.6, s * randf_range(1.8, 2.6), randf_range(1.2, 1.8),
				Color(0.82, 0.81, 0.79, 0.7), 0.0, 3.0, 2.0, 0.02 * i)


static func _fly(st: Dictionary, delta: float) -> void:
	var arr: Array = st["msl"]
	for i in range(arr.size() - 1, -1, -1):
		var m: Dictionary = arr[i]
		var mi: MeshInstance3D = m["mi"]
		m["t"] = float(m["t"]) + delta
		var k := clampf(float(m["t"]) / EMERGE, 0.0, 1.0)
		var real: Dictionary = m["real"]
		if real.size() > 0:
			real["lev_hold"] = maxf(0.0, EMERGE - float(m["t"]))
		if k >= 1.0 or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			arr.remove_at(i)
			continue
		var pxm: float = m["pxm"]
		var p0: Vector3 = m["p0"]
		var up: Vector3 = m["up"]
		var p1 := p0 + up * pxm * MSL_M * 2.2                     # выход из контейнера — вертикально
		var p2 := p1 + up * pxm * 4.0
		if real.size() > 0:
			var rp: Vector2 = real["p"]
			p2 = Vector3(rp.x, 0.0, rp.y)
		var e := k * k * (3.0 - 2.0 * k)
		var a := p0.lerp(p1, e)
		var b2 := p1.lerp(p2, e)
		var pos := a.lerp(b2, e)
		var dir := (b2 - a)
		if dir.length() < 0.001:
			dir = up
		dir = dir.normalized()
		var ln := lerpf(pxm * MSL_M, Render3D.ESHOT_LEN * float(Projectiles.MSL_SIZE.get(real.get("k", "sam"), 1.0)), e)
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		mi.global_transform = Transform3D(Basis(dir, side.cross(dir).normalized(), side).scaled(Vector3.ONE * ln), pos)
		if Boom3D.active():
			var bb := Boom3D.ensure()
			var tail := pos - dir * ln * 0.55
			m["trail"] = float(m["trail"]) + delta * 40.0
			while float(m["trail"]) >= 1.0:
				m["trail"] = float(m["trail"]) - 1.0
				bb._fire(tail, -dir * ln * 3.0, ln * 0.18, ln * 0.4, 0.12, 1.0)
				bb._smoke(tail - dir * ln * 0.3, -dir * ln * 1.5 + Boom3D._rdir() * ln * 0.3, ln * 0.2, ln * randf_range(0.6, 0.9),
					randf_range(0.8, 1.2), Color(0.86, 0.86, 0.85, 0.65), 0.0, 3.0, 2.0)
