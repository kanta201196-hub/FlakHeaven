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
		{"name": "trails", "times": [0.3, 0.6, 1.0, 1.6], "trails": true},   # VFX-03: missile and rocket smoke
		{"name": "wreck", "times": [1.0, 2.0, 3.0], "wreck": true},   # VFX-03: smoke of a wreck on the ground and of a falling plane
		{"name": "screen", "times": [0.5, 1.5, 3.0, 5.0], "screen": true},   # VFX-03: convoy smoke screen (as Convoy.smoke_fx)
		{"name": "marks", "times": [2.0, 5.0, 9.0], "blasts": [[Vector2(-220, -60), 130.0], [Vector2(260, 90), 130.0],
			[Vector2(470, -170), 100.0], [Vector2(60, 230), 90.0]]},   # VFX-06: craters and scorch on the relief
		{"name": "fires", "times": [0.15, 0.6, 1.2, 1.8], "boom": [[Vector2(-260, -40), 18.0, false, ""], [Vector2(240, 120), 18.0, false, ""],
			[Vector2(30, -170), 46.0, true, ""], [Vector2(-60, 210), 18.0, false, ""]], "blast": [Vector2(380, -120), 130.0]},   # VFX-06: light of blasts and burning spots
		{"name": "guns", "times": [0.3, 0.52, 0.71, 0.93, 1.12], "guns": true, "slow": 0.02, "pl": Vector2(-220, 120)},   # VFX-04: muzzle flashes, tracers, hit sparks
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
		# the cloud's software GPU makes auto-quality drop the saved preset to «Низкое» (no fire light, fewer
		# particles), so the bench pins the quality players see: «Высокое», or --gfx=N; not saved
		Settings.gfx_auto = false
		Settings.set_preset(2)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--gfx="):
				Settings.set_preset(int(a.substr(6)))
		Settings.apply_gfx()
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
	var pl_at: Vector2 = _scenes[_i].get("pl", Vector2(-330, 260)) if _i >= 0 and _i < _scenes.size() else Vector2(-330, 260)
	m.player.global_position = _pos + pl_at
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
			# a scene may ask for slower time once the camera has settled: effects living a few hundredths of a
			# second (muzzle flashes) fall between frames of the slow cloud renderer at SLOW
			Engine.time_scale = float(sc.get("slow", SLOW))
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
			if sc.get("trails", false):
				var pp := m.player.global_position
				for src: Array in [[Vector2(420, -260), "sam"], [Vector2(380, 180), "aam"], [Vector2(-60, -330), "manpads"]]:
					var a: Vector2 = _pos + (src[0] as Vector2)
					m.projectiles.spawn_missile(a, (pp - a).normalized(), src[1])
				for k in 3:
					m.projectiles.spawn_rocket(pp + Vector2(0, -20 * k), Vector2(520, -300).rotated(0.08 * k), 0.0, 40.0, 0.0)
			if sc.get("wreck", false) and Render3D.I != null:
				Boom3D.ensure()   # the lit smoke takes Boom3D's puff texture
				for w: Array in [[Vector2.ZERO, 16], [Vector2(300, -120), 36]]:   # a wreck on the ground; a crash still smoking hard
					var ws := Render3D.I._make_smoke()
					ws.global_position = Render3D.I.ground_under(_pos + (w[0] as Vector2)) + Vector3(0, 6, 0)
					ws.amount = w[1]
			for bl: Array in sc.get("blasts", []):
				m.fx.blast(_pos + (bl[0] as Vector2), bl[1])
			if sc.get("emp", false):
				m.fx.emp_wave(m.player.global_position, 380.0)
			for k in int(sc.get("stress", 0)):   # мясорубка: 30 взрывов разом — замер нагрузки
				var o := Vector2(randf_range(-700, 700), randf_range(-400, 400))
				m.fx.explosion(_pos + o, [12.0, 20.0, 46.0, 18.0][k % 4], k % 4 != 3, true, "flak" if k % 4 == 0 else "")
		return
	_et += delta
	if sc.get("screen", false):
		_screen(delta)
	if sc.get("guns", false):
		_guns(delta)
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


var _scr_acc := 0.0

## Same emission as Convoy.smoke_fx: a burst of 7 puffs, then 2 every 0.25 s over a 170 px circle
func _screen(delta: float) -> void:
	var burst := _et <= delta
	_scr_acc -= delta
	if _scr_acc > 0.0 and not burst:
		return
	_scr_acc = 0.25
	for i in (7 if burst else 2):
		var o := Vector2.from_angle(randf() * TAU) * Convoy.SMOKE_R * sqrt(randf()) * 0.85
		Boom3D.ensure().smoke_screen(GroundTarget.air_pos(_pos + o), Convoy.SMOKE_R * 0.45, burst)


var _gun_acc := 0.0

## Gunfire through the game's own calls: the player's two guns fire at a point ahead, two ground guns (ZSU, IFV)
## and a fighter fire at the player, and the player's bullets spark where they hit, 12 shots a second each
func _guns(delta: float) -> void:
	_gun_acc -= delta
	if _gun_acc > 0.0:
		return
	_gun_acc = 1.0 / 12.0
	var pr := m.projectiles
	var pl := m.player
	var fwd := Vector2.from_angle(pl.heading)
	var side := Vector2.from_angle(pl.heading + PI / 2.0) * 7.0 * pl.size
	var aim := _pos + Vector2(120, -120)
	for k in [-1.0, 1.0]:
		var mz: Vector2 = pl.global_position + fwd * 16.0 * pl.size + side * k
		pr.spawn_player_bullet(mz, (aim - mz).normalized() * Tuning.g("bullet_speed"), 0.0, 0.5)
	m.fx.hit_spark(aim + Vector2(randf_range(-18, 18), randf_range(-18, 18)))
	for g: Array in [[Vector2(180, 200), "zsu"], [Vector2(-120, -160), "ifv"], [Vector2(320, -220), "fighter"]]:
		var a: Vector2 = _pos + (g[0] as Vector2)
		pr.spawn_enemy_bullet(a, (pl.global_position - a).normalized().rotated(randf_range(-0.05, 0.05)) * 520.0, "", false, 0.0,
			false, g[1], 1.2)


func _start() -> void:
	Engine.time_scale = SLOW
	_et = 0.0
	_shot = 0
	m.camera.global_position = _pos
	m.camera.reset_smoothing()
	_wait = 40 if _i < _scenes.size() and _scenes[_i].has("slow") else 4   # slowed scenes freeze the camera chase
