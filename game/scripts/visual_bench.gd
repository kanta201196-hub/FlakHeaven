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
		m.select_class("fighter")
		_t = 0.0
		return
	if m.state != "playing" or not is_instance_valid(m.player):
		return
	m.god_mode = true
	m.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	for e in m.get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	if m.hud != null:
		m.hud.visible = false
	if _i < 0:
		if _t < 1.0:
			return
		_points = _make_points()
		_i = 0
		_t = 0.0
	if _i >= _points.size():
		print("VISUAL done")
		m.get_tree().quit()
		return
	var p: Dictionary = _points[_i]
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
	return pts



## 3.4-t1 (п. 1): 3D-ангар — вкладка «САМОЛЁТ» каждого класса, ур. 1 и ур. 2 → user://vis_hangar_<класс>_<ур>.png
var _hq: Array = []
var _hf := 0


func _hangar_bench() -> void:
	if _t < 1.5:
		return
	if m.state != "hangar":
		m.ui_click("menu_hangar")
		for c in PlaneClasses.LIST:
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
	_hf += 1
	if _hf > 8 and _t > 1.2:   # в облаке (программная отрисовка) кадр идёт ~1 с — ждём кадры, а не секунды
		_save("hangar_%s_%d_w%d" % [cur[0], cur[1], cur[2]])
		_hq.pop_front()
		_t = 0.0
		_hf = 0
