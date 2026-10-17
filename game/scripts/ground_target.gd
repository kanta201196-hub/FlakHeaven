class_name GroundTarget
extends Enemy
## Наземная цель (позиция ПВО). Не таранит, ракеты «воздух-воздух» её не берут —
## работают курсовое, НАР, бомбы, гондолы, турели и навыки.
##   zsu    — зенитная установка: очереди по 4 снаряда с упреждением, вспышка перед очередью;
##            3.5: сбивает наши ракеты и НАР, подлетающие к позиции;
##   sam    — зенитный ракетный комплекс: захват (красная линия) → ракета;
##   radar  — РЛС: пока жива, ЗСУ и ЗРК стреляют дальше (+30%);
##   bunker — командный бункер: прочный, без оружия. 3.5: главная цель — уничтожен бункер, позиция взята.
## 3.5: бункер и РЛС стоят на месте; ЗСУ и ЗРК переезжают между позициями вокруг бункера,
## встают между ним и самолётом и прикрывают его. Без бункера техника теряет управление и уезжает.
## Правка 3.5-s4 (Kanta: «тупо перекатываются»): переезды через общий модуль GroundDrive (как у конвоя) —
## разгон и торможение, ЗСУ на гусеницах доворачивает на месте, ЗРК на колёсах едет по дуге.
## Корпус в 3D смотрит по курсу машины, а не по сдвигу точки на экране.

var variant := "zsu"
var site: AASite
var _cd := 2.0
var _aim := 0.0
var _shots := 0
var _shot_t := 0.0
var _lock := 0.0
var _t := 0.0
var _spin := 0.0
var _body_angle := 0.0
# 3.5: переезды и противоракетная оборона
var _goal := Vector2.INF     # куда едет (точка рельефа)
var _move_cd := 0.0
var _def_cd := 0.0
var _fire_dir := 0.0         # куда смотрит ствол при перехвате (для вспышки)
var _def_flash := 0.0
var leaderless := false      # бункер уничтожен
var drive: GroundDrive = null   # правка 3.5-s4: у ЗСУ и ЗРК
var _drive_t := 0.0

const DRIVE_SPEED := 70.0
const DEF_R := 300.0         # радиус перехвата наших ракет


func setup(v: String, s: AASite, hp_mult: float) -> void:
	variant = v
	site = s
	_body_angle = randf() * TAU
	is_ground = true
	no_despawn = true
	big = v != "zsu"
	match v:
		"zsu":
			hp = 90.0
			radius = 20.0
			xp = 4
			parts = 4
		"sam":
			hp = 120.0
			radius = 24.0
			xp = 5
			parts = 5
		"radar":
			hp = 80.0
			radius = 22.0
			xp = 3
			parts = 3
		"bunker":
			hp = 420.0 # 3.5: главная цель позиции
			radius = 32.0
			xp = 8
			parts = 10
	hp *= hp_mult
	max_hp = hp
	repair_chance = 0.15
	kill_shake = 6.0
	_cd = randf_range(1.0, 2.5)
	_move_cd = randf_range(1.0, 3.0)


func kind() -> String:
	return "ПВО"


## Наземные цели не масштабируются спавнером
func apply_hp_mult(_m: float) -> void:
	pass


func _ready() -> void:
	super()
	z_index = -2
	anchor = position # точка рельефа; логическая позиция считается от неё каждый кадр (Enemy._process)
	if mobile():
		drive = GroundDrive.new(anchor, _body_angle)
		if variant == "zsu":   # гусеницы: доворот на месте, короткая дуга
			drive.max_speed = 80.0
			drive.turn_r = 40.0
			drive.pivot = 0.9
			drive.accel = 40.0
		else:                  # колёсное шасси ЗРК: только по дуге, плавнее
			drive.max_speed = 70.0
			drive.turn_r = 75.0
			drive.accel = 28.0
		drive.brake = drive.accel * 2.0


## Проекция точки рельефа на слой самолётов (как её видно с камеры). Без 3D — та же точка.
static func air_pos(g: Vector2) -> Vector2:
	var r := Render3D.I
	if r == null or not Render3D.enabled or r.cam == null or r.terrain == null:
		return g
	var c := r.cam.global_position
	var y := r.terrain.surface_fast(g.x, g.y).y
	if c.y <= 1.0 or c.y - y <= 1.0:
		return g
	var k := (c.y - y) / c.y
	return Vector2(c.x + (g.x - c.x) / k, c.z + (g.y - c.z) / k)


