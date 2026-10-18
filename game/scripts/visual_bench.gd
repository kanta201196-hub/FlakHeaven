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
	var keep: bool = _i >= 0 and _i < _points.size() and (_points[_i] as Dictionary).get("enemies", false)
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
			site.setup(m.player.global_position + Vector2(0, -120), 1.0, 99999.0)
			m.world.add_child(site)
			p["pos"] = site.global_position + Vector2(0, 160)
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
	_hold(p)
	if _phase == 0 and _t > float(p.get("wait", WAIT)):
		if p.get("boom", false):
			var c: Vector2 = p["pos"]
			m.fx.explosion(c + Vector2(220, -90), 34.0)
			m.fx.explosion(c + Vector2(-260, 140), 22.0)
			m.fx.explosion(c + Vector2(60, 230), 16.0, false)
		_phase = 1
		_t = 0.0
		_pt = 0.0
	elif _phase == 1 and _t > (0.25 if p.get("boom", false) else 0.05):
		_save(p["name"])
		_phase = 0
		_t = 0.0
		_pt = 0.0
		_i += 1


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
					if ter != null and o["name"] in Terrain3D.SETTLE:
						var gap := absf(ter.river_field(o["pos"].x, o["pos"].y)) - float(o["size"]) * 0.5
						if gap < float(near_river.get(o["name"], [INF])[0]):
							near_river[o["name"]] = [gap, o]
	if empty == Vector2.INF:
		empty = Vector2.ZERO
	var pts := [{"name": "desert", "pos": empty}]
	# B-26: горы теперь — рельеф; берём самую высокую точку рядом с пустой клеткой
	var peak := empty + Vector2(4000, 0)
	if Render3D.I != null and Render3D.I.terrain != null:
		peak = Render3D.I.terrain.find_peak(empty)
	pts.append({"name": "mountain", "pos": peak})
	for k in [["village", "o_village"], ["oasis", "o_oasis"], ["fort", "o_fort"]]:
		pts.append({"name": k[0], "pos": found.get(k[1], empty + Vector2(4000, 0))})
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
		pts.append({"name": "nozzle_ab", "pos": empty, "fly": true, "ab": true, "wait": 1.0, "zoom": 2.2})
		pts.append({"name": "crash_fall", "pos": empty + Vector2(0, 600), "crash": true, "wait": 2.0, "zoom": 1.2})
		pts.append({"name": "crash_wreck", "pos": empty + Vector2(0, 600), "wait": 2.5, "zoom": 1.2})
		pts.append({"name": "kit_props", "pos": empty + Vector2(300, 300), "cls": ["bomber", 1], "wait": 0.8, "zoom": 2.2})
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
			# [класс, ур., ступень, № турели]; у «Кита» № 0 — корма, 1 и 2 — на крыльях
			for q in [["attacker", 1, 1, 0], ["attacker", 1, 2, 0], ["attacker", 2, 3, 0],
					["bomber", 1, 1, 2], ["bomber", 1, 2, 2], ["bomber", 1, 3, 2], ["bomber", 1, 4, 2], ["bomber", 2, 3, 1],
					["bomber", 1, 1, 0], ["bomber", 1, 2, 0], ["bomber", 2, 3, 0]]:
				_hq.append(q)
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
						_hq.append([c, lv, 1, "L", lv2[0]])
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
		if cur.size() > 4:   # --liveries: окраска из очереди (в профиль без сохранения)
			Profile.cls(cur[0])["livery"] = cur[4]
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
	if _hf > 8 and _t > 1.2:   # в облаке (программная отрисовка) кадр идёт ~1 с — ждём кадры, а не секунды
		if cur.size() > 4:
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
