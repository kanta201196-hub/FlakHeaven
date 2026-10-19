class_name VisualBench
extends RefCounted
## B-23: стенд скриншотов для сравнения картинки «до/после» (-- --visual).
## Фиксированное зерно, без врагов и интерфейса; 6 точек камеры → user://vis_*.png.
## В журнал — средняя яркость и доля пересвеченных пикселей (> 245) каждого кадра.

const SEED := 20261014
const WAIT := 0.6      # секунд реального времени на точку: камера и 3D успевают встать

var m: Main
var _i := -1
var _t := 0.0
var _phase := 0        # 0 — встать в точку, 1 — снять
var _points: Array = []


static func seed_world() -> void:
	seed(SEED)


var _suffix := ""


func _init(main: Main) -> void:
	m = main
	# --tilt=N (main.gd ставит cam_tilt) — файлы кадров vis_<имя>_tN.png
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tilt="):
			Tuning.set_param("cam_tilt", float(a.substr(7)))
			_suffix += "_t" + a.substr(7)
		if a == "--flatclouds":   # M-31: сравнение — прежние плоские облака (vis_<имя>_flat.png)
			Tuning.set_param("cloud3d", 0.0)
			_suffix += "_flat"
		if a.begins_with("--gfx="):   # T4-04: сравнение пресетов качества — vis_<имя>_gN.png
			_suffix += "_g" + a.substr(6)


func process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.01)
	if OS.get_cmdline_user_args().has("--hangarbench"):
		_hangar_bench()
		return
	if OS.get_cmdline_user_args().has("--menushot"):
		_menu_shot()
		return
	if m.state == "menu" and _i < 0 and _t > 1.0:
		var cls := "fighter"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--cls="):   # 3.5: кадры боя другим классом (3D-модели в бою)
				cls = a.substr(6)
				_suffix += "_" + cls
		m.select_class(cls)
		_t = 0.0
		return
	if m.state != "playing" or not is_instance_valid(m.player):
		return
	m.god_mode = true
	m.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	var cur: Dictionary = _points[_i] if _i >= 0 and _i < _points.size() else {}
	var keep: bool = cur.get("enemies", false) or cur.get("convoy", false)   # M-36: машины колонны — тоже враги
	for e in m.get_tree().get_nodes_in_group("enemies"):
		if not keep:
			(e as Node).queue_free()
	if m.hud != null:
		m.hud.visible = false
	if _i < 0:
		if _t < 1.0:
			return
		_points = _make_points()
		for a in OS.get_cmdline_user_args():   # --only=model_ground — только точки с этим началом имени
			if a.begins_with("--only="):
				var pre := a.get_slice("=", 1).split(",")   # несколько начал через запятую: --only=village,scene
				_points = _points.filter(func(q: Dictionary) -> bool: return Array(pre).any(func(x: String) -> bool: return String(q["name"]).begins_with(x)))
		_i = 0
		_t = 0.0
	if _i >= _points.size():
		print("VISUAL done")
		m.get_tree().quit()
		return
	var p: Dictionary = _points[_i]
	if p.get("ground", false):
		if not _g_spawned:
			_g_spawned = true
			var site := AASite.new()
			if p.has("site_off"):   # M-37: позиция ПВО рядом с колонной на дороге (камера остаётся на точке)
				var at: Vector2 = (p["pos"] as Vector2) + (p["site_off"] as Vector2)
				site.setup(at, 1.0)
				site.bunker.hp = 99999.0   # стенд: бункер не должен разбиться
				site.bunker.max_hp = 99999.0
				for g: GroundTarget in site.targets:   # раскладка та же, но ровно у дороги (без поиска дна долины)
					g.position += at - site.anchor
				site.anchor = at
				site.global_position = at
				site.process_mode = Node.PROCESS_MODE_DISABLED
			else:
				site.setup(m.player.global_position + Vector2(0, -120), 1.0)
				site.bunker.hp = 99999.0
				site.bunker.max_hp = 99999.0
				p["pos"] = site.global_position + Vector2(0, 160)
			m.world.add_child(site)
	elif p.get("tanker", false):
		if not _spawned:   # заправщик впереди игрока, штанга выдвинута и отклонена (логика стоит)
			_spawned = true
			var tk := Tanker.new()
			tk.heading = 0.0
			tk.position = (p["pos"] as Vector2) + Vector2(260, 0)
			tk.process_mode = Node.PROCESS_MODE_DISABLED
			tk.boom_len = 190.0
			tk.boom_angle = 0.25
			tk.docked = true
			m.world.add_child(tk)
	elif p.has("fortress"):
		if _fort == null:   # «Крепость» стоит перед игроком носом вправо, логика стоит; фаза — из точки
			_fort = Fortress.new()
			_fort.setup_fortress(5000.0)
			_fort.heading = -0.5
			_fort.position = (p["pos"] as Vector2) + Vector2(0, -40)
			_fort.process_mode = Node.PROCESS_MODE_DISABLED
			_fort.base_pos = _fort.position + Vector2.from_angle(_fort.heading) * 1400.0   # FB-01: маршрут к базе на кадре
			_fort._wp = _fort.base_pos
			m.world.add_child(_fort)
		_fort.hp = _fort.max_hp   # игрок стреляет: без своей логики «Крепость» не гасит вспышку попадания
		_fort._flash = 0.0
		var ph: int = p["fortress"]
		_fort.phase = ph
		_fort.hatches_open = ph >= 2
		_fort.hull_open = ph >= 3
		_fort.parts_down = {}
		for nm in (["turret_1", "turret_2", "turret_3", "turret_4"] if ph >= 2 else []) + (["engine_l", "engine_r"] if ph >= 3 else []):
			_fort.parts_down[nm] = true
	elif p.get("enemies", false) and (not _spawned or m.get_tree().get_nodes_in_group("enemies").is_empty()):   # смена класса в начале точки очищает мир
		_spawn_all_enemies(p["pos"])   # точка, а не игрок: в первый кадр игрок ещё не перенесён
	if p.get("convoy", false):
		if _convoy == null:
			_convoy = Convoy.new()
			_convoy.setup(p["pos"], Vector2.RIGHT, 1.0, 0.0, 0.0)
			m.world.add_child(_convoy)
			_convoy.process_mode = Node.PROCESS_MODE_DISABLED
		if _pt > 0.3 and not p.has("_done"):   # машины уже в мире — ставим подряд по дороге у точки и останавливаем
			p["_done"] = true
			var s0: float = _convoy._s_of(p["pos"])
			var at := s0
			for v: ConvoyVehicle in _convoy.vehicles:   # середина колонны — у точки
				at += (float(ConvoyVehicle.SPEC[v.role]["len"]) * Tuning.g("unit_scale") + ConvoyVehicle.GAP) * 0.5
			for v: ConvoyVehicle in _convoy.vehicles:
				v.process_mode = Node.PROCESS_MODE_DISABLED
				v.place(at)
				at -= float(ConvoyVehicle.SPEC[v.role]["len"]) * Tuning.g("unit_scale") + ConvoyVehicle.GAP
		for v: ConvoyVehicle in _convoy.vehicles:
			v.process_mode = Node.PROCESS_MODE_DISABLED
	_hold(p)
	if p.get("eweap", false):
		# время замедлено: в облаке кадр идёт ~1 с, а ракета пролетает экран за секунду — так след и трассеры плавные
		Engine.time_scale = 0.5
		_eweap(p)
		if _pt >= float(p["shot_t"]):
			Engine.time_scale = 1.0
			_save(p["name"])
			m.projectiles.missiles.clear()
			m.projectiles.ebullets.clear()
			_phase = 0
			_t = 0.0
			_pt = 0.0
			_ew_t = {}
			_i += 1
		return
	if _phase == 0 and _t > float(p.get("wait", WAIT)):
		if p.get("boom", false):
			var c: Vector2 = p["pos"]
			m.fx.explosion(c + Vector2(220, -90), 34.0)
			m.fx.explosion(c + Vector2(-260, 140), 22.0)
			m.fx.explosion(c + Vector2(60, 230), 16.0, false)
		if p.has("booms"):   # M-39: взрывы всех видов, кадр в момент shot_t игрового времени (замедлено)
			var c2: Vector2 = p["pos"]
			for b in p["booms"]:
				if b[3] == "blast":
					m.fx.blast(c2 + (b[0] as Vector2), b[1])
				else:
					m.fx.explosion(c2 + (b[0] as Vector2), b[1], b[2], true, b[3])
			Engine.time_scale = 0.2
			_bt = 0.0
		_phase = 1
		_t = 0.0
		_pt = 0.0
	elif _phase == 1 and p.has("booms"):
		_bt += m.get_process_delta_time()
		if _bt >= float(p["shot_t"]):
			Engine.time_scale = 1.0
			_save(p["name"])
			_phase = 0
			_t = 0.0
			_pt = 0.0
			_i += 1
	elif _phase == 1 and _t > (0.25 if p.get("boom", false) else 0.05):
		_save(p["name"])
		_phase = 0
		_t = 0.0
		_pt = 0.0
		_i += 1


