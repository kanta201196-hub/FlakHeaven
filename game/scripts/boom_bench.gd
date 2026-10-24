class_name BoomBench
extends RefCounted
## 3.5: стенд 3D-взрывов (-- --boombench). Пустая пустыня, без врагов и интерфейса; каждый вид взрыва
## снимается раскадровкой из игровой камеры → user://boom_<вид>_<кадр>.png. --tilt=N — угол камеры.
## Время эффектов считается по игровому времени (замедлено), поэтому кадры совпадают с нужным моментом
## и на медленной машине без видеокарты.

const SLOW := 0.25
const TIMES := [0.06, 0.18, 0.35, 0.7, 1.3, 2.6, 4.5]

var m: Main
var _t := 0.0
var _i := -1
var _et := 0.0
var _shot := 0
var _scenes: Array = []
var _pos := Vector2.ZERO
var _suffix := ""
var _only: PackedStringArray = []
var _wait := 0   # кадров до взрыва: 3D-камера догоняет 2D (иначе точка на земле считается от старой камеры)


func _init(main: Main) -> void:
	m = main
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tilt="):
			Tuning.set_param("cam_tilt", float(a.substr(7)))
			_suffix += "_t" + a.substr(7)
		if a.begins_with("--zoom="):   # close-up frames for review: camera zoom beyond the player slider range
			Tuning.set_param("camera_zoom", float(a.substr(7)))
			_suffix += "_z" + a.substr(7)
		if a.begins_with("--tag="):   # extra file suffix, so parallel renders do not overwrite each other
			_suffix += "_" + a.substr(6)
		if a.begins_with("--boomonly="):   # только эти сцены через запятую: --boomonly=blast,ground
			_only = a.substr(11).split(",")
	_scenes = [
		{"name": "flak", "boom": [[Vector2(0, 0), 12.0, true, "flak"], [Vector2(170, -60), 6.0, true, ""]]},
		{"name": "air", "boom": [[Vector2(0, 0), 20.0, true, ""]]},
		{"name": "big", "boom": [[Vector2(0, 0), 46.0, true, ""]]},
		{"name": "ground", "boom": [[Vector2(0, 0), 18.0, false, ""]]},
		{"name": "blast", "blast": [Vector2(0, 0), 130.0]},
		{"name": "battle", "times": [0.3, 1.0, 2.5], "boom": [[Vector2(-300, -120), 20.0, true, ""], [Vector2(260, -180), 46.0, true, ""],
			[Vector2(120, 200), 18.0, false, ""], [Vector2(-180, 220), 12.0, true, "flak"], [Vector2(-420, 120), 18.0, false, ""]],
			"blast": [Vector2(380, 150), 130.0]},
		{"name": "stress", "times": [0.5, 1.5], "stress": 30},
		{"name": "zones", "times": [0.5, 1.6], "zones": true},
		{"name": "emp", "times": [0.08, 0.25, 0.5], "emp": true},
		{"name": "plasma", "times": [0.5, 0.7, 0.9, 1.4, 3.0], "plasma": true},   # S10-08: плазменная бомба падает и рвётся на земле
		{"name": "debris", "times": [0.4, 1.0, 2.2], "boom": [[Vector2(-150, 0), 46.0, true, ""], [Vector2(200, 60), 18.0, false, ""]]},
	]
	if not _only.is_empty():
		_scenes = _scenes.filter(func(sc: Dictionary) -> bool: return _only.has(String(sc["name"])))


func process(delta: float) -> void:
	_t += delta
	if m.state == "menu" and _i < 0 and _t > 0.3:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--op="):   # same area in every run (campaign.cfg remembers the last operation played)
				Campaign.debug_open_all()
				Campaign.select(clampi(int(a.substr(5)) - 1, 0, Campaign.OPS.size() - 1))
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
		if _t < 0.5:
			return
		_pos = m.player.global_position + Vector2(0, -1600)
		_i = 0
		_start()
	m.player.global_position = _pos + Vector2(-330, 260)
	m.player.heading = -PI / 3.0
	m.camera.global_position = _pos
	m.camera.reset_smoothing()
	if _i >= _scenes.size():
		Engine.time_scale = 1.0
		print("BOOM done")
		m.get_tree().quit()
		return
	var sc: Dictionary = _scenes[_i]
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			for b in sc.get("boom", []):
				m.fx.explosion(_pos + (b[0] as Vector2), b[1], b[2], true, b[3])
			if sc.has("blast"):
				m.fx.blast(_pos + (sc["blast"][0] as Vector2), sc["blast"][1])
			if sc.get("zones", false):   # тест 3.5-s7: прицел бомб, падающие бомбы и огонь — на земле по рельефу
				var hb := Hardpoint.new("Бомбоотсек", 2, "bombs")
				hb.trigger = "button"
				hb.cd = 0.0
				Input.action_press("fire_hardpoint")   # прицел держится, пока кнопка «зажата»
				m.player.groups.append(hb)
				m.projectiles.spawn_bomb(_pos + Vector2(250, -150), 3.0, 0.0, 130.0, "бомбы", _pos + Vector2(250, -150), true)
				m.projectiles.spawn_bomb(_pos + Vector2(-250, -200), 3.0, 0.0, 130.0, "бомбы", _pos + Vector2(-250, -200), true)
				m.projectiles.spawn_fire(_pos + Vector2(80, 180), 90.0, 0.0, 4.0, "мастерство: выжженная земля", true)
				m.projectiles.spawn_fire(_pos + Vector2(420, 120), 70.0, 0.0, 4.0, "связка: ковровая дорожка", true)
			if sc.get("plasma", false):
				m.projectiles.spawn_bomb(m.player.global_position, Hardpoint.PLASMA_FUSE, 0.0, 160.0, "плазма", _pos, true)
				m.projectiles.bombs.back()["plasma"] = {"dps": 0.0, "t": 4.0}
			if sc.get("emp", false):
				m.fx.emp_wave(m.player.global_position, 380.0)
			for k in int(sc.get("stress", 0)):   # мясорубка: 30 взрывов разом — замер нагрузки
				var o := Vector2(randf_range(-700, 700), randf_range(-400, 400))
				m.fx.explosion(_pos + o, [12.0, 20.0, 46.0, 18.0][k % 4], k % 4 != 3, true, "flak" if k % 4 == 0 else "")
		return
	_et += delta
	var times: Array = sc.get("times", TIMES)
	if _shot < times.size() and _et >= float(times[_shot]):
		var img := m.get_viewport().get_texture().get_image()
		img.save_png("user://boom_%s%s_%d.png" % [sc["name"], _suffix, _shot])
		print("BOOM %s t=%.2f parts=%d cpu=%d us" % [sc["name"], _et, Boom3D.I.count() if Boom3D.I != null else -1, Boom3D.I.stats_us if Boom3D.I != null else -1])
		_shot += 1
	if _shot >= times.size():
		_i += 1
		_pos += Vector2(2600, 0)   # следующая сцена — на чистом месте (без пятен и дыма прошлой)
		if _i < _scenes.size():
			_start()


func _start() -> void:
	Engine.time_scale = SLOW
	_et = 0.0
	_shot = 0
	m.camera.global_position = _pos
	m.camera.reset_smoothing()
	_wait = 4