func mobile() -> bool:
	return variant == "zsu" or variant == "sam"


func _range() -> float:
	var r := 650.0 if variant == "zsu" else 900.0
	if site != null and site.radar_alive():
		r *= 1.3
	return r


func behave(delta: float) -> void:
	_t += delta
	_spin += delta * 1.5
	_def_flash = maxf(0.0, _def_flash - delta)
	if leaderless:
		_drive_off(delta)
		return
	var p := Main.I.player
	if p == null or p.hp <= 0.0 or site == null or not site.active:
		if drive != null:
			_stand(delta)
		return
	if mobile():
		_drive(delta, p)
	var to := p.global_position - global_position
	var d := to.length()
	heading = rotate_toward(heading, to.angle(), deg_to_rad(120.0) * delta)
	match variant:
		"zsu":
			_defend(delta)
			if _shots > 0:
				_shot_t -= delta
				if _shot_t <= 0.0:
					fire_at_player(randf_range(-0.07, 0.07))
					_shots -= 1
					_shot_t = 0.09
			elif _aim > 0.0:
				_aim -= delta
				if _aim <= 0.0:
					_shots = 4
			else:
				_cd -= delta
				if _cd <= 0.0 and d < _range():
					_aim = 0.4
					_cd = randf_range(1.8, 2.6)
		"sam":
			if _lock > 0.0:
				_lock -= delta
				if _lock <= 0.0:
					Main.I.projectiles.spawn_missile(global_position, to.normalized())
					Main.I.sfx.play("sam_launch", -6.0, 0.9)
			else:
				_cd -= delta
				# ЗРК пускает только с места
				if _cd <= 0.0 and d < _range() and _goal == Vector2.INF:
					_lock = 1.2
					_cd = randf_range(5.0, 6.5)
					Main.I.sfx.play("sam_lock", -6.0, 1.2)


## Переезд: раз в несколько секунд — новая точка между бункером и самолётом (полукольцо 140–240 пикс.)
func _drive(delta: float, p: Player) -> void:
	if _goal == Vector2.INF:
		_stand(delta)
		_move_cd -= delta
		if _move_cd > 0.0 or _lock > 0.0 or site.bunker == null:
			return
		var b: Vector2 = site.bunker.anchor
		var toward := (p.global_position - site.global_position).angle()
		var slot := b + Vector2.from_angle(toward + randf_range(-1.1, 1.1)) * randf_range(140.0, 240.0)
		if Render3D.I != null and Render3D.I.terrain != null and Render3D.I.terrain._bg != null:
			slot = Render3D.I.terrain.find_floor(slot, 110.0)
		_goal = slot
		_drive_t = 0.0
		return
	var step := _goal - anchor
	_drive_t += delta
	# приехал (у колёсной — «почти»: по дуге в точку можно не попасть) — тормозит и встаёт
	if step.length() < (12.0 if drive.pivot > 0.0 else 30.0) or _drive_t > 9.0:
		_goal = Vector2.INF
		_move_cd = randf_range(3.0, 5.5)
		return
	# к точке подъезжает с замедлением: тормозной путь v²/2a
	var want := DRIVE_SPEED
	var stop_d := drive.speed * drive.speed / (2.0 * drive.brake) + 8.0
	if step.length() < stop_d * 1.5:
		want = maxf(15.0, DRIVE_SPEED * step.length() / (stop_d * 1.5))
	drive.drive_to(_goal, want, delta)
	_sync_drive()


func _stand(delta: float) -> void:
	drive.stop(delta)
	_sync_drive()


func _sync_drive() -> void:
	anchor = drive.pos
	_body_angle = drive.heading


## Бункер уничтожен: техника без командования прекращает огонь и уходит от позиции
func _drive_off(delta: float) -> void:
	if not mobile() or site == null:
		return
	var away := (anchor - site.anchor).normalized()
	if away == Vector2.ZERO:
		away = Vector2.from_angle(_body_angle)
	drive.drive_to(anchor + away * 400.0, DRIVE_SPEED * 0.9, delta)
	_sync_drive()


