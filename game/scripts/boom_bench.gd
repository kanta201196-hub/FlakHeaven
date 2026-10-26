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
		{"name": "splash", "times": [0.1, 0.3, 0.6, 1.0, 1.8], "river": true},   # VFX-05: bomb, crash and rounds in the river
		{"name": "guns", "times": [0.3, 0.52, 0.71, 0.93, 1.12], "guns": true, "slow": 0.02, "pl": Vector2(-220, 120)},   # VFX-04: muzzle flashes, tracers, hit sparks
		# Kanta 25.10: machine-gun turrets of the bomber tracking targets that circle and cross the plane; --film saves
		# every frame (run with --fixed-fps 30 for a clip in game time) and prints the frame of each turret shot
		{"name": "turrets", "times": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], "turrets": true, "slow": 1.0, "pl": Vector2.ZERO},
		# Kanta 26.10: every effect at its real place on the model — nozzle flames on afterburner, course guns firing
		# at a drone ahead, turrets at drones around (run once per class and plane level: --cls=… --plane=2)
		{"name": "planes", "times": [0.4, 0.55, 0.7, 0.85, 1.0], "turrets": true, "ab": true, "ahead": true, "pl": Vector2.ZERO},
		# Kanta s12: blasts, fire and a «Ёлочка» missile salvo right on the player's plane
		{"name": "clear", "times": [0.25, 0.6, 1.0, 1.6], "boom": [[Vector2(0, 0), 46.0, true, ""], [Vector2(45, -30), 20.0, true, ""],
			[Vector2(-30, 40), 18.0, false, ""]], "trails": true, "salvo": true, "pl": Vector2.ZERO},
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
		var cls := "fighter"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--cls="):   # a class with turrets for the turret scene: --cls=bomber
				cls = a.substr(6)
		m.select_class(cls)
		_t = 0.0
		return
	if m.state != "playing" or not is_instance_valid(m.player):
		return
	m.god_mode = true
	m.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	for e in m.get_tree().get_nodes_in_group("enemies"):
		if not (e as Node).has_meta("bench"):   # the turret scene's own targets stay
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
			if sc.get("salvo", false):   # the «Ёлочка» fan as PlayerSkills._fire_yolka launches it
				for i in 10:
					var a := m.player.heading + (float(i) / 9.0 - 0.5) * 2.6
					m.projectiles.spawn_player_missile(m.player.global_position, m.player.velocity * 0.5 + Vector2.from_angle(a) * 300.0,
						null, 0.0, "ёлочка")
			if sc.get("wreck", false) and Render3D.I != null:
				Boom3D.ensure()   # the lit smoke takes Boom3D's puff texture
				for w: Array in [[Vector2.ZERO, 16], [Vector2(300, -120), 36]]:   # a wreck on the ground; a crash still smoking hard
					var ws := Render3D.I._make_smoke()
					ws.global_position = Render3D.I.ground_under(_pos + (w[0] as Vector2)) + Vector3(0, 6, 0)
					ws.amount = w[1]
			for bl: Array in sc.get("blasts", []):
				m.fx.blast(_pos + (bl[0] as Vector2), bl[1])
			if sc.get("river", false):
				var rp := _river_points(3)
				if rp.is_empty():
					print("BOOM splash: no river in view")
				else:
					m.fx.blast(rp[0], 90.0)
					if rp.size() > 1:
						m.fx.explosion(rp[1], 30.0, false)   # a plane crashing into the river, as Render3D._sync_crashes
					if rp.size() > 2:
						for k in 6:   # rounds landing in the water
							Boom3D.ensure().ground_hit(rp[2] + Vector2(randf_range(-12, 12), randf_range(-30, 30)))
			if sc.get("turrets", false):
				_turret_targets(sc.get("ahead", false))
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
	if sc.get("turrets", false):
		_turrets_move()
	if sc.get("ab", false):
		m.player.ab_t = 1.0
	var times: Array = sc.get("times", TIMES)
	if _film:
		_film_frame(sc)
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


## Up to n points on the combat plane whose ground on screen is river water, spread apart, within the view
func _river_points(n: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var R := Render3D.I
	if R == null:
		return out
	var cand: Array[Vector2] = []
	for y in range(-420, 421, 20):
		for x in range(-700, 701, 20):
			var p := _pos + Vector2(x, y)
			if R.is_water(R.ground_under(p), 0.0):
				cand.append(p)
	cand.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(_pos) < b.distance_squared_to(_pos))
	for p in cand:   # nearest to the view centre first, so the effects stay in frame
		if out.any(func(q: Vector2) -> bool: return q.distance_to(p) < 200.0):
			continue
		out.append(p)
		if out.size() >= n:
			break
	return out


var _gun_acc := 0.0
var _home := Vector2.INF


