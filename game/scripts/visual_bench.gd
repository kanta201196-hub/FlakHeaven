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
		if a == "--relief0":   # relief lab: frames of the current relief (vis_<name>_before.png)
			_suffix += "_before"
		if a.begins_with("--tag="):   # parallel workers share user://: vis_<name>_<tag>.png keeps frames apart
			_suffix += "_" + a.substr(6)
		if a == "--nowater":   # S9-07/S9-08: «до» — кишлак без учёта ручья и реки у посёлка (vis_<имя>_dry.png)
			AdobeBuild.ignore_water = true
			_suffix += "_dry"
		if a == "--boxhouses":   # VIS-01: «до» — дома кишлака коробками, а не моделями (vis_<имя>_box.png)
			AdobeBuild.model_houses = false
			_suffix += "_box"


func process(delta: float) -> void:
	if m.state == "levelup":   # тест 3.5-s8: игрок сбивает цели стенда и набирает уровень — карточка останавливала кадры
		m.choose_card(0)
	_t += delta / maxf(Engine.time_scale, 0.01)
	if OS.get_cmdline_user_args().has("--hangarbench"):
		_hangar_bench()
		return
	if OS.get_cmdline_user_args().has("--menushot"):
		_menu_shot()
		return
	if OS.get_cmdline_user_args().has("--levbench"):
		_lev_bench(delta)
		return
	if m.state == "menu" and _i < 0 and _t > 1.0:
		var cls := "fighter"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--cls="):   # 3.5: кадры боя другим классом (3D-модели в бою)
				cls = a.substr(6)
				_suffix += "_" + cls
			if a.begins_with("--op="):   # S10-06: район стенда по операции (--op=5 — «Архипелаг»), а не последняя из campaign.cfg
				Campaign.debug_open_all()
				Campaign.select(clampi(int(a.substr(5)) - 1, 0, Campaign.OPS.size() - 1))
		m.select_class(cls)
		_t = 0.0
		return
	if m.state != "playing" or not is_instance_valid(m.player):
		return
	m.god_mode = true
	m.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	var cur: Dictionary = _points[_i] if _i >= 0 and _i < _points.size() else {}
	var keep: bool = cur.get("enemies", false) or cur.get("convoy", false) or cur.has("live") or cur.has("sam_poses") or cur.has("unit_poses")   # M-36: машины колонны — тоже враги
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
	if p.has("live"):
		_live(p)
		return
	if p.get("fort_area", false):
		# FA-01: the «Укрепрайон» base on the map fort — launchers raised, nothing breaks. Wait for Render3D's
		# place filter: before it, chunk_object gives the raw spot, not where the 3D fort stands (off the river)
		if not _fa_spawned and m.background.place_filter.is_valid():
			_fa_spawned = true
			var fp: Vector2 = p["fort"]
			var f := FortArea.pick_fort(FortArea.forts_near(m.background, fp, 900.0), fp, 900.0)
			if not f.is_empty():
				_fa_fort = f
				var base := FortArea.new()
				base.setup_fort(f, 1.0)
				for g in base.targets:
					g.hp = 99999.0
					g.max_hp = 99999.0
				base.active = true
				m.world.add_child(base)
				_fa_base = base
		if p.has("fort_break") and not p.get("_broke", false) and _fa_base != null:
			p["_broke"] = true
			_fort_break(p["fort_break"])
		if not _fa_fort.is_empty():   # the camera on the 3D fort (pushed off the river), not the raw chunk spot
			var at: Vector2 = _fa_fort["pos"]
			if p.has("on_piece"):   # FA-03: a broken piece close up
				var sp := FortArea.piece_spot(p["on_piece"])
				at = FortArea.fort_point(_fa_fort, Vector2(sp.x, sp.z))
			elif p.get("on_tower", false):
				at = FortArea.tower_points(_fa_fort)[3]
			p["pos"] = at + (p.get("off", Vector2.ZERO) as Vector2)
	elif p.get("ground", false):
		if not _g_spawned:
			_g_spawned = true
			var site := AASite.new()
			if p.has("site_off"):   # M-37: позиция ПВО рядом с колонной на дороге (камера остаётся на точке)
				var at: Vector2 = (p["pos"] as Vector2) + (p["site_off"] as Vector2)
				site.setup(at, 1.0)
				site.bunker.hp = 99999.0   # стенд: бункер не должен разбиться
				site.bunker.max_hp = 99999.0
				# Kanta 24.10: the site stands where the game puts it (off the river), not moved onto the road
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
			_fort.position = (p["pos"] as Vector2) + (p.get("fort_off", Vector2(0, -40)) as Vector2)
			_fort.process_mode = Node.PROCESS_MODE_DISABLED
			_fort.base_pos = _fort.position + Vector2.from_angle(_fort.heading) * 1400.0   # FB-01: маршрут к базе на кадре
			_fort._wp = _fort.base_pos
			m.world.add_child(_fort)
		_fort.hp = _fort.max_hp   # игрок стреляет: без своей логики «Крепость» не гасит вспышку попадания
		# S11-29 (point "fort_hit"): as under steady fire in a fight, the hit flash stays on every frame
		_fort._flash = 0.06 if p.get("fort_hit", false) else 0.0
		var ph: int = p["fortress"]
		_fort.phase = ph
		_fort.hatches_open = ph >= 2
		_fort.hull_open = ph >= 3
		_fort.parts_down = {}
		for nm in (["turret_1", "turret_2", "turret_3", "turret_4"] if ph >= 2 else []) + (["engine_l", "engine_r"] if ph >= 3 else []):
			_fort.parts_down[nm] = true
		# its logic is off, so nothing redraws it: without this the point rings stay where the first draw put them,
		# before the 3D model existed (Fortress._ring_at fallback), off the turrets on the wings
		_fort.queue_redraw()
	elif p.has("sam_poses"):
		_sam_poses(p)
	elif p.has("unit_poses"):
		_unit_poses(p)
	elif p.get("heli", false):
		if _heli == null:   # S9-22: «Сарыч» висит рядом с игроком, логика стоит (винты крутит render3d)
			_spawned = true
			_heli = Helicopter.new()
			_heli.position = (p["pos"] as Vector2) + Vector2(-120, 90)   # за хвостом игрока: пушки не попадают
			_heli.heading = -0.6
			_heli.process_mode = Node.PROCESS_MODE_DISABLED
			m.world.add_child(_heli)
			m.player.process_mode = Node.PROCESS_MODE_DISABLED   # не стреляет: дым попаданий не закрывает винт
		_heli.max_hp = 99999.0
		_heli.hp = 99999.0
		_heli._flash = 0.0
	elif p.get("enemies", false) and (not _spawned or m.get_tree().get_nodes_in_group("enemies").is_empty()):   # смена класса в начале точки очищает мир
		_spawn_all_enemies(p["pos"])   # точка, а не игрок: в первый кадр игрок ещё не перенесён
	if p.get("convoy", false):
		if _convoy == null:
			_convoy = Convoy.new()
			_convoy.setup(p.get("convoy_at", p["pos"]), Vector2.RIGHT, 1.0, 0.0, 0.0)
			m.world.add_child(_convoy)
			_convoy.process_mode = Node.PROCESS_MODE_DISABLED
		if _pt > 0.3 and not p.has("_done"):   # машины уже в мире — ставим подряд по дороге у точки и останавливаем
			p["_done"] = true
			var s0: float = _convoy._s_of(p.get("convoy_at", p["pos"]))
			var at := s0
			for v: ConvoyVehicle in _convoy.vehicles:   # середина колонны — у точки
				at += (float(ConvoyVehicle.SPEC[v.role]["len"]) * Tuning.g("unit_scale") + ConvoyVehicle.GAP) * 0.5
			for v: ConvoyVehicle in _convoy.vehicles:
				v.process_mode = Node.PROCESS_MODE_DISABLED
				v.place(at)
				at -= float(ConvoyVehicle.SPEC[v.role]["len"]) * Tuning.g("unit_scale") + ConvoyVehicle.GAP
		for v: ConvoyVehicle in _convoy.vehicles:
			v.process_mode = Node.PROCESS_MODE_DISABLED
		if p.get("smoke", false) and p.has("_done"):   # тест 3.5-s8: дымовая завеса БМП над колонной (как при тревоге)
			var first := _convoy.smoke_t <= 0.0
			_convoy.smoke_t = Convoy.SMOKE_TIME - minf(_pt, 3.0)
			_convoy.smoke_c = _convoy.point_at(_convoy.middle_s())
			_convoy.smoke_fx(delta, first)
			_convoy.queue_redraw()
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


