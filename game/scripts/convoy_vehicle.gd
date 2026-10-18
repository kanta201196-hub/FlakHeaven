class_name ConvoyVehicle
extends Enemy
## Машина наземного конвоя (концепция docs/activities/convoy.md, раздел 3). Едет по маршруту колонны
## (Convoy.route) через общий модуль движения GroundDrive: разгон, дуги, держит дистанцию до впереди идущей.
##   truck, light — грузовики без оружия, главная цель; при тревоге прибавляют ход к укрытию;
##   scout, technical — броневик и боевой пикап: при тревоге съезжают с дороги вбок и бьют очередями;
##   ifv — БМП: пушка очередями, при тревоге ставит дым над грузовиками;
##   manpads — пикап с ПЗРК: встаёт, захват (красная линия) и ракета, потом догоняет колонну.
## Подбитая машина не исчезает: горит и остаётся остовом на дороге — колонна объезжает его медленно («пробка»).

const SPEC := {
	# len — длина на экране (как у ПВО: × unit_scale). Пропорции по настоящим длинам (решение Kanta 18.10, A-05):
	# грузовик 7,9 м = 1; БМП 6,8 м ≈ 0,88; пикап 5,2 м ≈ 0,66; броневик 5 м ≈ 0,64; всё меньше прежнего (грузовик 58 → 50)
	# Тест 3.5-s6 (Kanta 18.10, A-08): масштаб мира «с высоты 2–4 км» — грузовик ≈ 0,5 истребителя (plane_len 100 → 28 × 1,8 = 50 пикс.),
	# пикапы 0,5 грузовика, БМП 0,9, броневик 0,64
	# hp — прочность по категориям S6-02 (× рост врагов): стандартная 90 — грузовики, пикап, техничка;
	# бронированная 135 — броневик, БМП, ПЗРК. r — радиус поворота, pivot — разворот на месте
	"truck": {"len": 28.0, "hp": GroundTarget.HP_STD, "r": 75.0, "pivot": 0.0, "acc": 32.0, "xp": 6, "parts": 6},
	"light": {"len": 14.0, "hp": GroundTarget.HP_STD, "r": 45.0, "pivot": 0.0, "acc": 50.0, "xp": 4, "parts": 4},
	"scout": {"len": 18.0, "hp": GroundTarget.HP_ARMOR, "r": 50.0, "pivot": 0.0, "acc": 55.0, "xp": 5, "parts": 5},
	"technical": {"len": 14.0, "hp": GroundTarget.HP_STD, "r": 42.0, "pivot": 0.0, "acc": 60.0, "xp": 4, "parts": 4},
	"manpads": {"len": 14.0, "hp": GroundTarget.HP_ARMOR, "r": 42.0, "pivot": 0.0, "acc": 60.0, "xp": 5, "parts": 5},
	"ifv": {"len": 25.0, "hp": GroundTarget.HP_ARMOR, "r": 55.0, "pivot": 1.0, "acc": 38.0, "xp": 8, "parts": 8},
}
const TEX := {"truck": "e_convoy_truck", "light": "e_convoy_pickup_tent", "scout": "e_convoy_scout",
	"technical": "e_convoy_technical", "manpads": "e_convoy_manpads", "ifv": "e_convoy_ifv"}
const MARCH := 100.0         # пикс./с по дороге (правка 3.5-s4: было 70 — колонна была мишенью)
const DASH := 145.0          # грузовики при тревоге (было 100)
const GAP := 110.0           # просвет между машинами в марше, пикс. (было 30–45)
const OFFROAD := 150.0       # на сколько охрана съезжает вбок от дороги при тревоге

var role := "truck"
var convoy: Convoy
var drive: GroundDrive
var s := 0.0                 # где на маршруте (пикс. от начала)
var lane := 0.0              # смещение вбок от оси дороги, пикс. (+ — влево по ходу)
var wreck := false
var escaped := false
var _side := 1.0             # куда съезжает охрана
var _cd := 1.5
var _shots := 0
var _shot_t := 0.0
var _lock := 0.0             # захват ПЗРК (3D поднимает трубу)
var _t := 0.0
var _burn := 0.0