## VFX-05: the river point nearest to `from` (combat plane ≈ ground x, z), so the splash scene films water;
## `from` itself when the area has no river within 4000 px
func _river_spot(from: Vector2) -> Vector2:
	var R := Render3D.I
	if R == null or R.terrain == null:
		return from
	var best := from
	var bd := INF
	for y in range(-4000, 4001, 40):
		for x in range(-4000, 4001, 40):
			var p := from + Vector2(x, y)
			if absf(R.terrain.river_field(p.x, p.y)) < Terrain3D.D_RIVER * 0.3 and p.distance_squared_to(from) < bd:
				bd = p.distance_squared_to(from)
				best = p
	return best

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
		# rounds end at the aim point, as when they miss there: VFX-04 dust shows where they land
		pr.spawn_player_bullet(mz, (aim - mz).normalized() * Tuning.g("bullet_speed"), 0.0, mz.distance_to(aim) / Tuning.g("bullet_speed"))
	m.fx.hit_spark(aim + Vector2(randf_range(-18, 18), randf_range(-18, 18)))
	for g: Array in [[Vector2(180, 200), "zsu"], [Vector2(-120, -160), "ifv"], [Vector2(320, -220), "fighter"]]:
		var a: Vector2 = _pos + (g[0] as Vector2)
		pr.spawn_enemy_bullet(a, (pl.global_position - a).normalized().rotated(randf_range(-0.05, 0.05)) * 520.0, "", false, 0.0,
			false, g[1], 1.2)


var _targets: Array[Enemy] = []
var _film := OS.get_cmdline_user_args().has("--film")
var _film_n := 0

## Paths of the turret scene's targets: [radius, angular speed rad/s, phase]; radius 0 — a pass across the nose
const TURRET_PATHS := [[170.0, 0.9, 0.0], [230.0, -0.6, 2.0], [0.0, 220.0, 0.0], [130.0, 1.4, 4.0]]


## Four drones that cannot die and do nothing on their own: _turrets_move flies them on TURRET_PATHS;
## `ahead` adds a fifth one hanging in front of the nose, so the course guns fire too
func _turret_targets(ahead := false) -> void:
	for t in _targets:
		if is_instance_valid(t):
			t.queue_free()
	_targets.clear()
	for k in TURRET_PATHS.size() + (1 if ahead else 0):
		var d := Drone.new()
		d.set_meta("bench", true)
		d.global_position = _pos
		m.world.add_child(d)
		d.hp = 1.0e9
		d.process_mode = Node.PROCESS_MODE_DISABLED
		_targets.append(d)
	_turrets_move()


func _turrets_move() -> void:
	for k in _targets.size():
		var d := _targets[k]
		if not is_instance_valid(d):
			continue
		var p: Vector2
		var hd: float
		if k >= TURRET_PATHS.size():   # in front of the nose
			d.global_position = m.player.global_position + Vector2.from_angle(m.player.heading) * 230.0
			d.heading = m.player.heading + PI
			d.hp = 1.0e9
			continue
		var pth: Array = TURRET_PATHS[k]
		var r: float = float(pth[0])
		if r > 0.0:
			var a: float = float(pth[2]) + float(pth[1]) * _et
			p = _pos + Vector2.from_angle(a) * r
			hd = a + signf(float(pth[1])) * PI / 2.0
		else:   # crosses 170 px above the plane, left to right, again every 900 px
			var x := fposmod(float(pth[1]) * _et, 900.0) - 450.0
			p = _pos + Vector2(x, -170.0)
			hd = 0.0
		d.global_position = p
		d.heading = hd
		d.hp = 1.0e9


## --film: every frame to user://film<suffix>_NNNN.png; "FILM shot N" marks the frame of each new turret round,
## so the clip's sound can be laid from the game's own turret samples
func _film_frame(sc: Dictionary) -> void:
	m.get_viewport().get_texture().get_image().save_png("user://film_%s%s_%04d.png" % [sc["name"], _suffix, _film_n])
	for b: Dictionary in m.projectiles.bullets:
		if String(b.get("src", "")) == "турели" and not b.has("film"):
			b["film"] = true
			print("FILM shot %d" % _film_n)
	_film_n += 1


func _start() -> void:
	Engine.time_scale = SLOW
	_et = 0.0
	_shot = 0
	if _home == Vector2.INF:
		_home = _pos
	_pos = _home
	if _i < _scenes.size() and _scenes[_i].get("river", false):
		_pos = _river_spot(_home)
	m.camera.global_position = _pos
	m.camera.reset_smoothing()
	_wait = 40 if _i < _scenes.size() and (_scenes[_i].has("slow") or _scenes[_i].has("river")) else 4   # slowed scenes freeze the camera chase