## VIS-01 review: a camera of its own at `ground_dist` world px from the ground straight below the point,
## at the same tilt. The game camera stands over the combat plane, ground_depth above the ground, so a high
## zoom brings the ground only about twice closer; houses, palms and rocks need a real close-up.
var _gcam: Camera3D = null


func _ground_cam(p: Dictionary) -> void:
	var r3 := Render3D.I
	if r3 == null or r3.cam == null:
		return
	if not p.has("ground_dist"):
		if _gcam != null and _gcam.current:
			r3.cam.current = true
		return
	if _gcam == null:
		_gcam = Camera3D.new()
		_gcam.fov = Render3D.FOV
		_gcam.near = 2.0
		_gcam.far = 9000.0
		_gcam.keep_aspect = Camera3D.KEEP_HEIGHT
		_gcam.cull_mask = r3.cam.cull_mask
		r3.add_child(_gcam)
	var at: Vector2 = p.get("ground_at", p["pos"])
	if not p.has("ground_at"):   # the frame point's own spot: _hold moves pos with the game camera
		p["ground_at"] = at
	var g := Vector3(at.x, r3.terrain.surface_fast(at.x, at.y).y if r3.terrain != null else r3.GROUND_Y, at.y)
	var tilt := deg_to_rad(Tuning.g("cam_tilt"))
	_gcam.global_position = g + Vector3(0.0, cos(tilt), sin(tilt)) * float(p["ground_dist"])
	_gcam.basis = Basis.looking_at(Vector3(0, -cos(tilt), -sin(tilt)), Vector3(0, 0, -1))
	_gcam.current = true
	var pu: Unit3D = r3._units.get(m.player.get_instance_id())   # the plane flies in the combat plane above
	if pu != null:
		(pu.node as Node3D).visible = false
		if pu.sh != null:
			(pu.sh as Node3D).visible = false


