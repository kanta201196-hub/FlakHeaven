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
		if a.begins_with("--gfx="):   # T4-04: сравнение пресетов качества — vis_<имя>_gN.png
			_suffix += "_g" + a.substr(6)


func process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.01)
	if OS.get_cmdline_user_args().has("--hangarbench"):
		_hangar_bench()
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
				_points = _points.filter(func(q: Dictionary) -> bool: return String(q["name"]).begins_with(a.get_slice("=", 1)))
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
	elif p.get("enemies", false) and not _spawned:
		_spawn_all_enemies(m.player.global_position)
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
	if p.get("crash", false) and _pt > 1.2 and not p.has("_done"):
		# 3.4-t1 п. 32: ведомый сбит (бессмертие не даёт урон — обнуляем напрямую)
		p["_done"] = true
		var wm: Wingman = m.player.wingmen[0]
		wm.hp = 0.0
		wm.dead_t = 20.0
		wm.visible = false
		m.fx.explosion(wm.global_position, 22.0)
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


## Точки: пустыня, гора, кишлак, оазис, бой со взрывами, крупный план самолёта
func _make_points() -> Array:
	var bg := m.background
	var found := {}
	var empty := Vector2.INF
	for r in range(0, 14):
		for cx in range(-r, r + 1):
			for cy in range(-r, r + 1):
				if maxi(absi(cx), absi(cy)) != r:
					continue
				var o := bg.chunk_object(cx, cy)
				if o.is_empty():
					if empty == Vector2.INF:
						empty = Vector2((cx + 0.5) * Background.CHUNK, (cy + 0.5) * Background.CHUNK)
				elif not found.has(o["name"]):
					found[o["name"]] = o["pos"]
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
	pts.append({"name": "battle", "pos": empty + Vector2(0, -300), "boom": true})
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
	if OS.get_cmdline_user_args().has("--modelbench"):   # 3.5: самолёты игрока 3D-моделями в бою
		pts = []
		for c in ["fighter", "attacker", "bomber"]:
			for lv in [1, 2]:
				pts.append({"name": "model_%s_%d" % [c, lv], "pos": empty + Vector2(300, 300), "cls": [c, lv], "wait": 1.0, "zoom": 2.2})
				pts.append({"name": "model_%s_%d_far" % [c, lv], "pos": empty + Vector2(300, 300), "cls": [c, lv], "fly": true, "wait": 1.5, "zoom": 1.0})
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
			# крупно турели: штурмовик и бомбардировщик, ступени 1 и 3, два ракурса (сверху-сзади, снизу-сбоку)
			# [класс, ур., ступень, № турели]
			for q in [["attacker", 1, 1, 0], ["attacker", 1, 3, 0], ["bomber", 1, 1, 0], ["bomber", 1, 1, 1], ["bomber", 1, 1, 2], ["bomber", 2, 3, 0], ["bomber", 2, 3, 1]]:
				_hq.append(q)
			_t = 0.0
			return
		for c in PlaneClasses.LIST:
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
	if _hq.is_empty():
		print("VISUAL done")
		m.get_tree().quit()
		return
	var cur: Array = _hq[0]
	m.hangar_tab = "plane"
	m.hangar_cls = cur[0]
	if Hangar3D.I != null:
		Hangar3D.I._cls = cur[0]
		Hangar3D.I.view_lvl = cur[1]
		Hangar3D.I.weapon_tier = cur[2]
		if cur.size() > 3:   # --turretclose: крупный план турели № cur[3]
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
	_hf += 1
	if _hf > 8 and _t > 1.2:   # в облаке (программная отрисовка) кадр идёт ~1 с — ждём кадры, а не секунды
		if cur.size() > 3:
			_save("turret_s%d_%s_%d_w%d_v%d" % [WeaponModels.turret_style, cur[0], cur[1], cur[2], cur[3]])
		else:
			_save("hangar_%s_%d_w%d" % [cur[0], cur[1], cur[2]])
		_hq.pop_front()
		_t = 0.0
		_hf = 0