func setup(r: String, c: Convoy, hp_v: float) -> void:
	role = r
	convoy = c
	var sp: Dictionary = SPEC[r]
	hp = hp_v
	max_hp = hp_v
	radius = maxf(float(sp["len"]) * 0.5, 9.0)   # A-08: машины меньше, попадание чуть щедрее картинки
	is_ground = true
	no_despawn = true
	big = r in ["truck", "ifv"]
	xp = int(sp["xp"])
	parts = int(sp["parts"])
	repair_chance = 0.1
	kill_shake = 7.0 if big else 4.0
	_side = 1.0 if randf() < 0.5 else -1.0
	_cd = randf_range(1.0, 2.5)


func place(at_s: float) -> void:
	s = at_s
	var p := convoy.point_at(s)
	var h := convoy.dir_at(s).angle()
	var sp: Dictionary = SPEC[role]
	drive = GroundDrive.new(p, h)
	drive.max_speed = DASH * 1.15
	drive.turn_r = float(sp["r"])
	drive.pivot = float(sp["pivot"])
	drive.accel = float(sp["acc"]) * 1.6
	drive.brake = float(sp["acc"]) * 3.2
	drive.speed = MARCH * 0.6
	_side = convoy.dry_side(_side)
	anchor = p
	heading = h
	position = p


func _half_len() -> float:
	return float(SPEC[role]["len"]) * 0.5 * Tuning.g("unit_scale")


## Корпус для расталкивания (A-07): отрезок по курсу и радиус — капсула длиной с машину, шириной ~0,45 длины
func body_r() -> float:
	return _half_len() * 0.45


func body_a() -> Vector2:
	return anchor + Vector2.from_angle(heading) * (_half_len() - body_r())


func body_b() -> Vector2:
	return anchor - Vector2.from_angle(heading) * (_half_len() - body_r())


func nudge(d: Vector2) -> void:
	if wreck or drive == null or d.length_squared() < 1e-6:
		return
	drive.pos = convoy.keep_dry(drive.pos + d)
	anchor = drive.pos


## Впереди по курсу вплотную стоит или едет другая машина (живая или остов) — она, иначе null
func _blocker() -> ConvoyVehicle:
	var fwd := Vector2.from_angle(heading)
	var a := body_a() + fwd * 14.0
	var b := body_b()
	for v in convoy.vehicles:
		if v == self or not is_instance_valid(v):
			continue
		var o := v as ConvoyVehicle
		if o.escaped or o.drive == null or (o.anchor - anchor).dot(fwd) <= 0.0:
			continue
		var cp := Geometry2D.get_closest_points_between_segments(a, b, o.body_a(), o.body_b())
		if cp[0].distance_to(cp[1]) < body_r() + o.body_r():
			return o
	return null


func kind() -> String:
	return {"truck": "грузовик", "light": "грузовик", "scout": "броневик", "technical": "пикап",
		"manpads": "ПЗРК", "ifv": "БМП"}[role]


func is_truck() -> bool:
	return role == "truck" or role == "light"


func armed() -> bool:
	return not is_truck()


## Тревога в колонне (3D: башни и пулемёты разворачиваются на самолёт)
func alarm_on() -> bool:
	return convoy != null and is_instance_valid(convoy) and convoy.alarm


## Прочность задаёт колонна
func apply_hp_mult(_m: float) -> void:
	pass


func _ready() -> void:
	super()
	z_index = -2


## Дым БМП: машины под завесой получают меньше урона (их плохо видно)
func absorb(dmg: float) -> float:
	if convoy != null and convoy.in_smoke(anchor):
		return dmg * (1.0 - Convoy.SMOKE_CUT)
	return dmg


func _process(delta: float) -> void:
	if wreck:
		# остов: стоит на месте, горит; логическая позиция — проекция точки рельефа (камера двигается)
		_burn += delta
		global_position = GroundTarget.air_pos(anchor)
		queue_redraw()
		return
	super(delta)