func _hold(p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var dt := m.get_process_delta_time()
	_pt += dt
	_ground_cam(p)
	if p.has("cls"):   # 3.4-t1 п. 9, 19: другой самолёт (винты «Кита 1», сопла)
		m.player.cls_id = p["cls"][0]
		m.player.plane_lvl = p["cls"][1]
	if OS.get_cmdline_user_args().has("--holdfire"):   # PG-01: missiles stay on their rails for weapon close-ups
		for g: Hardpoint in m.player.groups:
			if g.weapon in Hardpoint.MISSILES:
				g.cd = 0.29   # above zero — no launch; below 0.3 — render3d still shows it
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
	if p.get("aim", false):
		for g in m.player.groups:
			var h: Hardpoint = g
			if h.weapon == "bombs" or (h.is_empty() and not h.builtin and not m.player.groups.any(func(x): return (x as Hardpoint).weapon == "bombs")):
				h.weapon = "bombs"
				h.level = maxi(h.level, 3)
				h.trigger = "button"
		Input.action_press("fire_hardpoint")
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
		# бомбы всех калибров (1–5 и «ковёр», тест 3.5-s8) с долгим взрывателем — на кадре видно падение
		var vt := (int(_pt * 10.0) % WeaponModels.BOMB_EVO_VT) + 1
		var to := pos + Vector2.from_angle(m.player.heading + randf_range(-0.5, 0.5)) * randf_range(420.0, 600.0)
		m.projectiles.spawn_bomb(pos + Vector2(randf_range(-20, 20), randf_range(-20, 20)), randf_range(4.0, 7.0), 0.0, 120.0, "бомбы", to, true)
		m.projectiles.bombs[-1]["vt"] = vt
	if p.has("skill_carpet") and _t > float(p["skill_carpet"]) and not p.has("_sk"):
		# Kanta 20.10 (BM-01): умение «Огненный ковёр» — метки падения бомб должны лежать на земле
		p["_sk"] = true
		m.player._carpet_left = 14
		m.player._carpet_i = 0
		m.player._carpet_tick = 0.0
		m.player._carpet_dir = 1.0
		Engine.time_scale = 0.03   # в облаке кадр идёт ~1 с, а спираль ложится за секунду
	if p.has("_sk") and m.player._carpet_left <= 6:
		Engine.time_scale = 1.0
		_save(p["name"])
		m.projectiles.bombs.clear()
		_phase = 0
		_t = 0.0
		_pt = 0.0
		_i += 1
		return
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
	var zk := 1.0
	for a in OS.get_cmdline_user_args():   # PG-01: --zoomk=2.5 — every point closer (weapon close-ups)
		if a.begins_with("--zoomk="):
			zk = float(a.get_slice("=", 1))
	m.camera.zoom = Vector2.ONE * float(p.get("zoom", 1.0)) * zk
	m.camera.reset_smoothing()


func _save(name: String) -> void:
	if _i >= 0 and _i < _points.size():   # relief lab: where the frame is, to reshoot it with --pts=
		print("VISUAL point %s at %s" % [name, str(_points[_i]["pos"])])
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
	if _i >= 0 and _i < _points.size() and _points[_i].get("sizes", false):
		_print_sizes(name)
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


## Size bench (--sizebench): the camera and the player sit this far from the convoy's road point,
## and the Fortress this far from the player, so that none of the three covers another
const SIZE_PLAYER_OFF := Vector2(280, 120)
const SIZE_FORT_OFF := Vector2(-560, -330)
## Size bench at the ground fort: the player (and camera) sits this far south of the fort's centre (y)
## and this far east of the road there (x)
const SIZE_FORT_PLAYER_OFF := Vector2(100, 350)


## Size bench: prints the on-screen length (frame pixels, nose to tail through the 3D camera,
## perspective included) of the player plane, every convoy vehicle and the Fortress
func _print_sizes(name: String) -> void:
	var r3 := Render3D.I
	if r3 == null:
		return
	var rows: Array = [["player", m.player]]
	if _convoy != null:
		for v: ConvoyVehicle in _convoy.vehicles:
			rows.append([v.role, v])
	if _fort != null:
		rows.append(["fortress", _fort])
	var img_w := float(m.get_viewport().get_texture().get_width())
	var px_k := img_w / maxf(r3.cam.get_viewport().get_visible_rect().size.x, 1.0)
	for row: Array in rows:
		var u: Unit3D = r3._units.get((row[1] as Node).get_instance_id())
		if u == null:
			print("VISUAL %s size %s: no 3D unit" % [name, row[0]])
			continue
		var root: Node3D = u.node
		var inv := root.global_transform.affine_inverse()
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var c := box.get_center()
		var a2 := r3.cam.unproject_position(root.global_transform * Vector3(box.position.x, c.y, c.z))
		var b2 := r3.cam.unproject_position(root.global_transform * Vector3(box.end.x, c.y, c.z))
		print("VISUAL %s size %s: %.0f px on screen (model %s)" % [name, row[0], a2.distance_to(b2) * px_k,
			"GLB" if u.bm != null else "relief"])
	var fp: Variant = _points[_i].get("fort_obj")
	if fp != null:
		_print_fort_size(name, fp as Vector2, px_k)


## Size bench: on-screen and world length of the side of the ground fort (Highland o_fort) whose
## centre is at fp — the 3D building render3d placed for that chunk object, not the boss bomber
func _print_fort_size(name: String, fp: Vector2, px_k: float) -> void:
	var r3 := Render3D.I
	for mi: Node in r3._objs.values():
		if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh not in [FortBuild.mesh(), FortBuild.base()]:
			continue
		var n3 := mi as MeshInstance3D
		if Vector2(n3.global_position.x, n3.global_position.z).distance_to(fp) > 5.0:
			continue
		var box := n3.mesh.get_aabb()
		var c := box.get_center()
		var a2 := r3.cam.unproject_position(n3.global_transform * Vector3(box.position.x, 0.0, c.z))
		var b2 := r3.cam.unproject_position(n3.global_transform * Vector3(box.end.x, 0.0, c.z))
		print("VISUAL %s size o_fort side: %.0f px on screen, %.0f world px (object size %.0f)" % [name,
			a2.distance_to(b2) * px_k, box.size.x * n3.basis.get_scale().x, n3.basis.get_scale().x])
		return
	print("VISUAL %s size o_fort: no 3D fort at %s" % [name, fp])


## Точки: пустыня, гора, кишлак, оазис, бой со взрывами, крупный план самолёта
func _make_points() -> Array:
	var bg := m.background
	var found := {}
	var placed := []   # VIS-01 review: every object, to pick a rock group away from settlements
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
					placed.append(o)
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
		pts.append({"name": "road_smoke", "pos": ter._field_point(empty + Vector2(0, 700), Terrain3D.D_ROAD), "zoom": 1.0, "convoy": true, "smoke": true, "wait": 3.0})
		# M-37: позиция ПВО целиком и рядом с колонной (размеры ПВО относительно машин конвоя)
		pts.append({"name": "aa_site", "pos": empty, "zoom": 1.0, "enemies": true, "ground": true, "wait": 2.5})
		pts.append({"name": "aa_convoy", "pos": ter._field_point(empty + Vector2(0, 700), Terrain3D.D_ROAD), "zoom": 1.3, "convoy": true, "enemies": true, "ground": true, "site_off": Vector2(-380, -40), "wait": 2.5})
	for k in [["village", "o_village"], ["oasis", "o_oasis"], ["fort", "o_fort"]]:
		pts.append({"name": k[0], "pos": found.get(k[1], empty + Vector2(4000, 0))})
	if found.has("o_oasis"):   # VIS-01: the oasis palms and well close up (south of it: the tilted camera looks north)
		pts.append({"name": "oasis_close", "pos": found["o_oasis"] + Vector2(0, 600), "zoom": 2.4})
		# VIS-01 review (26.10): the palm clumps and the well filling the frame
		pts.append({"name": "oasis_palms", "pos": found["o_oasis"], "ground_dist": 260.0, "wait": 3.0})
	# VIS-01 review: a big rock group (outcrop, boulders, spires) up close, the one farthest from any settlement
	var rk := [-1.0, Vector2.INF]
	for o: Dictionary in placed:
		if o["name"] != "o_rocks_big":
			continue
		var gap := INF
		for q: Dictionary in placed:
			if q["name"] in ["o_village", "o_oasis", "o_fort", "o_mesa"]:
				gap = minf(gap, (o["pos"] as Vector2).distance_to(q["pos"]) - float(q["size"]))
		if gap > rk[0]:
			rk = [gap, o["pos"]]
	if rk[1] != Vector2.INF:
		pts.append({"name": "rocks_group", "pos": rk[1], "ground_dist": 180.0, "wait": 3.0})
	if found.has("o_fort"):   # FA-01: the fortified-area base — whole fort and a tower launcher close up
		pts.append({"name": "fort_area", "pos": found["o_fort"] + Vector2(0, 300), "off": Vector2(0, 300), "fort": found["o_fort"], "fort_area": true, "enemies": true, "zoom": 1.0, "wait": 3.0})
		pts.append({"name": "fort_area_close", "pos": found["o_fort"], "off": Vector2(0, 60), "fort": found["o_fort"], "fort_area": true, "enemies": true, "zoom": 2.4, "wait": 2.0})
		# FA-02: the tower, its launcher, sandbags and the wall textures up close
		pts.append({"name": "fort_area_tower", "pos": found["o_fort"], "off": Vector2(-60, 40), "on_tower": true, "fort": found["o_fort"], "fort_area": true, "enemies": true, "zoom": 6.0, "wait": 2.0})
		# FA-03: mid-fight (one crown collapsed, one cracked, a breach) and the fort taken (all crowns, gate, store)
		var fa := {"fort": found["o_fort"], "fort_area": true, "enemies": true}
		pts.append(fa.merged({"name": "fort_area_hit", "pos": found["o_fort"], "off": Vector2(0, 60), "zoom": 2.4, "wait": 2.5,
			"fort_break": {"t3": 0.0, "t1": 0.4, "w5": 1}}))
		pts.append(fa.merged({"name": "fort_area_hit_tower", "pos": found["o_fort"], "off": Vector2(-60, 40), "on_piece": "t3", "zoom": 6.0, "wait": 1.5}))
		pts.append(fa.merged({"name": "fort_area_hit_breach", "pos": found["o_fort"], "off": Vector2(40, 30), "on_piece": "w5", "zoom": 6.0, "wait": 1.5}))
		pts.append(fa.merged({"name": "fort_area_ruin", "pos": found["o_fort"], "off": Vector2(0, 60), "zoom": 2.4, "wait": 6.0,
			"fort_break": {"t0": 0.0, "t1": 0.0, "t2": 0.0, "w1": 1, "gate": 1, "store": 1, "citadel": 1}}))
		pts.append(fa.merged({"name": "fort_area_ruin_wide", "pos": found["o_fort"], "off": Vector2(0, 300), "zoom": 1.0, "wait": 1.5}))
		# FA-04: the taken fort's burning citadel, store and yard close up
		pts.append(fa.merged({"name": "fort_area_ruin_citadel", "pos": found["o_fort"], "off": Vector2(0, 40), "on_piece": "citadel", "zoom": 4.5, "wait": 1.5}))
		pts.append(fa.merged({"name": "fort_area_ruin_gate", "pos": found["o_fort"], "off": Vector2(0, 50), "on_piece": "gate", "zoom": 6.0, "wait": 1.5}))
	if found.has("o_village"):   # тест 3.5-s8: кишлак-городок общим планом и крупно (центр, базар)
		# с наклоном камеры земля в центре кадра — севернее игрока: точка южнее посёлка, чтобы он был в центре
		pts.append({"name": "village_wide", "pos": found["o_village"] + Vector2(0, 700), "zoom": 0.6})
		pts.append({"name": "village_close", "pos": found["o_village"] + Vector2(0, 600), "zoom": 2.4})
		pts.append({"name": "village_houses", "pos": found["o_village"] + Vector2(-150, 0), "ground_dist": 260.0, "wait": 3.0})   # VIS-01: house models up close
		# VIS-01: the village at gameplay height with the player's plane over it, to judge the houses' scale
		pts.append({"name": "village_play", "pos": found["o_village"] + Vector2(0, 450), "cls": ["fighter", 1], "zoom": 1.3, "wait": 1.5})
		# VIS-01: the market on the square up close (Kanta 26.10: tents in the centre of the kishlak)
		pts.append({"name": "village_market", "pos": found["o_village"], "ground_dist": 170.0, "wait": 3.0})
		for vr in 4:
			AdobeBuild._vcache.erase("village%d" % vr)
			var t0 := Time.get_ticks_usec()
			var vm := AdobeBuild.village(vr)
			var hm := AdobeBuild.village_homes(vr)
			print("VISUAL village%d mesh tris=%d build=%d ms %s house models tris=%d models=%d model draws=%d" % [vr, vm.surface_get_array_len(0) / 3, (Time.get_ticks_usec() - t0) / 1000, AdobeBuild._vcache.get("village%d_stats" % vr, {}), VillageHouses.tris(hm), hm.size(), VillageHouses.draws(hm)])
	# сцены прошедших боёв (Terrain3D.scenes): первая с самолётом и первая с танком — крупнее
	if ter != null:
		var got := {}
		for r in range(0, 10):   # тест 3.5-s8: дальше — чтобы нашлась сцена с упавшим самолётом
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
	if OS.get_cmdline_user_args().has("--altbench"):
		# Kanta 25.10 (flight altitude): the gameplay zoom over the plain, a ridge and an AA site with enemy
		# planes around the player and air and ground blasts mid-way, to judge how high the planes read
		pts = []
		var ab := [[Vector2(-330, 160), 18.0, false, ""], [Vector2(-120, 260), 130.0, false, "blast"],
			[Vector2(260, -120), 22.0, true, ""], [Vector2(340, 200), 12.0, true, "flak"]]
		pts.append({"name": "alt_plain", "pos": empty, "enemies": true, "booms": ab, "shot_t": 0.6, "wait": 1.5, "zoom": 1.0})
		pts.append({"name": "alt_ridge", "pos": peak + Vector2(0, 300), "enemies": true, "booms": ab, "shot_t": 0.6, "wait": 1.5, "zoom": 1.0})
		pts.append({"name": "alt_site", "pos": empty + Vector2(2400, 0), "enemies": true, "ground": true, "booms": ab, "shot_t": 0.6, "wait": 2.5, "zoom": 1.0})
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
	if OS.get_cmdline_user_args().has("--bombaim"):   # S9-26: прицел бомб «Кита» по кнопке — должен лежать на земле
		pts = []
		pts.append({"name": "bomb_aim", "pos": empty + Vector2(300, 300), "cls": ["bomber", 1], "aim": true, "wait": 1.5, "zoom": 1.0})
		pts.append({"name": "bomb_aim_hill", "pos": empty + Vector2(-900, 700), "cls": ["bomber", 1], "aim": true, "wait": 1.5, "zoom": 1.0})
	if OS.get_cmdline_user_args().has("--carpetskill"):   # BM-01: умение «Огненный ковёр» — метки бомб
		pts = []
		pts.append({"name": "carpet_skill", "pos": empty + Vector2(300, 300), "cls": ["bomber", 1], "skill_carpet": 2.5, "wait": 99.0, "zoom": 1.6})
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
	if OS.get_cmdline_user_args().has("--wakebench") and ter != null:
		# S10-07, S10-10: караван (у моря) или колонна на ходу — след на воде, затем подбитые суда и остовы
		var at := ter._river_point(empty if empty != Vector2.INF else Vector2.ZERO)
		if Biome.sea():
			pts = [{"name": "wake", "pos": at, "live": [[7.0, "shot", "wake_near", 1.4], [8.5, "shot", "wake_wide", 0.8],
				[9.0, "kill", 2], [11.0, "shot", "sink_start", 1.6], [13.0, "shot", "sink_mid", 1.6], [16.5, "shot", "sink_after", 1.6]]}]
		else:
			pts = [{"name": "wreck", "pos": at, "live": [[1.5, "kill", 2], [6.0, "shot", "wreck_land", 3.2], [9.0, "shot", "wreck_land_far", 1.6]]}]
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
	if OS.get_cmdline_user_args().has("--convoymtn") and ter != null:
		# S11 (Kanta 25.10): a column ordered over the mountains, where the road search near its point finds
		# nothing (a bomber patrol there gets no road: the first such point on a grid around the empty cell);
		# the camera sits where its route passes: on the road since the far road search, on the straight line
		# over the ridges before it
		pts = []
		var at := Vector2.INF
		var mid := Vector2.INF
		for k in 400:
			var q := empty + Vector2(k % 20 - 10, floori(k / 20.0) - 10) * 1500.0
			if absf(ter.river_field(q.x, q.y)) < 1500.0:
				continue
			var near := Convoy.new()
			near.patrol = true
			near._build_route(q, Vector2.RIGHT, ter)
			var none := not near.on_road
			near.free()
			if none:
				at = q
				break
		if at.is_finite():
			var probe := Convoy.new()
			probe._build_route(at, Vector2.RIGHT, ter)
			mid = probe.point_at(probe._s_of(probe._center_road))
			print("VISUAL convoy over the mountains at %s: on_road=%s route centre %s" % [at, probe.on_road, mid])
			probe.free()
		if at.is_finite():
			for zz in [["near", 1.3], ["far", 0.55]]:
				pts.append({"name": "cvm_%s" % zz[0], "pos": mid, "zoom": zz[1], "convoy": true, "convoy_at": at, "wait": 1.5})
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
		# S11-29: the Fortress close (turrets on the hull, paint) and under steady fire (hit flash every frame)
		pts.append({"name": "model_fortress_close", "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": 2.6, "enemies": true, "fortress": 1, "wait": 2.5})
		pts.append({"name": "model_fortress_hit", "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": 2.6, "enemies": true, "fortress": 1, "fort_hit": true, "wait": 2.5})
		pts.append({"name": "model_enemies", "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": 1.6, "enemies": true, "wait": 0.6})
		for ph in ["march", "track", "launch"]:   # Kanta 24.10: SAM launcher folded, raised and tracking, launching
			pts.append({"name": "sam_" + ph, "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": 9.0, "sam_poses": ph, "wait": 2.5})
		# VIS-01: each reworked enemy model alone and close, moving parts posed (turret turned, wheels steered)
		for k in UNIT_POSES:
			pts.append({"name": "unit_" + k, "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": UNIT_POSES[k][2], "unit_poses": k, "wait": 3.5})
		# S9-22: вертолёт «Сарыч» крупно — диск несущего винта над песком
		pts.append({"name": "model_heli", "pos": empty + Vector2(300, 300), "cls": ["fighter", 1], "zoom": 2.4, "enemies": true, "heli": true, "wait": 1.5})
	if OS.get_cmdline_user_args().has("--sizebench") and ter != null:
		# VIS-01 (Kanta 24.10): true sizes at the normal gameplay zoom — the player fighter, a whole
		# convoy on the road and the Fortress in one frame; the log prints their on-screen lengths
		pts = []
		var road := ter._field_point(empty + Vector2(0, 700), Terrain3D.D_ROAD)
		pts.append({"name": "size_trio", "pos": road + SIZE_PLAYER_OFF, "convoy": true, "convoy_at": road,
			"fortress": 1, "fort_off": SIZE_FORT_OFF, "cls": ["fighter", 1], "zoom": 1.0, "wait": 2.5,
			"sizes": true})
		# VIS-01 (Kanta 24.10): the same at the ground fort (Highland o_fort) — the fighter, the fort and
		# a convoy on the road past it; the log adds the fort side's on-screen length
		if found.has("o_fort"):
			var fp: Vector2 = found["o_fort"]
			var rd := ter._field_point(fp, Terrain3D.D_ROAD)
			print("VISUAL size_fort fort at ", fp, " road ", rd)
			# the tilted camera sees the ground north of the player: the player flies past the road south
			# of the fort, so a fort twice as big still fits in the frame
			var pp := ter._field_point(Vector2(rd.x, fp.y + SIZE_FORT_PLAYER_OFF.y), Terrain3D.D_ROAD) + Vector2(SIZE_FORT_PLAYER_OFF.x, 0)
			pts.append({"name": "size_fort", "pos": pp, "convoy": true, "convoy_at": rd,
				"fort_obj": fp, "cls": ["fighter", 1], "zoom": 1.0, "wait": 2.5, "sizes": true})
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pts="):   # relief lab: --pts=name:x:z:zoom,name2:x:z:zoom — arbitrary camera points
			pts = []
			for q in a.substr(6).split(","):
				var f := q.split(":")
				pts.append({"name": f[0], "pos": Vector2(float(f[1]), float(f[2])), "zoom": float(f[3]) if f.size() > 3 else 1.0, "wait": 1.2})
		if a.begins_with("--vat="):   # S9-07/S9-08: кишлак у протоки: --vat=x,z[,zoom] (координаты — tools/village_water)
			var v := a.substr(6).split(",")
			pts = [{"name": "village_water", "pos": Vector2(float(v[0]), float(v[1])), "zoom": float(v[2]) if v.size() > 2 else 1.0, "wait": 1.5}]
	return pts



## S10-07, S10-10 (--wakebench): живая колонна / караван у точки — идёт своим ходом, камера над серединой;
## по расписанию p["live"] = [[время, "shot", имя, зум] | [время, "kill", сколько]] — кадры и подбитые машины
var _live_cv: Convoy = null
var _live_t := 0.0
var _live_k := 0


func _live(p: Dictionary) -> void:
	if _live_cv == null:
		m.player.process_mode = Node.PROCESS_MODE_DISABLED   # не стреляет: кадр следа и остовов без дыма попаданий
		_live_cv = Convoy.new()
		_live_cv.setup(p["pos"], Vector2.RIGHT, 50.0, 0.0, 0.0)
		m.world.add_child(_live_cv)
		_live_t = 0.0
		_live_k = 0
		return
	_live_t += m.get_process_delta_time()
	if _live_t > 0.3 and not p.has("_placed"):   # машины уже в мире — ставим у точки, дальше едут сами
		p["_placed"] = true
		var at: float = _live_cv._s_of(p["pos"]) + 300.0
		for v: ConvoyVehicle in _live_cv.vehicles:
			v.place(at)
			at -= float(ConvoyVehicle.spec(v.role)["len"]) * Tuning.g("unit_scale") + ConvoyVehicle.gap()
	var vs: Array = _live_cv.vehicles.filter(func(v: Variant) -> bool: return is_instance_valid(v))
	var focus: Vector2 = p["pos"]
	if not vs.is_empty() and p.has("_placed"):
		focus = (vs[mini(2, vs.size() - 1)] as Node2D).global_position
		if p.has("_wreck") and is_instance_valid(p["_wreck"]):   # после подбития камера — над остовом
			focus = (p["_wreck"] as Node2D).global_position
	var seq: Array = p["live"]
	var zoom := 1.0
	for st: Array in seq:
		if st[1] == "shot":
			zoom = float(st[3])
			if _live_t < float(st[0]):
				break
	m.player.global_position = focus + Vector2(380, 260) / zoom
	m.player.heading = -PI / 4.0
	m.camera.global_position = focus
	m.camera.zoom = Vector2.ONE * zoom
	m.camera.reset_smoothing()
	if _live_k >= seq.size():
		_live_cv.queue_free()
		for v in vs:
			(v as Node).queue_free()
		_live_cv = null
		_i += 1
		_t = 0.0
		return
	var cur: Array = seq[_live_k]
	if _live_t < float(cur[0]):
		return
	_live_k += 1
	if cur[1] == "kill":   # подбить машины с середины колонны (не головную — колонна идёт дальше)
		var n := 0
		for v: ConvoyVehicle in vs:
			if v != vs[0] and not v.wreck and n < int(cur[2]):
				n += 1
				# как ConvoyVehicle._die, но без взрыва: его дым закрывает кадр остова
				v.hp = 0.0
				v.remove_from_group("enemies")
				v.wreck = true
				v.add_to_group("wrecks3d")
				if n == 1:
					p["_wreck"] = v
	else:
		_save(String(cur[2]))


## 3.5: враги всех видов рядом с игроком (стенд 3D-моделей в бою)
var _spawned := false
var _fort: Fortress = null
var _heli: Helicopter = null
var _sams: Array = []


## SAM launcher phases for review (Kanta 24.10): "march" (box folded, on the move), "track" (raised at a live
## site, turned to the player), "launch" (a missile leaves its cell, the box kicks). One launcher per point; its
## logic is frozen and Render3D animates the launcher from the fields set here.
func _sam_poses(p: Dictionary) -> void:
	if _pt < 0.3:   # the class switch at the start of a point clears the world
		return
	if not p.has("_sam"):   # a new point: drop the previous phase's launcher if the world kept it
		for g in _sams:
			if is_instance_valid(g):
				g.queue_free()
		_sams.clear()
	if not _sams.is_empty() and not is_instance_valid(_sams[0]):
		_sams.clear()
	var phase: String = p["sam_poses"]
	if _sams.is_empty():
		p["_sam"] = true
		var tr := Terrain3D.active()
		var at: Vector2 = tr.find_floor(p["pos"], 2600.0, 0.0, _clear_of(p["pos"], 3200.0), AASite.FLOOR_MID, true) if tr != null else p["pos"]
		p["pos"] = at + Vector2(-60, -48)   # the bench keeps the player and camera on the point
		_spawned = true
		m.player.process_mode = Node.PROCESS_MODE_DISABLED
		var site := AASite.new()
		site.active = phase != "march"
		var g := GroundTarget.new()
		g.setup("sam", site, 1.0)
		g.position = at
		g.anchor = at
		g._body_angle = 0.4
		if phase == "march":
			g._goal = at + Vector2(400, 0)
		g.process_mode = Node.PROCESS_MODE_DISABLED
		m.world.add_child(g)
		_sams.append(g)
	var sam: GroundTarget = _sams[0]
	var r3 := Render3D.I
	if r3 != null and r3.terrain != null:
		# the 3D camera looks ahead of the player, so steer the point until the launcher sits mid-frame
		var vs := m.get_viewport().get_visible_rect().size
		var scr := r3.cam.unproject_position(r3.terrain.surface_fast(sam.anchor.x, sam.anchor.y))
		var step := (scr - vs * Vector2(0.5, 0.55)) / (8.0 * float(p.get("zoom", 1.0)) / 9.0) * 0.5
		p["pos"] = Vector2(p["pos"]) + step.limit_length(20.0)   # small steps so the camera settles
		var pu: Unit3D = r3._units.get(m.player.get_instance_id())
		if pu != null:   # the plane would cover the launcher: hide its 3D model only
			(pu.node as Node3D).visible = false
			if pu.sh != null:
				(pu.sh as Node3D).visible = false
	sam.hp = maxf(sam.hp, sam.max_hp)   # the player's guns stay off it
	if sam.sprite_info().is_empty():   # frozen targets never run _draw, which is where Render3D gets its model
		sam._spr = {"tex": "e_sam", "len": 34.0, "angle": sam._body_angle}
	if phase == "launch" and _pt > float(p.get("wait", 2.0)) - 0.2 and sam.launches == 0 and sam.launch_at.is_finite():
		var to := m.player.global_position - sam.global_position
		m.projectiles.spawn_missile(sam.launch_at, to.normalized(), "sam", "ЗРК")
		sam.launches = 1
var _g_spawned := false
var _fa_spawned := false
var _fa_fort: Dictionary = {}   # FA-02: the fort the bench base stands on, for the camera points
var _fa_base: FortArea


## FA-03 bench: breaks pieces of the bench fort as a fight would. `b`: piece id → launcher HP share for towers
## ("t3": 0.0 collapses it, 0.4 — damaged), any value for walls, gate and store (blown) and "citadel" (the fort taken). Plays the same dust and smoke.
func _fort_break(b: Dictionary) -> void:
	for id: String in b:
		if id.begins_with("t"):
			var g := _fa_base.launchers[int(id.substr(1))]
			g.hp = g.max_hp * float(b[id])
		elif id == "citadel":   # the fort taken: citadel and trucks burn
			_fa_base.damage.take()
		else:
			var sp := FortArea.piece_spot(id)
			for got in _fa_base.damage.apply_blast(Vector2(sp.x, sp.z), 0.005, 9.0):
				_fa_base.break_fx(got)
	Events.fort_changed.emit(FortView.key_of(_fa_fort["pos"]))


## VIS-01 unit close-ups: kind -> [enemy texture, sprite length, camera zoom]. Lengths are the game's own
## (GroundTarget._draw, ConvoyVehicle.SPEC, Helicopter.LEN, Interceptor._draw); zoom brings each to ~40 % of the frame.
const UNIT_POSES := {
	"zsu": ["e_zsu", 27.0, 20.0], "truck": ["e_convoy_truck", 28.0, 20.0], "ifv": ["e_convoy_ifv", 25.0, 22.0],
	"scout": ["e_convoy_scout", 18.0, 28.0], "technical": ["e_convoy_technical", 14.0, 34.0],
	"heli": ["e_helicopter", 60.0, 9.0], "interceptor": ["e_interceptor", 46.0, 11.0],
	# S11-24: the strike drone plain and elite (the elite marking drew it flat yellow on Forward+)
	"drone": ["e_drone", 34.0, 14.0], "drone_elite": ["e_drone", 34.0, 12.0], "drone_hit": ["e_drone", 34.0, 14.0],
	# Kanta 25.10 enemy overview: every Highlands enemy alone and close (lengths from each script's sprite)
	"interceptor_elite": ["e_interceptor", 46.0, 9.5], "carrier": ["e_carrier", 60.0, 8.5],
	"carrier_elite": ["e_carrier", 60.0, 7.2], "bomber": ["e_bomber", 120.0, 4.2],
	"transport": ["e_transport", 190.0, 2.7], "rival": ["e_rival", 64.0, 8.0], "postman": ["e_postman", 92.0, 5.5],
	"draft": ["e_draft", 84.0, 6.0], "light": ["e_convoy_pickup_tent", 14.0, 34.0],
	"manpads": ["e_convoy_manpads", 14.0, 34.0], "radar": ["e_radar", 32.0, 15.0], "bunker": ["e_bunker", 59.0, 8.5],
	"sam": ["e_sam", 34.0, 14.0],
}
var _unit: Enemy = null
var _unit_cv: Convoy = null


## VIS-01 (Kanta 26.10: units stood on the fort walls): find_floor keeps only size * 0.6 + 50 off a map object,
## which is inside a fort's corner towers; every object within `reach` of `p`, as Background places it
## (river push applied), is kept a full size plus a margin away so a close-up shows the unit on open ground.
func _clear_of(p: Vector2, reach: float) -> Array:
	var out := []
	var ch := Background.CHUNK
	var r := int(ceil(reach / ch)) + 1
	var c := Vector2i(floori(p.x / ch), floori(p.y / ch))
	for cx in range(c.x - r, c.x + r + 1):
		for cy in range(c.y - r, c.y + r + 1):
			var o := m.background.chunk_object(cx, cy)
			if not o.is_empty():
				out.append([o["pos"], float(o["size"]) + 250.0])
	return out


## VIS-01: one enemy model alone and centred, logic frozen, the player's plane hidden (as _sam_poses).
## Ground units get their moving parts posed through the same fields Render3D reads in a battle: the turret
## turns off the hull (ZSU: sprite angle ~65° after the first second; convoy: alarm on, so it aims at the
## player, who stays on the camera point off the vehicle's quarter),
## convoy wheels have rolled and the front axles steer. The camera steers until the 3D model sits mid-frame.
func _unit_poses(p: Dictionary) -> void:
	if _pt < 0.3:   # the class switch at the start of a point clears the world
		return
	var kind: String = p["unit_poses"]
	if not p.has("_unit"):   # a new point: only this unit in the world (earlier points keep their enemies)
		p["_unit"] = true
		for e in m.get_tree().get_nodes_in_group("enemies"):
			(e as Node).queue_free()
		m.projectiles.missiles.clear()
		m.projectiles.ebullets.clear()
		_unit = null
	if _unit != null and not is_instance_valid(_unit):
		_unit = null
	var spec: Array = UNIT_POSES[kind]
	var body := 0.4
	if _unit == null:
		var tr := Terrain3D.active()
		var at: Vector2 = tr.find_floor(p["pos"], 2600.0, 0.0, _clear_of(p["pos"], 3200.0), AASite.FLOOR_MID, true) if tr != null else p["pos"]
		p["pos"] = at + Vector2(-60, -48)
		_spawned = true
		m.player.process_mode = Node.PROCESS_MODE_DISABLED
		match kind:
			"zsu", "radar", "bunker", "sam":
				var g := GroundTarget.new()
				g.setup(kind, AASite.new(), 1.0)
				g.position = at
				g.anchor = at
				g._body_angle = body
				_unit = g
			"heli":
				_unit = Helicopter.new()
			"interceptor", "interceptor_elite":
				_unit = Interceptor.new()
			"carrier", "carrier_elite":
				_unit = MissileCarrier.new()
			"bomber":
				_unit = Bomber.new()
			"transport":
				var tp := Transport.new()
				tp.setup(99999.0)
				_unit = tp
			"rival":
				_unit = RivalAce.new()
			"postman", "draft":
				var b := Boss.new()
				b.setup("carrier" if kind == "postman" else "interceptor", 99999.0)
				_unit = b
			"drone", "drone_elite", "drone_hit":
				_unit = Drone.new()
			_:
				if _unit_cv == null:
					_unit_cv = Convoy.new()   # never enters the tree: only carries the alarm flag the turret reads
					_unit_cv.alarm = true
				var v := ConvoyVehicle.new()
				v.setup(kind, _unit_cv, 99999.0)
				v.drive = GroundDrive.new(at, body)
				v.drive.dist = 40.0     # wheels rolled off their modelled pose
				v.drive.steer = 0.6     # front axles turned
				v.anchor = at
				v.heading = body
				v.position = at
				_unit = v
		if not (_unit is GroundTarget or _unit is ConvoyVehicle):
			_unit.position = at
			_unit.heading = body
		_unit.process_mode = Node.PROCESS_MODE_DISABLED
		m.world.add_child(_unit)
		if _unit is RivalAce:
			(_unit as RivalAce).setup(99999.0)
		if kind.ends_with("_elite"):
			_unit.make_elite()
	var aim := body + (1.15 if _pt > 1.0 else 0.0)
	_unit.hp = maxf(_unit.hp, 99999.0)
	_unit.max_hp = maxf(_unit.max_hp, 99999.0)
	_unit._flash = 0.06 if kind == "drone_hit" else 0.0   # S11-24: drone_hit shows the hit flash
	_unit._spr = {"tex": spec[0], "len": spec[1], "angle": aim if kind == "zsu" else body}
	var r3 := Render3D.I
	if r3 == null:
		return
	var u: Unit3D = r3._units.get(_unit.get_instance_id())
	if u != null:
		var vs := m.get_viewport().get_visible_rect().size
		var scr := r3.cam.unproject_position((u.node as Node3D).global_position)
		var step := (scr - vs * Vector2(0.5, 0.5)) / (8.0 * float(p.get("zoom", 1.0)) / 9.0) * 2.0
		p["pos"] = Vector2(p["pos"]) + step.limit_length(200.0)   # software GL in the cloud runs a few frames a second
	var pu: Unit3D = r3._units.get(m.player.get_instance_id())
	if pu != null:
		(pu.node as Node3D).visible = false
		if pu.sh != null:
			(pu.sh as Node3D).visible = false


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


## S11 close-up views from the command line: --hcam=name:cls:lvl:tier:livery:fx:fy:fz:yaw:pitch:dist[;…]
## (livery "-" keeps the profile's paint; focus in model units, plane length 1) → user://vis_hcam_<name><suffix>.png
var _hcams: Array = []


var _hc_frame := 0   # --hcamframes: frame of the current view


## --hcamframes=N: each --hcam view saves N consecutive frames instead of one (a clip of the animated hangar).
func _hcam_frames() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hcamframes="):
			return int(a.get_slice("=", 1))
	return 0


func _hcam() -> Array:
	if _hcams.is_empty():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--hcam="):
				for e in a.get_slice("=", 1).split(";", false):
					var f := e.split(":")
					if f.size() == 11:
						_hcams.append(Array(f))
	return _hcams


## Тест 3.5-s8 (--mechanim): ракурсы показа механизации [фокус, рысканье, тангаж, дальность] по классам
const MECH_FRAMES := 8
const MECH_DT := 0.75   # с между кадрами: 8 кадров = полный цикл HangarAnim (6 с)
const _MECH_VIEWS := {
	# сзади сбоку чуть сверху: закрылки уходят вниз за заднюю кромку — сверху их не видно
	"fighter": [[Vector3(-0.1, -0.01, 0.0), 2.8, 0.16, 1.0]],
	"attacker": [[Vector3(-0.08, 0.0, 0.0), 2.75, 0.22, 1.05]],
	"bomber": [[Vector3(-0.08, 0.0, 0.0), 2.75, 0.2, 1.1], [Vector3(0.0, -0.03, 0.0), 2.0, -0.6, 1.0]],
}


## S11-02/08/10/11/12 (--mechclose): large close-ups of every plane's wing mechanisation and the «Kit» bomb bay,
## each view twice: flaps up with the bay closed (pose 0) and flaps down with the bay open (pose 1).
## [focus, yaw, pitch, distance] in hangar axes (nose +X, up +Y, left wing -Z); "bay" only on the bombers
var _mc_last := ""   # --mechclose: plane of the previous frame
const _MECHCLOSE := {
	"fighter_1": {"low34": [Vector3(-0.24, -0.02, -0.14), PI + 0.55, -0.4, 0.34], "side": [Vector3(-0.24, -0.02, -0.14), -PI / 2.0 - 0.55, -0.05, 0.4],
		"top34": [Vector3(-0.24, -0.02, -0.14), PI + 0.55, 0.55, 0.34]},
	"fighter_2": {"low34": [Vector3(-0.2, -0.03, -0.27), PI + 0.55, -0.4, 0.36], "side": [Vector3(-0.2, -0.03, -0.27), -PI / 2.0 - 0.55, -0.05, 0.42],
		"top34": [Vector3(-0.2, -0.03, -0.27), PI + 0.55, 0.55, 0.36]},
	"attacker_1": {"low34": [Vector3(-0.12, -0.06, -0.24), PI + 0.55, -0.4, 0.38], "side": [Vector3(-0.12, -0.06, -0.24), -PI / 2.0 - 0.55, -0.05, 0.46],
		"top34": [Vector3(-0.12, -0.06, -0.24), PI + 0.55, 0.55, 0.38]},
	"attacker_2": {"low34": [Vector3(-0.16, -0.06, -0.25), PI + 0.55, -0.4, 0.38], "side": [Vector3(-0.16, -0.06, -0.25), -PI / 2.0 - 0.55, -0.05, 0.46],
		"top34": [Vector3(-0.16, -0.06, -0.25), PI + 0.55, 0.55, 0.38]},
	"bomber_1": {"low34": [Vector3(-0.08, -0.07, -0.3), PI + 0.55, -0.4, 0.42], "side": [Vector3(-0.08, -0.07, -0.3), -PI / 2.0 - 0.55, -0.05, 0.5],
		"top34": [Vector3(-0.08, -0.07, -0.3), PI + 0.55, 0.55, 0.42], "bay": [Vector3(-0.01, -0.08, 0.0), -PI / 2.0 + 0.45, -0.55, 0.38]},
	"bomber_2": {"low34": [Vector3(-0.17, -0.03, -0.27), PI + 0.55, -0.4, 0.42], "side": [Vector3(-0.17, -0.03, -0.27), -PI / 2.0 - 0.55, -0.05, 0.5],
		"top34": [Vector3(-0.17, -0.03, -0.27), PI + 0.55, 0.55, 0.42], "bay": [Vector3(-0.16, -0.05, 0.0), -PI / 2.0 + 0.45, -0.55, 0.38]},
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
		if not _hcam().is_empty():
			# S11: free close-ups of the hangar plane, one queue entry per --hcam view, rendered large
			Hangar3D.bench_supersample = 2.5
			for vi in _hcam().size():
				var hv: Array = _hcam()[vi]
				_hq.append([hv[1], int(hv[2]), int(hv[3]), "C", hv[4], vi])
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
		if OS.get_cmdline_user_args().has("--mechclose"):
			for key: String in _MECHCLOSE:
				for view: String in _MECHCLOSE[key]:
					for pose in [0, 1]:
						_hq.append([key.get_slice("_", 0), int(key.get_slice("_", 1)), 3 if key.begins_with("bomber") else 1, "K", view, pose])
			_t = 0.0
			return
		if OS.get_cmdline_user_args().has("--hangarweaptab"):
			# тест 3.5-s3: вкладка «ОРУЖИЕ» — каждое оружие объёмной моделью, ступени 1 / 3 / 5 и модернизация
			var wl := ["aam", "rockets", "bombs", "flares", "turret"]
			for a in OS.get_cmdline_user_args():   # --weaplist=bombs,flares — только эти виды
				if a.begins_with("--weaplist="):
					wl = Array(a.get_slice("=", 1).split(","))
			for w in wl:
				for wt in ([1, 2, 3] if not Profile.WBRANCH.has(w) else [1, 2, 3, 4]):   # PG-01: no modernization yet
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
		if OS.get_cmdline_user_args().has("--hangarnew"):
			# PG-01: the new standard weapons on each plane, tiers 1 / 2 / 3 (hangar models)
			Hangar3D.bench_weapons = {"fighter": ["srm", ""], "attacker": ["srm", "agm"], "bomber": ["hebomb", ""]}
			for c in PlaneClasses.LIST:
				for wt in [1, 2, 3]:
					_hq.append([c, 1, wt])
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
		for a in OS.get_cmdline_user_args():   # --wcls=bomber: the weapon store of that class (its turret)
			if a.begins_with("--wcls="):
				m.hangar_cls = a.get_slice("=", 1)
		m.hangar_w = cur[1]
		Hangar3D.bench_tab_w = cur[1]
		var wcam := ""
		if Hangar3D.I != null:
			Hangar3D.I.weapon_tier = cur[2]
			Hangar3D.I._idle = 0.0
			for a in OS.get_cmdline_user_args():   # --wcam=yaw,pitch,dist: close-up of the weapon on its stand
				if a.begins_with("--wcam="):
					var cv := a.get_slice("=", 1).split(",")
					Hangar3D.I._yaw = float(cv[0])
					Hangar3D.I._pitch = float(cv[1])
					Hangar3D.I._dist = float(cv[2])
					wcam = "_cam"
		_hf += 1
		if _hf > 8 and _t > 1.2:
			_save("hangar_w_%s_%d%s" % [cur[1], cur[2], wcam])
			if Hangar3D.I != null:   # S11-13: the weapon view alone, at its own resolution (close-up frames)
				Hangar3D.I.vp.get_texture().get_image().save_png("user://vis_hangar_wvp_%s_%s_%d%s%s.png" % [
					m.hangar_cls, cur[1], cur[2], wcam, _suffix])
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
		if cur.size() > 5 and typeof(cur[3]) == TYPE_STRING and cur[3] == "K":   # --mechclose
			var cv: Array = _MECHCLOSE["%s_%d" % [cur[0], cur[1]]][cur[4]]
			HangarAnim.bench_pose = float(cur[5])
			Hangar3D.anim_time = 0.0
			Hangar3D.bench_pitch_min = -0.9
			Hangar3D.I.focus = cv[0]
			Hangar3D.I._yaw = cv[1]
			Hangar3D.I._pitch = cv[2]
			Hangar3D.I._dist = cv[3]
			Hangar3D.I._idle = 0.0
		elif cur.size() > 5 and typeof(cur[3]) == TYPE_STRING and cur[3] == "M":   # --mechanim
			var mv: Array = _MECH_VIEWS[cur[0]][cur[5]]
			Hangar3D.I.mech_demo = true
			Hangar3D.anim_time = float(cur[4]) * MECH_DT
			Hangar3D.bench_pitch_min = -0.9
			Hangar3D.I.focus = mv[0]
			Hangar3D.I._yaw = mv[1]
			Hangar3D.I._pitch = mv[2]
			Hangar3D.I._dist = mv[3]
			Hangar3D.I._idle = 0.0
		elif cur.size() > 5 and typeof(cur[3]) == TYPE_STRING and cur[3] == "C":   # --hcam close-up
			var cv: Array = _hcam()[cur[5]]
			if String(cv[4]) != "-":
				Profile.cls(cur[0])["livery"] = cv[4]
			Hangar3D.bench_pitch_min = -1.3
			Hangar3D.I.focus = Vector3(float(cv[5]), float(cv[6]), float(cv[7]))
			Hangar3D.I._yaw = float(cv[8])
			Hangar3D.I._pitch = float(cv[9])
			Hangar3D.I._dist = float(cv[10])
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
	var mech_next: bool = cur.size() > 5 and typeof(cur[3]) == TYPE_STRING and cur[3] == "M" and int(cur[4]) > 0   # модель уже собрана
	# --mechclose: the same plane as the previous frame is already built, only the camera and the pose change
	mech_next = mech_next or (cur.size() > 5 and typeof(cur[3]) == TYPE_STRING and cur[3] == "K" and _mc_last == "%s_%d" % [cur[0], cur[1]] and _hf > 2)
	if (_hf > 8 and _t > 1.2 and (cur.size() < 6 or typeof(cur[3]) != TYPE_STRING or _hf > 14)) or (mech_next and _hf > 2):   # в облаке (программная отрисовка) кадр идёт ~1 с — ждём кадры, а не секунды
		if cur.size() > 5 and typeof(cur[3]) == TYPE_STRING and cur[3] == "K":   # --mechclose
			Hangar3D.I.vp.get_texture().get_image().save_png("user://vis_mechclose_%s_%d_%s_p%d%s.png" % [cur[0], cur[1], cur[4], cur[5], _suffix])
			_mc_last = "%s_%d" % [cur[0], cur[1]]
		elif cur.size() > 5 and typeof(cur[3]) == TYPE_STRING and cur[3] == "C":
			# S11: only the 3D view (SubViewport, supersampled), so the close-up is not shrunk into the hangar frame
			var hn := "user://vis_hcam_%s%s.png" % [_hcam()[cur[5]][0], _suffix]
			if _hcam_frames() > 0:   # --hcamframes=N: N frames in a row for a clip (run with --fixed-fps)
				hn = "user://vis_hcam_%s%s_f%03d.png" % [_hcam()[cur[5]][0], _suffix, _hc_frame]
				Hangar3D.I.vp.get_texture().get_image().save_png(hn)
				_hc_frame += 1
				if _hc_frame < _hcam_frames():
					return
				_hc_frame = 0
			else:
				Hangar3D.I.vp.get_texture().get_image().save_png(hn)
			print("VISUAL hcam %s" % hn)
		elif cur.size() > 5 and typeof(cur[3]) == TYPE_STRING:
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
			# S11-13: the hangar view alone, at its own resolution (close-up frames)
			Hangar3D.I.vp.get_texture().get_image().save_png("user://vis_turretvp_%s_%d_w%d_v%d%s.png" % [
				cur[0], cur[1], cur[2], cur[3], _suffix])
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


# ---------- «Левиафан» крупно (-- --visual --levbench [--tilt=35]) ----------
# Операция «Левиафан», корабль подходит к игроку (бессмертие); кадры vis_lev_*.png: целый (общий план и нос),
# серия пуска ракет (время замедлено: в облаке кадр ~1 с), половина частей выбита, всё выбито.
var _lev: Warship = null
var _lev_step := 0
var _lev_t := 0.0
var _lev_n := 0
var _lev_launch := -1
var _lev_post := -1


func _lev_bench(delta: float) -> void:
	if m.state == "menu":
		if _t > 1.0 and _lev_step == 0:
			_lev_step = 1
			Campaign.debug_open_all()
			for i in Campaign.OPS.size():
				if Campaign.OPS[i]["id"] == "leviathan":
					Campaign.select(i)
			m.select_class("fighter")
		return
	if m.state != "playing" or not is_instance_valid(m.player):
		return
	m.god_mode = true
	m.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	if m.hud != null:
		m.hud.visible = false
	for e in m.get_tree().get_nodes_in_group("enemies"):
		if e != _lev:
			(e as Node).queue_free()
	if _lev == null or not is_instance_valid(_lev):
		_lev_t += delta
		if _lev_t > 1.0:
			_lev = Warship.new()
			_lev.setup_ship("leviathan", 1.0e7, m.player.global_position)
			m.world.add_child(_lev)
			_lev_t = 0.0
		return
	_lev_t += delta
	var c := _lev.global_position
	var fw := Vector2.from_angle(_lev.heading)
	var ln := 450.0 * Tuning.g("unit_scale")
	var cam := c
	var zoom := 1.0
	match _lev_step:
		1:
			if _lev_t > 4.0:
				_save("lev_full")
				_lev_step = 2
				_lev_t = 0.0
		2:
			cam = c + fw * ln * 0.25
			zoom = 2.4
			if _lev_t > 1.0:
				_save("lev_bow")
				_lev_step = 3
				_lev_t = 0.0
		3:
			cam = c + fw * ln * 0.21
			zoom = 4.5
			m.player.visible = false   # самолёт игрока не закрывает пусковые; вспышку попаданий гасим
			_lev._flash = 0.0
			# запускать с --fixed-fps 30: шаг времени ровный, кадр не «проскакивает» выход ракеты, пока сохраняется снимок
			if _lev_launch == -1 and _lev._sam_lock > 0.0:
				_lev_launch = _lev.fx_launch
				_lev_t = 0.0
			if _lev_launch != -1:
				var fired := _lev.fx_launch != _lev_launch
				if _lev_n == 0 and _lev_t > 0.15:   # крышки начали открываться
					_save("lev_launch_%02d" % _lev_n)
					_lev_n += 1
				elif _lev_n > 0 and (fired or _lev._sam_lock < 0.35):
					_lev_post += 1
					if _lev_post % 2 == 0:   # каждый второй кадр (1/15 с)
						_save("lev_launch_%02d" % _lev_n)
						_lev_n += 1
				if _lev_n > 24:
					Engine.time_scale = 1.0
					m.player.visible = true
					if OS.get_cmdline_user_args().has("--levlaunch"):   # только серия пуска
						print("VISUAL done")
						m.get_tree().quit()
					_lev.hp = _lev.max_hp * 0.5
					_lev_step = 4
					_lev_t = 0.0
		4:
			if _lev_t > 6.0:
				_save("lev_half")
				_lev_step = 5
				_lev_t = 0.0
		5:
			cam = c - fw * ln * 0.05
			zoom = 2.2
			if _lev_t > 1.0:
				_save("lev_half_close")
				_lev.hp = _lev.max_hp * 0.02
				_lev_step = 6
				_lev_t = 0.0
		6:
			if _lev_t > 6.0:
				_save("lev_broken")
				_lev_step = 7
				_lev_t = 0.0
		7:
			cam = c + fw * ln * 0.25
			zoom = 2.4
			if _lev_t > 1.0:
				_save("lev_broken_bow")
				_lev_step = 8
				_lev_t = 0.0
		8:
			cam = c - fw * ln * 0.12
			zoom = 2.4
			if _lev_t > 1.0:
				_save("lev_broken_mid")
				print("VISUAL done")
				m.get_tree().quit()
	m.player.global_position = cam   # камера боя идёт за самолётом игрока (бессмертие)
	m.camera.global_position = cam
	m.camera.zoom = Vector2.ONE * zoom
	m.camera.reset_smoothing()