## ПРО позиции: ЗСУ сбивает наши ракеты и НАР в радиусе DEF_R (очередь — 0,5 с перезарядки)
func _defend(delta: float) -> void:
	_def_cd -= delta
	if _def_cd > 0.0:
		return
	var pr := Main.I.projectiles
	var best := -1
	var best_d := DEF_R
	var arr := "m"
	for i in pr.pmissiles.size():
		var dd := global_position.distance_to(pr.pmissiles[i]["p"])
		if dd < best_d:
			best_d = dd
			best = i
	for i in pr.rockets.size():
		if float(pr.rockets[i]["delay"]) > 0.0:
			continue
		var dd := global_position.distance_to(pr.rockets[i]["p"])
		if dd < best_d:
			best_d = dd
			best = i
			arr = "r"
	if best < 0:
		return
	_def_cd = 0.5
	var mp: Vector2 = (pr.pmissiles[best] if arr == "m" else pr.rockets[best])["p"]
	_fire_dir = (mp - global_position).angle()
	_def_flash = 0.12
	Main.I.fx.zap(global_position, mp)
	# не каждая очередь попадает: 65%
	if randf() < 0.65:
		Main.I.fx.explosion(mp, 12.0, true, true, "flak")
		if arr == "m":
			pr.pmissiles.remove_at(best)
		else:
			pr.rockets.remove_at(best)
		Main.I.tele.add("aa_shot_down")
	Main.I.sfx.play("aa_intercept", -12.0, 1.6)


func _die() -> void:
	if site != null:
		site.on_target_destroyed(self)
	super()


func _draw() -> void:
	# тень-подложка, чтобы наземное читалось «ниже» самолётов
	var spr := {"zsu": ["e_zsu", 44.0], "sam": ["e_sam", 54.0], "radar": ["e_radar", 50.0], "bunker": ["e_bunker", 66.0]}
	var ba: float = _body_angle
	if mobile() and not leaderless and _goal == Vector2.INF and site != null and site.active:
		ba = heading # стоит — разворачивается на цель
	if variant == "zsu" and _def_flash > 0.0:
		ba = _fire_dir
	if draw_enemy_sprite(spr[variant][0], spr[variant][1], Color.WHITE, ba):
		if variant == "zsu" and (_aim > 0.0 or _shots > 0 or _def_flash > 0.0):
			draw_circle(Vector2.from_angle(ba) * 30.0, 6.0, Color(1.0, 0.9, 0.3))
		if variant == "sam" and _lock > 0.0:
			var pl := Main.I.player
			if pl != null and pl.hp > 0.0:
				var al := 0.35 + 0.5 * absf(sin(_t * 30.0))
				draw_line(Vector2.ZERO, to_local(pl.global_position), Color(1, 0.15, 0.1, al), 2.0)
		draw_hp_bar()
		return
	draw_circle(Vector2(4, 5), radius + 4.0, Color(0, 0, 0, 0.25))
	var base := Color(0.45, 0.5, 0.38)
	match variant:
		"zsu":
			draw_rect(Rect2(-16, -12, 32, 24), body_color(base))
			var tip := Vector2.from_angle(heading) * 24.0
			draw_line(Vector2.ZERO, tip, body_color(Color(0.3, 0.33, 0.27)), 5.0)
			if _aim > 0.0 or _shots > 0:
				draw_circle(tip, 6.0, Color(1.0, 0.9, 0.3))
		"sam":
			draw_rect(Rect2(-20, -16, 40, 32), body_color(base))
			var xf := Transform2D(heading, Vector2.ZERO)
			for i in 2:
				var off := Vector2(0, -7 + 14 * i)
				draw_line(xf * (off + Vector2(-10, 0)), xf * (off + Vector2(18, 0)), body_color(Color(0.85, 0.85, 0.8)), 4.0)
			if _lock > 0.0:
				var p := Main.I.player
				if p != null and p.hp > 0.0:
					var a := 0.35 + 0.5 * absf(sin(_t * 30.0))
					draw_line(Vector2.ZERO, to_local(p.global_position), Color(1, 0.15, 0.1, a), 2.0)
		"radar":
			draw_circle(Vector2.ZERO, 14.0, body_color(base))
			var dish := Vector2.from_angle(_spin) * 20.0
			draw_line(-dish, dish, body_color(Color(0.8, 0.85, 0.8)), 4.0)
		"bunker":
			draw_rect(Rect2(-28, -22, 56, 44), body_color(Color(0.4, 0.42, 0.38)))
			draw_rect(Rect2(-28, -22, 56, 44), Color(0.2, 0.22, 0.2), false, 3.0)
			draw_rect(Rect2(-12, -4, 24, 8), Color(0.15, 0.15, 0.12))
	draw_hp_bar()