func behave(delta: float) -> void:
	_t += delta
	if convoy == null or drive == null:
		return
	var p := Main.I.player
	var alarm := convoy.alarm
	var want := MARCH
	var goal_s := s + 45.0
	var goal_lane := 0.0
	if convoy.leaderless or (convoy.ended and not is_truck()):
		# грузовиков нет (или время вышло) — охрана уходит по дороге к укрытию, не стреляет
		want = DASH
	elif alarm:
		if is_truck():
			want = DASH
		elif role == "scout" or role == "technical":
			# съехать с дороги вбок, держаться рядом с серединой колонны и бить с фланга
			goal_s = convoy.middle_s() + (60.0 if role == "scout" else -40.0)
			goal_lane = _side * OFFROAD
			# съезжает по факту (а не по полосе-цели): иначе ждущая охрана стояла на дороге и запирала грузовики
			var off_road := absf(convoy.lateral_of(anchor, s) - convoy.safe_lane(goal_lane)) > 30.0
			want = DASH * 1.1 if off_road or s < goal_s - 80.0 else 40.0
			if s > goal_s + 60.0 and not off_road:
				want = 15.0
			elif off_road:
				goal_s = maxf(goal_s, s + 60.0)
		elif role == "ifv":
			# между самолётом и грузовиками: сбоку от дороги со стороны игрока
			goal_s = convoy.middle_s()
			if p != null:
				goal_lane = signf(convoy.lateral_of(p.global_position, s)) * 70.0
			want = DASH if s < goal_s - 40.0 else 35.0
		elif role == "manpads":
			want = DASH * 0.9
	# дистанция до впереди идущей машины своей полосы (охрана, съехавшая вбок, грузовикам дорогу не держит)
	var ahead := convoy.ahead_of(self)
	if ahead != null and not (alarm and (role == "scout" or role == "technical")):
		var gap := ahead.s - s
		var need := _half_len() + ahead._half_len() + GAP * (0.6 if alarm else 1.0)
		if gap < need * 0.6:
			want = 0.0
		elif gap < need * 1.3:
			want = minf(want, ahead.drive.speed * clampf((gap - need * 0.6) / (need * 0.7), 0.0, 1.0) + 10.0)
	# остов на дороге впереди — объезд по обочине; полосу держим, пока корпус не прошёл остов целиком
	var jam := convoy.wreck_ahead(s, lane, 260.0, _half_len() + 24.0)
	if jam != INF:
		goal_lane = jam
		want = minf(want, 45.0)
		# ещё не съехали в сторону, а остов уже рядом — встать и довернуть, а не проехать сквозь
		if absf(convoy.lateral_of(anchor, s) - jam) > 30.0 and convoy.wreck_near(s, convoy.lateral_of(anchor, s), _half_len() * 2.0 + 30.0):
			want = minf(want, 14.0)
	# ПЗРК: стрелять только с места
	if role == "manpads" and alarm and not convoy.ended and not convoy.leaderless and p != null and p.hp > 0.0:
		if _lock > 0.0 or (_cd <= 0.0 and anchor.distance_to(p.global_position) < 950.0):
			want = 0.0
	# A-07: впереди вплотную машина. Едущую ждём; остов или вставшую объезжаем: полоса в сторону от неё (не к реке),
	# малым ходом, корпуса при этом расталкивает Convoy._separate — сквозь не проедет
	var bl := _blocker()
	if bl != null:
		if bl.wreck or bl.drive.speed < 8.0:
			var bl_lat := convoy.lateral_of(bl.anchor, s)
			var off := body_r() + bl.body_r() + 30.0
			var dside := convoy.dry_side(1.0 if lane >= bl_lat else -1.0)
			goal_lane = convoy.safe_lane(bl_lat + dside * off)
			if absf(goal_lane - bl_lat) < off * 0.8:
				goal_lane = bl_lat - dside * off     # к реке места нет — объезд с другой стороны
			want = minf(want, 18.0)
		else:
			want = 0.0
	lane = move_toward(lane, convoy.safe_lane(goal_lane), 60.0 * delta)
	var target := convoy.keep_dry(convoy.point_at(goal_s) + convoy.normal_at(goal_s) * lane)
	if want <= 0.5:
		drive.stop(delta)
	else:
		drive.drive_to(target, want, delta)
	drive.pos = convoy.keep_dry(drive.pos)
	anchor = drive.pos
	s = convoy.project(anchor, s)
	heading = drive.heading
	if s >= convoy.length - 20.0 and (convoy.leaderless or is_truck() or convoy.ended):
		escaped = true
		convoy.on_escaped(self)
		return
	if alarm and not convoy.ended and not convoy.leaderless:
		_fight(delta, p)