var _ew_t := {}   # S8 «eweap»: когда в точке последний раз стрелял каждый вид оружия


## S8 «eweap»: вокруг игрока стреляют все виды оружия врагов — ракеты трёх видов с разных сторон и очереди по видам пуль
const EW_GUNS := [["pickup", Vector2(-470, -160), 0.09, "пикап"], ["apc", Vector2(-320, 360), 0.12, "броневик"],
	["ifv", Vector2(330, -380), 0.2, "БМП"], ["zsu", Vector2(470, -60), 0.08, "ПВО"], ["fighter", Vector2(160, 430), 0.1, "перехватчики"],
	["ace", Vector2(-170, -460), 0.1, "асы"], ["big", Vector2(440, 280), 0.3, "корабли"]]
const EW_MSL := [["manpads", Vector2(-560, 260)], ["aam", Vector2(560, 330)], ["sam", Vector2(-60, -600)]]


func _ew_due(key: String, iv: float) -> bool:
	if _pt - float(_ew_t.get(key, -INF)) < iv:
		return false
	_ew_t[key] = _pt
	return true


func _eweap(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var pr := m.projectiles
	for g in EW_GUNS:
		if not _ew_due(g[0], g[2]):
			continue
		var at: Vector2 = c + (g[1] as Vector2)
		var gun: String = g[0]
		var dir := (c - at).normalized().rotated(randf_range(-1.0, 1.0) * Projectiles.gun_spread(gun) * 0.5)
		var big := gun == "big"
		var spd := 260.0 if big else Projectiles.gun_speed(gun)
		if gun == "zsu" or gun == "fighter":   # спаренные: пара параллельных пуль
			var side := Vector2(-dir.y, dir.x) * (9.0 if gun == "zsu" else 5.0)
			pr.spawn_enemy_bullet(at + side, dir * spd, g[3], false, 1.0, true, gun)
			pr.spawn_enemy_bullet(at - side, dir * spd, g[3], false, 1.0, true, gun)
		else:
			pr.spawn_enemy_bullet(at, dir * spd, g[3], big, 1.0, true, gun, at.distance_to(c) / spd + 0.1 if gun == "ifv" else 3.3)
	for ms in EW_MSL:
		if _ew_due(ms[0], 0.7):
			var at2: Vector2 = c + (ms[1] as Vector2)
			pr.spawn_missile(at2, (c - at2).normalized(), ms[0])


var _convoy: Convoy = null   # M-36: колонна для кадра дороги
var _bt := 0.0     # M-39: игровое время после взрывов точки «booms»
var _pt := 0.0     # время в точке (3.4-t1: эффекты — самолёт летит, за ним тянется след)


func _hold(p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var dt := m.get_process_delta_time()
	_pt += dt
	if p.has("cls"):   # 3.4-t1 п. 9, 19: другой самолёт (винты «Кита 1», сопла)
		m.player.cls_id = p["cls"][0]
		m.player.plane_lvl = p["cls"][1]
	if p.get("fly", false):
		# летим по кругу: след и огонь форсажа видны, камера над самолётом
		var a := _pt * 0.9
		pos += Vector2(cos(a), sin(a)) * 380.0
		m.player.heading = a + PI / 2.0
		m.player.ab_t = 1.0 if p.get("ab", false) else 0.0
		if p.get("missiles", false) and fmod(_pt, 0.5) < dt:
			m.projectiles.spawn_player_missile(pos, Vector2.from_angle(m.player.heading + randf_range(-0.6, 0.6)) * 700.0, null)
			m.projectiles.spawn_missile(pos + Vector2(500, -300), Vector2(-1, 0.4).normalized())
		m.player.global_position = pos
		m.camera.global_position = p["pos"]
	else:
		m.player.global_position = pos
		m.player.heading = -PI / 4.0
		m.camera.global_position = pos
	if p.get("crash", false) and m.player.wingmen.is_empty():
		m.player.add_wingman()
	if p.get("wingmen", false) and m.player.wingmen.is_empty():   # Т-8: звено из трёх типов рядом с игроком
		for wt in ["swift", "rook", "weasel"]:
			m.player.add_wingman(wt)
		for wm: Wingman in m.player.wingmen:
			wm.global_position = m.player.global_position + wm._slot_offset(m.player)
	if p.get("crash", false) and _pt > 1.2 and not p.has("_done"):
		# 3.4-t1 п. 32: ведомый сбит (бессмертие не даёт урон — обнуляем напрямую)
		p["_done"] = true
		var wm: Wingman = m.player.wingmen[0]
		wm.hp = 0.0
		wm.dead_t = 20.0
		wm.visible = false
		m.fx.explosion(wm.global_position, 22.0)
	if p.get("bombs", false) and m.projectiles.bombs.size() < 8:
		# бомбы всех ступеней (1–3 и «ковёр») с долгим взрывателем — на кадре видно падение
		var vt := (int(_pt * 10.0) % 4) + 1
		var to := pos + Vector2.from_angle(m.player.heading + randf_range(-0.5, 0.5)) * randf_range(420.0, 600.0)
		m.projectiles.spawn_bomb(pos + Vector2(randf_range(-20, 20), randf_range(-20, 20)), randf_range(4.0, 7.0), 0.0, 120.0, "бомбы", to, true)
		m.projectiles.bombs[-1]["vt"] = vt
	if p.has("carpet"):
		# тест 3.5-s5 (п. 3): сброс из бомбоотсека «Кита» — «ковёр» (true) или бомбы ступени 3 (false);
		# время замедлено: в облаке кадр идёт ~1 с, а бомба падает полсекунды
		# (почти стоит); кадр — через 0,21 с после сброса: створки открыты, часть бомб уже падает
		Engine.time_scale = 0.01 if p.has("_done") else 1.0
		if not p.has("_done"):   # бомбы прошлой точки не рвутся в кадре этой
			m.projectiles.bombs.clear()
		for wm: Wingman in m.player.wingmen:   # ведомые не заслоняют самолёт игрока
			wm.queue_free()
		m.player.wingmen.clear()
		for g: Hardpoint in m.player.groups:
			if g.name.begins_with("Бомбоотсек"):
				g.weapon = "bombs"
				g.level = Weapons.MAX_LEVEL
				g.evo = bool(p["carpet"])
				g.cd = 6.0
				if _t > 3.5 and not p.has("_done"):
					p["_done"] = true
					m.projectiles.bombs.clear()
					g._fire_bombs(m.player, true)
		if p.has("_done"):
			for b: Dictionary in m.projectiles.bombs:
				b["t"] = float(b["fuse"]) - float(p.get("ph", 0.21))
			for n in Render3D.I.find_children("bay_doors", "", true, false):
				n.set_meta("t", 1.0)
				n.set_meta("hold", 1.0)
	elif Engine.time_scale < 0.05:
		Engine.time_scale = 1.0
	if p.get("craters", false) and not p.has("_done"):
		p["_done"] = true
		for i in 9:
			var cp := pos + Vector2.from_angle(i * 0.7) * (140.0 + 45.0 * i)
			m.fx.ground.crater(cp, [90.0, 120.0, 150.0][i % 3])
	if p.has("roll"):   # 3.4-t1 п. 6: самолёт в бочке, брюхом к камере
		m.player.roll_dir = 1
		m.player.roll_t = m.player.roll_time() * float(p["roll"])
	m.camera.zoom = Vector2.ONE * float(p.get("zoom", 1.0))
	m.camera.reset_smoothing()


func _save(name: String) -> void:
	var img := m.get_viewport().get_texture().get_image()
	img.save_png("user://vis_%s%s.png" % [name, _suffix])
	if Render3D.I != null and Render3D.I._tilt_on:   # отладка B-47: что попало в текстуру слоя боя
		Render3D.I._combat_vp.get_texture().get_image().save_png("user://vis_%s_combat.png" % name)
	# яркость: каждый 4-й пиксель по обеим осям
	var n := 0
	var hot := 0
	var sum := 0.0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			var l := (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0
			sum += l
			n += 1
			if l > 245.0:
				hot += 1
	print("VISUAL %s lum=%.1f hot=%.2f%%" % [name, sum / maxf(n, 1), 100.0 * hot / maxf(n, 1)])
	# M-31: вызовы отрисовки основного вьюпорта (видимые и тени) — сравнение «до/после»
	var rid := m.get_viewport().get_viewport_rid()
	print("VISUAL %s draws=%d prims=%dk shadow_draws=%d" % [name,
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) / 1000,
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	print("VISUAL %s nodes=%d" % [name, m.get_tree().get_node_count()])
	if Render3D.I != null and Render3D.I.terrain != null:   # Р-13: заглушки рельефа сейчас и кадров с ними с начала
		print("VISUAL %s terrain lods=%d lod_frames=%d" % [name, Render3D.I.terrain._lods.size(), Render3D.I.terrain.lod_frames])
	if Render3D.I != null:   # облака: сколько вызовов и экземпляров (плоские — по облаку на вызов; клубы — один MultiMesh)
		var R := Render3D.I
		var flat := 0
		var flat_fill := 0.0
		var planes := R.cam.get_frustum()
		for mi: MeshInstance3D in R._clouds:   # в кадре камеры (как Perf._tri_report): один вызов на облако
			if not mi.visible:
				continue
			var bb := mi.global_transform * mi.get_aabb()
			if planes.all(func(pl: Plane) -> bool: return pl.distance_to(bb.get_support(-pl.normal)) <= 0.0):
				flat += 1
				var dp := (mi.global_position - R.cam.global_position).dot(-R.cam.global_transform.basis.z)
				var spx := bb.size.x * m.get_viewport().get_visible_rect().size.y * 0.5 / tan(deg_to_rad(R.cam.fov) * 0.5) / maxf(dp, 1.0)
				flat_fill += spx * spx / (m.get_viewport().get_visible_rect().size.x * m.get_viewport().get_visible_rect().size.y)
		var low := 0
		if R._puffs != null:
			for c: Dictionary in R._puffs._cache.values():
				low += 1 if c["low"] else 0
		print("VISUAL %s clouds: плоских в кадре=%d (заливка %.2f кадра) клубов=%d (вызов %d, заливка %.2f кадра) низких облаков=%d вуаль=%.2f" % [name, flat, flat_fill,
			R._puffs.shown if R._puffs != null else 0, 1 if R._puffs != null and R._puffs.shown > 0 else 0,
			R._puffs.fill if R._puffs != null else 0.0, low,
			R._puffs.immersion if R._puffs != null else 0.0])
		if R._puffs != null: print("VISUAL  veil ", R._puffs._veil.visible, " ", R._puffs._veil.get_global_rect(), " ", R._puffs._veil.is_visible_in_tree())


## Точки: пустыня, гора, кишлак, оазис, бой со взрывами, крупный план самолёта
func _make_points() -> Array:
	var bg := m.background
	var found := {}
	var empty := Vector2.INF
	var cnt := {}   # 3.5-s8: сколько объектов каждого вида на 29 × 29 клеток (кишлаков стало меньше?)
	var near_river := {}   # тест 3.5-s4 (п. 16): поселения ближе всех к реке (кромка у воды): имя → [зазор, объект]
	var ter: Terrain3D = Render3D.I.terrain if Render3D.I != null else null
	for r in range(0, 14):
		for cx in range(-r, r + 1):
			for cy in range(-r, r + 1):
				if maxi(absi(cx), absi(cy)) != r:
					continue
				var o := bg.chunk_object(cx, cy)
				if o.is_empty():
					if empty == Vector2.INF:
						empty = Vector2((cx + 0.5) * Background.CHUNK, (cy + 0.5) * Background.CHUNK)
				else:
					if not found.has(o["name"]):
						found[o["name"]] = o["pos"]
					cnt[o["name"]] = int(cnt.get(o["name"], 0)) + 1
					if ter != null and o["name"] in Terrain3D.SETTLE:
						var gap := absf(ter.river_field(o["pos"].x, o["pos"].y)) - float(o["size"]) * 0.5
						if gap < float(near_river.get(o["name"], [INF])[0]):
							near_river[o["name"]] = [gap, o]
	print("VISUAL objects ", cnt)
	if empty == Vector2.INF:
		empty = Vector2.ZERO
	var pts := [{"name": "desert", "pos": empty}]
	# B-26: горы теперь — рельеф; берём самую высокую точку рядом с пустой клеткой
	var peak := empty + Vector2(4000, 0)
	if Render3D.I != null and Render3D.I.terrain != null:
		peak = Render3D.I.terrain.find_peak(empty)
	pts.append({"name": "mountain", "pos": peak})
	if ter != null:   # M-36: скальные выходы на склоне (общий план и крупно) и осыпь у подножия
		var best_r := [-1.0, empty]
		var best_s := [-1.0, empty]
		for gx in range(-24, 25):
			for gz in range(-24, 25):
				var q := empty + Vector2(gx, gz) * 200.0
				var vv := ter.valley(q.x, q.y)
				var rl := ter._relief(q.x, q.y, vv)
				var sr := rl.y - absf(absf(vv) - 900.0) / 2000.0
				if sr > best_r[0]:
					best_r = [sr, q]
				if rl.z > best_s[0]:
					best_s = [rl.z, q]
		print("VISUAL rocks at ", best_r[1], " foot ", best_s[1])
		pts.append({"name": "rocks_range", "pos": best_r[1], "zoom": 0.6})
		pts.append({"name": "rocks_slope", "pos": best_r[1], "zoom": 1.6})
		pts.append({"name": "rocks_foot", "pos": best_s[1], "zoom": 1.2})
		# M-36: дорога шире — колонна конвоя стоит на дороге (логика машин выключена)
		pts.append({"name": "road_convoy", "pos": ter._field_point(empty + Vector2(0, 700), Terrain3D.D_ROAD), "zoom": 2.2, "convoy": true, "wait": 1.5})
		# M-37: позиция ПВО целиком и рядом с колонной (размеры ПВО относительно машин конвоя)
		pts.append({"name": "aa_site", "pos": empty, "zoom": 1.0, "enemies": true, "ground": true, "wait": 2.5})
		pts.append({"name": "aa_convoy", "pos": ter._field_point(empty + Vector2(0, 700), Terrain3D.D_ROAD), "zoom": 1.3, "convoy": true, "enemies": true, "ground": true, "site_off": Vector2(-380, -40), "wait": 2.5})
	for k in [["village", "o_village"], ["oasis", "o_oasis"], ["fort", "o_fort"]]:
		pts.append({"name": k[0], "pos": found.get(k[1], empty + Vector2(4000, 0))})
	if found.has("o_village"):   # тест 3.5-s8: кишлак-городок общим планом и крупно (центр, базар)
		# с наклоном камеры земля в центре кадра — севернее игрока: точка южнее посёлка, чтобы он был в центре
		pts.append({"name": "village_wide", "pos": found["o_village"] + Vector2(0, 700), "zoom": 0.6})
		pts.append({"name": "village_close", "pos": found["o_village"] + Vector2(0, 600), "zoom": 2.4})
		for vr in 4:
			AdobeBuild._vcache.erase("village%d" % vr)
			var t0 := Time.get_ticks_usec()
			var vm := AdobeBuild.village(vr)
			print("VISUAL village%d mesh tris=%d build=%d ms %s" % [vr, vm.surface_get_array_len(0) / 3, (Time.get_ticks_usec() - t0) / 1000, AdobeBuild._vcache.get("village%d_stats" % vr, {})])
	# сцены прошедших боёв (Terrain3D.scenes): первая с самолётом и первая с танком — крупнее
	if ter != null:
		var got := {}
		for r in range(0, 6):
			for cx in range(-r, r + 1):
				for cy in range(-r, r + 1):
					if maxi(absi(cx), absi(cy)) != r:
						continue
					for it in ter.scenes(Vector2i(cx, cy)):
						if it["k"] in ["plane", "tank", "sandbag"] and not got.has(it["k"]):
							got[it["k"]] = true
							pts.append({"name": "scene_" + String(it["k"]), "pos": (it["p"] as Vector2) + Vector2(0, 110), "zoom": 2.5})
	for nm in ["o_village", "o_oasis"]:
		if near_river.has(nm):
			pts.append({"name": "river_" + nm.substr(2), "pos": near_river[nm][1]["pos"]})
	if ter != null:   # тест 3.5-s5 (M-35): охранная зона реки крупно — русло, мокрый берег, дорога рядом
		pts.append({"name": "river_reach", "pos": ter._field_point(empty + Vector2(0, 700), 0.0), "zoom": 1.8})
		var rv: Dictionary = near_river.get("o_village", [0, {}])[1]
		if not rv.is_empty():
			pts.append({"name": "river_edge", "pos": ter._field_point(rv["pos"], 0.0), "zoom": 2.2})
	if ter != null:   # L-07: мосты — пешеходный у оазиса, дорожный через ручей посёлка
		if found.has("o_oasis"):
			pts.append({"name": "footbridge", "pos": ter._river_point(found["o_oasis"]), "zoom": 2.5})
		if found.has("o_village"):
			for sd in ter._sides(found["o_village"].x, found["o_village"].y):
				if float(sd[2]) < 0.0:
					var f0: float = ter.river_field(sd[0].x, sd[0].y) - Terrain3D.D_ROAD
					var f1: float = ter.river_field(sd[1].x, sd[1].y) - Terrain3D.D_ROAD
					if f0 * f1 <= 0.0 and f0 != f1:
						pts.append({"name": "road_bridge", "pos": (sd[0] as Vector2).lerp(sd[1], f0 / (f0 - f1)), "zoom": 2.5})
						break
	pts.append({"name": "battle", "pos": empty + Vector2(0, -300), "boom": true})
	if found.has("o_wreck"):   # тест 3.5-s4 (п. 18): обломки самолёта крупно
		pts.append({"name": "wreck", "pos": found["o_wreck"], "zoom": 2.5})
	pts.append({"name": "closeup", "pos": found.get("o_rocks_big", empty) + Vector2(-260, 0), "zoom": 2.5})
	pts.append({"name": "roll", "pos": empty + Vector2(300, 300), "zoom": 2.5, "roll": 0.62})
	pts.append({"name": "roll90", "pos": empty + Vector2(300, 300), "zoom": 2.5, "roll": 0.78})
	if OS.get_cmdline_user_args().has("--fxbench"):   # 3.4-t1: эффекты (след, форсаж, ракеты, винты, падение ведомого)
		pts = []
		pts.append({"name": "trail", "pos": empty, "fly": true, "wait": 3.0, "zoom": 0.8})
		pts.append({"name": "trail_ab", "pos": empty, "fly": true, "ab": true, "missiles": true, "wait": 3.0, "zoom": 0.8})
		# M-39 (аудит 3.5-s6 Э-1): раскадровка взрывов — наземные (ground, blast) слева, воздушные (air, big, flak) справа
		var bl := [[Vector2(-330, 120), 18.0, false, ""], [Vector2(-120, 230), 130.0, false, "blast"], [Vector2(-360, -170), 14.0, false, ""],
			[Vector2(220, -110), 22.0, true, ""], [Vector2(330, 170), 46.0, true, ""], [Vector2(80, -230), 12.0, true, "flak"]]
		for bi in 4:
			var bt: float = [0.1, 0.45, 1.2, 3.0][bi]
			pts.append({"name": "boom_%d" % bi, "pos": empty + Vector2(3000.0 * (bi + 1), 0), "booms": bl, "shot_t": bt, "wait": 1.0, "zoom": 1.0})
		pts.append({"name": "nozzle_ab", "pos": empty, "fly": true, "ab": true, "wait": 1.0, "zoom": 2.2})
		pts.append({"name": "crash_fall", "pos": empty + Vector2(0, 600), "crash": true, "wait": 2.0, "zoom": 1.2})
		pts.append({"name": "crash_wreck", "pos": empty + Vector2(0, 600), "wait": 2.5, "zoom": 1.2})
		pts.append({"name": "kit_props", "pos": empty + Vector2(300, 300), "cls": ["bomber", 1], "wait": 0.8, "zoom": 2.2})
	if OS.get_cmdline_user_args().has("--eweapbench"):   # S8 «eweap»: ракеты ПЗРК / самолёта / ЗРК и трассеры по видам оружия
		pts = []
		pts.append({"name": "eweap", "pos": empty, "eweap": true, "shot_t": 1.5, "zoom": 1.0})
		pts.append({"name": "eweap_close", "pos": empty, "eweap": true, "shot_t": 1.5, "zoom": 2.0})
	if OS.get_cmdline_user_args().has("--bombbench"):   # тест 3.5-s4 (п. 10, 14): падающие бомбы ступеней и воронки
		pts = []
		pts.append({"name": "bomb_drop", "pos": empty + Vector2(300, 300), "cls": ["bomber", 1], "bombs": true, "wait": 2.5, "zoom": 2.6})
		for lv in [1, 2]:
			pts.append({"name": "carpet_drop_%d" % lv, "pos": empty + Vector2(300, 300), "cls": ["bomber", lv], "carpet": true, "wait": 6.5, "zoom": 5.0})
			pts.append({"name": "carpet_roll_%d" % lv, "pos": empty + Vector2(300, 300), "cls": ["bomber", lv], "carpet": true, "wait": 6.5, "zoom": 5.0, "roll": 0.62, "ph": 0.17})
			pts.append({"name": "baybomb_drop_%d" % lv, "pos": empty + Vector2(300, 300), "cls": ["bomber", lv], "carpet": false, "wait": 6.5, "zoom": 5.0})
		pts.append({"name": "bomb_craters", "pos": empty + Vector2(300, 300), "cls": ["bomber", 1], "craters": true, "wait": 3.0, "zoom": 1.0})
	if OS.get_cmdline_user_args().has("--cloudbench"):   # тест 3.5-s5 (M-31): облака — рядом, над игроком, общий план
		pts = []
		var cl: Array = m.clouds.items() if m.clouds != null else []
		cl.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector2).length() < (b[0] as Vector2).length())
		for i in mini(cl.size(), 2):
			var cp: Vector2 = cl[i][0]
			pts.append({"name": "clouds_%d_near" % i, "pos": cp + Vector2(330, 260), "wait": 1.0})
			pts.append({"name": "clouds_%d_under" % i, "pos": cp, "wait": 1.0})
		if not cl.is_empty():
			pts.append({"name": "clouds_wide", "pos": (cl[0][0] as Vector2) + Vector2(500, 300), "zoom": 0.6, "wait": 1.0})
	if OS.get_cmdline_user_args().has("--seabench") and ter != null and ter.props != null:
		# «Архипелаг» (-- --visual --seabench --op=5): композиции берега крупно и общим планом, по 2 каждого типа
		pts = []
		var mark := {"harbor": "s_pier_a", "cape": "s_lighthouse", "battery": "s_gun", "beach": "s_hedgehog", "reef": "s_wreck_a"}
		var seen := {}
		for r in range(0, 9):
			for cx in range(-r, r + 1):
				for cy in range(-r, r + 1):
					if maxi(absi(cx), absi(cy)) != r:
						continue
					var key := Vector2i(cx, cy)
					var c := SeaProps.comp_of(key)
					if c == "" or int(seen.get(c, 0)) >= 2:
						continue
					var put := ter.props.plan(key, ter._ctx(key))
					var arr: Array = put.get(mark[c], put.get("s_wreck_b", [])) if c == "reef" else put.get(mark[c], [])
					if arr.is_empty():
						continue
					var at := Vector2((arr[0] as Transform3D).origin.x, (arr[0] as Transform3D).origin.z)
					var n := int(seen.get(c, 0))
					seen[c] = n + 1
					pts.append({"name": "sea_%s_%d" % [c, n], "pos": at, "zoom": 1.6, "wait": 1.2})
					pts.append({"name": "sea_%s_%d_wide" % [c, n], "pos": at, "zoom": 0.7, "wait": 1.2})
		print("VISUAL sea compositions ", seen)
	if OS.get_cmdline_user_args().has("--terrainbench") and ter != null:
		# тест 3.5-s6 (аудит визуала): рельеф в разных местах биома крупно / средне / далеко
		pts = []
		var vil: Vector2 = found.get("o_village", empty)
		var spots := {
			"peak": peak,
			"slope": ter._field_point(empty + Vector2(900, 0), 1100.0),
			"foot": ter._field_point(empty + Vector2(0, 400), 420.0),
			"valley": ter._field_point(empty, 0.0),
			"plain": empty,
			"village": vil,
			"seam": Vector2(floorf(empty.x / Terrain3D.CHUNK) * Terrain3D.CHUNK, floorf(empty.y / Terrain3D.CHUNK) * Terrain3D.CHUNK),
		}
		for k in spots:
			for zz in [["near", 2.5], ["mid", 1.0], ["far", 0.55]]:
				pts.append({"name": "ter_%s_%s" % [k, zz[0]], "pos": spots[k], "zoom": zz[1], "wait": 1.2})
	if OS.get_cmdline_user_args().has("--modelbench"):   # 3.5: самолёты игрока 3D-моделями в бою
		pts = []
		for c in ["fighter", "attacker", "bomber"]:
			for lv in [1, 2]:
				pts.append({"name": "model_%s_%d" % [c, lv], "pos": empty + Vector2(300, 300), "cls": [c, lv], "wait": 1.0, "zoom": 2.2})
				pts.append({"name": "model_%s_%d_far" % [c, lv], "pos": empty + Vector2(300, 300), "cls": [c, lv], "fly": true, "wait": 1.5, "zoom": 1.0})
		pts.append({"name": "model_wingmen", "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": 2.0, "wingmen": true, "wait": 1.0})
		pts.append({"name": "model_roll", "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": 2.2, "roll": 0.62})
		pts.append({"name": "model_tanker", "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": 1.5, "tanker": true, "wait": 1.0})
		pts.append({"name": "model_ground", "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": 1.3, "enemies": true, "ground": true, "wait": 2.5})
		for ph in [1, 2, 3]:
			pts.append({"name": "model_fortress_%d" % ph, "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": 1.0, "enemies": true, "fortress": ph, "wait": 2.5})
		pts.append({"name": "model_enemies", "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": 1.6, "enemies": true, "wait": 0.6})
	return pts



## 3.5: враги всех видов рядом с игроком (стенд 3D-моделей в бою)
var _spawned := false
var _fort: Fortress = null
var _g_spawned := false


func _spawn_all_enemies(c: Vector2) -> void:
	_spawned = true
	var list: Array = []
	var d := Drone.new()
	list.append(d)
	list.append(Interceptor.new())
	list.append(MissileCarrier.new())
	var r := RivalAce.new()
	list.append(r)
	for v in ["carrier", "interceptor"]:
		var b := Boss.new()
		b.setup(v, 99999.0)
		list.append(b)
	var tr := Transport.new()   # Т-7: транспортник 3D-моделью
	tr.setup(99999.0)
	list.append(tr)
	for i in list.size():
		var e: Enemy = list[i]
		e.position = c + Vector2.from_angle(TAU * i / list.size()) * 260.0
		e.heading = TAU * i / list.size() + PI / 2.0
		m.world.add_child(e)
		if e is RivalAce:
			(e as RivalAce).setup(99999.0)


## 3.4-t1 (п. 1): 3D-ангар — вкладка «САМОЛЁТ» каждого класса, ур. 1 и ур. 2 → user://vis_hangar_<класс>_<ур>.png
var _hq: Array = []
var _hf := 0
## Тест 3.5-s7 (дефекты окраски в ангаре): --hangarclose вместе с --liveries — крупные планы
## [фокус, рысканье, тангаж, дальность], как виды 8 и 10 листа окрасок (tools/model_lab/livery_sheet.gd):
## гондола и правое крыло сзади почти по горизонту (ракурс скриншота Kanta), хвост внутренней гондолы снизу сзади
var _hclose: Array = ([
	[Vector3(-0.12, 0.0, 0.2), 2.75, 0.1, 0.34],
	[Vector3(-0.17, -0.03, 0.145), 2.6, -0.35, 0.2],
] if OS.get_cmdline_user_args().has("--hangarclose") else [])


## Тест 3.5-s8 (--mechanim): ракурсы показа механизации [фокус, рысканье, тангаж, дальность] по классам
const MECH_FRAMES := 8
const MECH_DT := 0.75   # с между кадрами: 8 кадров = полный цикл HangarAnim (6 с)
const _MECH_VIEWS := {
	# сзади сбоку чуть сверху: закрылки уходят вниз за заднюю кромку — сверху их не видно
	"fighter": [[Vector3(-0.1, -0.01, 0.0), 2.8, 0.16, 1.0]],
	"attacker": [[Vector3(-0.08, 0.0, 0.0), 2.75, 0.22, 1.05]],
	"bomber": [[Vector3(-0.08, 0.0, 0.0), 2.75, 0.2, 1.1], [Vector3(0.0, -0.03, 0.0), 2.0, -0.6, 1.0]],
}


func _hangar_bench() -> void:
	if _t < 1.5:
		return
	if m.state != "hangar":
		m.ui_click("menu_hangar")
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--turretstyle="):
				WeaponModels.turret_style = int(a.get_slice("=", 1))
		if OS.get_cmdline_user_args().has("--turretclose"):
			# крупно турели: штурмовик и бомбардировщик по ступеням 1 / 2 / 3 и эволюции (4), кормовая установка
			# [класс, ур., ступень, № турели]; у «Кита» № 0 — корма, 1 — на спине (ступени 2+: с ур. 3)
			for q in [["attacker", 1, 1, 0], ["attacker", 1, 2, 0], ["attacker", 2, 3, 0],
					["bomber", 1, 1, 1], ["bomber", 1, 2, 1], ["bomber", 1, 3, 1], ["bomber", 1, 4, 1], ["bomber", 2, 3, 1],
					["bomber", 1, 1, 0], ["bomber", 1, 2, 0], ["bomber", 2, 3, 0]]:
				_hq.append(q)
			_t = 0.0
			return
		if OS.get_cmdline_user_args().has("--mechanim"):
			# тест 3.5-s8: показ механизации — кадры анимации подряд (MECH_FRAMES через MECH_DT с) по ракурсам _MECH_VIEWS
			for c in PlaneClasses.LIST:
				for vi in (_MECH_VIEWS[c] as Array).size():
					if OS.get_cmdline_user_args().has("--mechview=%d" % (1 - vi)):   # только один ракурс
						continue
					for f in MECH_FRAMES:
						_hq.append([c, 1, 3 if c == "bomber" else 1, "M", f, vi])
			_t = 0.0
			return
		if OS.get_cmdline_user_args().has("--hangarweaptab"):
			# тест 3.5-s3: вкладка «ОРУЖИЕ» — каждое оружие объёмной моделью, ступени 1 / 3 / 5 и модернизация
			var wl := ["aam", "rockets", "bombs", "flares", "turret"]
			for a in OS.get_cmdline_user_args():   # --weaplist=bombs,flares — только эти виды
				if a.begins_with("--weaplist="):
					wl = Array(a.get_slice("=", 1).split(","))
			for w in wl:
				for wt in [1, 2, 3, 4]:
					_hq.append(["W", w, wt])
			_t = 0.0
			return
		if OS.get_cmdline_user_args().has("--hangarcarpet"):
			# тест 3.5-s5 (п. 3): «Кит» ур. 1 и 2 — бомбы ступени 3 и «ковёр» в открытом бомбоотсеке (вид снизу сбоку)
			for lv in [1, 2]:
				for wt in [3, 4]:
					_hq.append(["bomber", lv, wt])
			_t = 0.0
			return
		var evo_bench := OS.get_cmdline_user_args().has("--hangarevo")
		if evo_bench or OS.get_cmdline_user_args().has("--hangarweap"):
			# Т-6 (--hangarevo): все эволюции — «Шмель» и «Салют» на истребителе, «Ливень» и «Бабушкин ковёр»
			# на штурмовике, «Бабушкин ковёр» и «Салют» на «Ките»; ступень 3 рядом для сравнения.
			# Т-5 (--hangarweap): то же оружие по ступеням 1 / 2 / 3 — ловушки и кассетные бомбы
			Hangar3D.bench_weapons = {"fighter": ["", "flares"], "attacker": ["", "bombs"], "bomber": ["", "flares"]}
			for c in PlaneClasses.LIST:
				for wt in ([3, 4] if evo_bench else [1, 2, 3]):
					_hq.append([c, 1, wt])
			_t = 0.0
			return
		if OS.get_cmdline_user_args().has("--liveries"):   # п. 35: каждый класс во всех окрасках (ур. 1; --livlvl=2 — ур. 2)
			var llv := 1
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--livlvl="):
					llv = int(a.get_slice("=", 1))
			for c in PlaneClasses.LIST:
				for lv in [llv]:
					for lv2: Array in Livery.list(c):
						if _hclose.is_empty():
							_hq.append([c, lv, 1, "L", lv2[0]])
						else:   # тест 3.5-s7: --hangarclose — крупные планы (гондола и крыло, хвост гондолы)
							for vi in _hclose.size():
								_hq.append([c, lv, 1, "L", lv2[0], vi])
			_t = 0.0
			return
		for c in PlaneClasses.LIST:
			if OS.get_cmdline_user_args().has("--modfront") or OS.get_cmdline_user_args().has("--modrear"):
				for lv in [1, 2]:
					_hq.append([c, lv, 1])
				continue
			if OS.get_cmdline_user_args().has("--hangarlow"):
				for lv in [1, 2]:
					for wt in [1, 2, 3]:
						_hq.append([c, lv, wt])
				continue
			if OS.get_cmdline_user_args().has("--hangarside"):
				_hq.append([c, 1, 1])
				_hq.append([c, 2, 1])
				continue
			for lv in [1, 2]:
				_hq.append([c, lv, 1])
			_hq.append([c, 1, 2])
			_hq.append([c, 1, 3])
		_t = 0.0
		return
	for a in OS.get_cmdline_user_args():   # --hangarcls=bomber: только этот класс
		if a.begins_with("--hangarcls="):
			_hq = _hq.filter(func(q: Array) -> bool: return q[0] == a.get_slice("=", 1))
	if _hq.is_empty():
		print("VISUAL done")
		m.get_tree().quit()
		return
	var cur: Array = _hq[0]
	if cur[0] == "W":
		m.hangar_tab = "weapons"
		m.hangar_cls = "attacker"
		m.hangar_w = cur[1]
		if Hangar3D.I != null:
			Hangar3D.I.weapon_tier = cur[2]
			Hangar3D.I._idle = 0.0
		_hf += 1
		if _hf > 8 and _t > 1.2:
			_save("hangar_w_%s_%d" % [cur[1], cur[2]])
			_hq.pop_front()
			_t = 0.0
			_hf = 0
		return
	m.hangar_tab = "plane"
	m.hangar_cls = cur[0]
	if Hangar3D.I != null:
		Hangar3D.I._cls = cur[0]
		Hangar3D.I.view_lvl = cur[1]
		Hangar3D.I.weapon_tier = cur[2]
		if cur.size() > 5 and typeof(cur[3]) == TYPE_STRING and cur[3] == "M":   # --mechanim
			var mv: Array = _MECH_VIEWS[cur[0]][cur[5]]
			Hangar3D.I.mech_demo = true
			Hangar3D.anim_time = float(cur[4]) * MECH_DT
			Hangar3D.bench_pitch_min = -0.9
			Hangar3D.I.focus = mv[0]
			Hangar3D.I._yaw = mv[1]
			Hangar3D.I._pitch = mv[2]
			Hangar3D.I._dist = mv[3]
			Hangar3D.I._idle = 0.0
		elif cur.size() > 4:   # --liveries: окраска из очереди (в профиль без сохранения)
			Profile.cls(cur[0])["livery"] = cur[4]
			if cur.size() > 5:   # --hangarclose: [фокус, рысканье, тангаж, дальность]
				var hv: Array = _hclose[cur[5]]
				Hangar3D.bench_pitch_min = -0.9
				Hangar3D.I.focus = hv[0]
				Hangar3D.I._yaw = hv[1]
				Hangar3D.I._pitch = hv[2]
				Hangar3D.I._dist = hv[3]
				Hangar3D.I._idle = 0.0
		elif cur.size() > 3:   # --turretclose: крупный план турели № cur[3]
			var h := Hangar3D.I
			var tp: Array = h.turret_pos[cur[3]] if cur[3] < h.turret_pos.size() else [Vector3.ZERO, "top"]
			h.focus = tp[0]
			h._yaw = 2.2 if tp[1] != "tail" else 2.7
			h._pitch = {"top": 0.45, "tail": 0.3, "bottom": -0.25}.get(tp[1], 0.3)
			h._dist = 0.3
			h._idle = 0.0
		elif OS.get_cmdline_user_args().has("--hangarside"):   # вид сбоку: проверка, где сидят турели и подвесы
			Hangar3D.I._yaw = PI / 2.0
			Hangar3D.I._pitch = 0.06
			Hangar3D.I._idle = 0.0
		elif OS.get_cmdline_user_args().has("--modfront") or OS.get_cmdline_user_args().has("--modrear"):
			# Т-3: модули крупно — спереди сбоку сверху (броня, пушка, антенны) или сзади (сопла)
			var front := OS.get_cmdline_user_args().has("--modfront")
			Hangar3D.I._yaw = -0.9 if front else 2.5
			Hangar3D.I._pitch = 0.35 if front else 0.2
			Hangar3D.I._dist = 0.75
			Hangar3D.I._idle = 0.0
		elif OS.get_cmdline_user_args().has("--hangarcarpet"):   # снизу сбоку: открытый бомбоотсек
			Hangar3D.bench_pitch_min = -0.9
			Hangar3D.I._yaw = PI / 2.0 + 0.5
			Hangar3D.I._pitch = -0.62
			Hangar3D.I._dist = 0.9
			Hangar3D.I._idle = 0.0
		elif OS.get_cmdline_user_args().has("--hangarlow"):   # снизу сбоку крупно: подвесы под крылом на пилонах
			Hangar3D.I._yaw = 2.3
			Hangar3D.I._pitch = -0.12
			Hangar3D.I._dist = 0.7
			Hangar3D.I._idle = 0.0
		elif OS.get_cmdline_user_args().has("--hangartop"):   # вид сверху: турели и подвесы по размаху
			Hangar3D.I._yaw = PI / 2.0
			Hangar3D.I._pitch = 1.45
			Hangar3D.I._idle = 0.0
	_hf += 1
	var mech_next: bool = cur.size() > 5 and typeof(cur[3]) == TYPE_STRING and int(cur[4]) > 0   # модель уже собрана
	if (_hf > 8 and _t > 1.2 and (cur.size() < 6 or typeof(cur[3]) != TYPE_STRING or _hf > 14)) or (mech_next and _hf > 2):   # в облаке (программная отрисовка) кадр идёт ~1 с — ждём кадры, а не секунды
		if cur.size() > 5 and typeof(cur[3]) == TYPE_STRING:
			# только сам вид ангара (SubViewport, с запасом по разрешению) — для серии кадров и GIF
			Hangar3D.I.vp.get_texture().get_image().save_png("user://vis_mech_%s_v%d_f%02d.png" % [cur[0], cur[5], cur[4]])
			if int(cur[4]) == 0 and cur[5] == 0:
				_save("mech_%s_screen" % cur[0])
		elif cur.size() > 5:
			_save("hangar_close_%s_%d_%s_v%d" % [cur[0], cur[1], cur[4], cur[5]])
		elif cur.size() > 4:
			_save("hangar_livery_%s_%d_%s" % [cur[0], cur[1], cur[4]])
		elif cur.size() > 3:
			_save("turret_s%d_%s_%d_w%d_v%d" % [WeaponModels.turret_style, cur[0], cur[1], cur[2], cur[3]])
		else:
			_save("hangar_%s_%d_w%d" % [cur[0], cur[1], cur[2]])
		_hq.pop_front()
		_t = 0.0
		_hf = 0


## Тест 3.5-s5 (п. 1): заставка главного меню — кадры на 3, 6 и 9 с → user://vis_menu_<с>.png
## (с --gfx=0 — спрайтовый режим «Низкого»)
var _ms := 0


func _menu_shot() -> void:
	if m.state != "menu":
		return
	var at := [3.0, 6.0, 9.0]
	for a in OS.get_cmdline_user_args():   # M-31: свои моменты кадров, --menuat=12,20,28
		if a.begins_with("--menuat="):
			at = Array(a.substr(9).split(",")).map(func(x: String) -> float: return float(x))
	if _ms < at.size() and _t >= at[_ms]:
		_save("menu_%d" % int(at[_ms]))
		_ms += 1
	if _ms >= at.size():
		print("VISUAL done")
		m.get_tree().quit()