func _fight(delta: float, p: Player) -> void:
	if p == null or p.hp <= 0.0:
		return
	var d := global_position.distance_to(p.global_position)
	match role:
		"scout", "technical", "ifv":
			var rng := 750.0 if role == "ifv" else 650.0
			if _shots > 0:
				_shot_t -= delta
				if _shot_t <= 0.0:
					fire_at_player(randf_range(-0.08, 0.08))
					_shots -= 1
					_shot_t = 0.16 if role == "ifv" else 0.09
			else:
				_cd -= delta
				if _cd <= 0.0 and d < rng:
					_shots = 3 if role == "ifv" else 4
					_cd = randf_range(2.0, 2.8) if role == "ifv" else randf_range(1.6, 2.4)
					Main.I.sfx.play("aa_alert", -18.0, 1.6)
		"manpads":
			if _lock > 0.0:
				_lock -= delta
				if _lock <= 0.0:
					Main.I.projectiles.spawn_missile(global_position, (p.global_position - global_position).normalized())
					Main.I.sfx.play("sam_launch", -6.0, 1.1)
			else:
				_cd -= delta
				if _cd <= 0.0 and d < 950.0 and drive.speed < 3.0:
					_lock = 1.2
					_cd = randf_range(7.0, 8.0)
					Main.I.sfx.play("sam_lock", -6.0, 1.3)


## Подбит: награда как у наземной цели, но машина остаётся остовом (горит, мешает колонне)
func _die() -> void:
	hp = 0.0
	remove_from_group("enemies")
	Main.I.on_enemy_killed(self)
	Main.I.pickups.drop_xp(global_position, xp * Main.I.streak_mult())
	if randf() < repair_chance:
		Main.I.pickups.drop_repair(global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20)))
	wreck = true
	add_to_group("wrecks3d")
	if convoy != null:
		convoy.on_destroyed(self)


func _draw() -> void:
	var tex: String = TEX[role]
	if wreck:
		# остов: тёмная картинка, языки огня первые секунды
		if draw_enemy_sprite(tex, SPEC[role]["len"], Color(0.25, 0.22, 0.2), heading):
			pass
		else:
			draw_rect(Rect2(-14, -8, 28, 16), Color(0.15, 0.13, 0.12))
		if _burn < 7.0 and not Render3D.enabled:
			draw_circle(Vector2(sin(_burn * 9.0) * 2.0, -2.0), 6.0 + 2.0 * sin(_burn * 13.0), Color(1.0, 0.55, 0.15, 0.8))
		return
	if draw_enemy_sprite(tex, SPEC[role]["len"], Color.WHITE, heading):
		if role == "manpads" and _lock > 0.0:
			var pl := Main.I.player
			if pl != null and pl.hp > 0.0:
				var al := 0.35 + 0.5 * absf(sin(_t * 30.0))
				draw_line(Vector2.ZERO, to_local(pl.global_position), Color(1, 0.15, 0.1, al), 2.0)
		if _shots > 0:
			draw_circle(Vector2.from_angle((Main.I.player.global_position - global_position).angle() if Main.I.player != null else heading) * radius, 4.0, Color(1.0, 0.9, 0.3))
		draw_hp_bar()
		return
	# без картинки — простая фигура
	var c := body_color(Color(0.62, 0.52, 0.36))
	var xf := Transform2D(heading, Vector2.ZERO)
	var l := float(SPEC[role]["len"]) * 0.5
	draw_colored_polygon(PackedVector2Array([xf * Vector2(-l, -l * 0.4), xf * Vector2(l, -l * 0.4), xf * Vector2(l, l * 0.4), xf * Vector2(-l, l * 0.4)]), c)
	draw_hp_bar()
