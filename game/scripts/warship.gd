class_name Warship
extends Boss
## «Архипелаг Таласора» (задачи E-07, E-08): корабли-боссы идут по фарватеру пролива (маршрут — Convoy.sea_route),
## держатся на воде и ходят взад-вперёд по проливу, догоняя игрока вдоль маршрута. Цель наземная (is_ground):
## по ним работают бомбы, НАР и пушка; ракеты В-В — нет.
##   «Сторож» (cruiser, 10:00) — лёгкий крейсер: зенитные очереди с двух башен, пуск ЗУР с захватом,
##     на 70 % и 35 % прочности поднимает с палубы вертолёт «Сарыч» (решение Kanta 18.10, M-41).
##   «Левиафан» (leviathan, 15:00) — корабль-носитель (docs/biome2/archipelago.md): фаза 1 — ЗСУ по бортам,
##     фаза 2 (< 2/3) — взлёт «Чаек» (дроны) и ракетные залпы, фаза 3 (< 1/3) — главный калибр (кольца снарядов),
##     ход быстрее, пенный след длиннее.

const SPEC := {
	# len — длина на экране до unit_scale; speed — ход, пикс./с; w — полуширина корпуса для попаданий
	"cruiser": {"tex": "e_cruiser", "len": 300.0, "speed": 62.0, "w": 0.09, "title": "Крейсер «Сторож»"},
	"leviathan": {"tex": "e_leviathan", "len": 450.0, "speed": 44.0, "w": 0.11, "title": "«Левиафан»"},
}
const SHIP_LINES := {
	"spawn": ["Крейсер на позиции. Воздух — ваш.", "Всем башням: цель воздушная, огонь по готовности.", "Пролив наш. Сбейте его."],
	"run": ["Зенитчики, заградительный!", "Пуск! Пуск!", "Держать его в секторе!"],
	"angry": ["Пробоина! Аварийные партии на палубу!", "Крен на борт… продолжать огонь!", "Поднять вертолёт!"],
	"down": ["Корабль тонет! Все наверх!", "Пожар в погребах… покинуть корабль!"],
}

var _route: Convoy
var _s := 0.0
var _dir := 1.0
var _len_px := 0.0
var _flak_cd := 1.0
var _flak_n := 0
var _sam_cd := 5.0
var _sam_lock := 0.0
var _heli_at := [0.7, 0.35]
var _drone_cd := 6.0
var _ring_cd := 3.0
var _hdg := 0.0


func setup_ship(v: String, hp_total: float, near: Vector2) -> void:
	setup(v, hp_total)
	var sp: Dictionary = SPEC[v]
	title = sp["title"]
	_len_px = float(sp["len"]) * Tuning.g("unit_scale")
	radius = _len_px * float(sp["w"]) * 1.6
	is_ground = true
	contact_damage = 0.0
	min_life = 40.0 if v == "leviathan" else 30.0
	# фарватер через точку у игрока; корабль — в 1 600 пикс. по маршруту, идёт навстречу
	_route = Convoy.sea_route(near, Vector2.from_angle(randf() * TAU))
	var s0 := _route._s_of(near)
	var back := s0 > _route.length * 0.5
	_s = clampf(s0 + (-1700.0 if back else 1700.0), 0.0, _route.length)
	_dir = 1.0 if back else -1.0
	anchor = _route.point_at(_s)
	position = anchor
	_hdg = (_route.dir_at(_s) * _dir).angle()
	heading = _hdg
	Main.I.sfx.play("ship_horn")   # гудок на подходе (PR #211)


func _exit_tree() -> void:
	if _route != null and is_instance_valid(_route):
		_route.free()
		_route = null


func kind() -> String:
	return "корабли"


func say(key: String) -> void:
	if _say_t > 0.0 and key != "down":
		return
	_say_t = 6.0
	var arr: Array = SHIP_LINES[key]
	Main.I.radio(title, arr[randi() % arr.size()])


func phase() -> int:
	var f := hp / maxf(max_hp, 1.0)
	return 1 if f > 0.66 else (2 if f > 0.33 else 3)


func behave(delta: float) -> void:
	_t += delta
	_since_hit += delta
	if _since_hit > 5.0 and shield < shield_max:
		shield = minf(shield_max, shield + shield_max * 0.1 * delta)
	_say_t -= delta
	var p := Main.I.player
	_sail(delta, p)
	if p == null or p.hp <= 0.0:
		return
	if not _said_angry and angry() < 1.0:
		_said_angry = true
		_say_t = 0.0
		say("angry")
	var d := global_position.distance_to(p.global_position)
	_flak(delta, p, d)
	_sam(delta, p, d)
	if variant == "cruiser":
		if not _heli_at.is_empty() and hp < max_hp * float(_heli_at[0]):
			_heli_at.pop_front()
			_launch_heli(p)
	else:
		var ph := phase()
		if ph >= 2:
			_drone_cd -= delta
			if _drone_cd <= 0.0:
				_drone_cd = 13.0 if ph == 2 else 10.0
				_launch_drones(p, 4 if ph == 2 else 6)
		if ph >= 3:
			_ring_cd -= delta
			if _ring_cd <= 0.0 and d < 1100.0:
				_ring_cd = 2.8
				_main_battery()


## Ход по фарватеру: к игроку вдоль маршрута, у конца маршрута — разворот; курс плавный, циркуляция широкая
func _sail(delta: float, p: Player) -> void:
	if _route == null:
		return
	if p != null:
		var sp := _route._s_of(p.global_position) if Engine.get_process_frames() % 20 == 0 else -1.0
		if sp >= 0.0 and absf(sp - _s) > 900.0:
			_dir = signf(sp - _s)
	if _s <= 10.0:
		_dir = 1.0
	elif _s >= _route.length - 10.0:
		_dir = -1.0
	var spd := float(SPEC[variant]["speed"]) * (1.3 if variant == "leviathan" and phase() == 3 else 1.0)
	_s = clampf(_s + _dir * spd * delta, 0.0, _route.length)
	anchor = _route.point_at(_s)
	_hdg = rotate_toward(_hdg, (_route.dir_at(_s) * _dir).angle(), deg_to_rad(9.0) * delta)
	heading = _hdg


## Зенитные башни: очереди по 4 пули с носовой и кормовой башни, упреждение как у остальных врагов
func _flak(delta: float, p: Player, d: float) -> void:
	_flak_cd -= delta
	if _flak_cd > 0.0 or d > 950.0:
		return
	var fw := Vector2.from_angle(heading)
	var lev := variant == "leviathan"
	var guns := [0.3, -0.3] if not lev else [0.36, 0.12, -0.12, -0.36]
	var g: float = guns[_flak_n % guns.size()]
	var c := global_position
	global_position = c + fw * g * _len_px
	fire_at_player(randf_range(-0.07, 0.07), true)
	global_position = c
	_flak_n += 1
	_flak_cd = (0.16 if _flak_n % 4 != 0 else 1.1) * angry() * (0.75 if lev and phase() == 3 else 1.0)
	if _flak_n % 4 == 1:
		Main.I.sfx.play("turret_fire", -10.0, 0.7, global_position)


## ЗУР: захват (красная линия) 1,2 с, потом пуск 2 ракет («Левиафан» — 4 веером)
func _sam(delta: float, p: Player, d: float) -> void:
	if _sam_lock > 0.0:
		_sam_lock -= delta
		if _sam_lock <= 0.0:
			var to := (p.global_position - global_position).normalized()
			var n := 4 if variant == "leviathan" and phase() >= 2 else 2
			for i in n:
				Main.I.projectiles.spawn_missile(global_position, to.rotated((i - (n - 1) * 0.5) * 0.3))
			Main.I.sfx.play("sam_launch", -4.0, 0.9, global_position)
			_sam_cd = (7.0 if variant == "cruiser" else 6.0) * angry()
		return
	_sam_cd -= delta
	if _sam_cd <= 0.0 and d < 1100.0:
		_sam_lock = 1.2
		Main.I.sfx.play("sam_lock", -4.0)
		if _say_t <= 0.0:
			say("run")


func _launch_heli(p: Player) -> void:
	var h := Helicopter.new()
	h.position = global_position
	h.heading = (p.global_position - global_position).angle()
	Main.I.world.add_child(h)
	h.apply_hp_mult(Main.I.spawner.hp_mult() * Spawner.hp_ramp(Main.I.run_time))
	Main.I.show_banner("%s поднял вертолёт «Сарыч»" % title, 2.5)


func _launch_drones(p: Player, n: int) -> void:
	for i in n:
		var dr := Drone.new()
		dr.lane = (i - (n - 1) / 2.0) * 60.0
		dr.position = global_position + Vector2.from_angle(heading + PI * 0.5 * (1.0 if i % 2 == 0 else -1.0)) * 40.0
		dr.heading = (p.global_position - dr.position).angle()
		Main.I.world.add_child(dr)
		dr.apply_hp_mult(Main.I.spawner.hp_mult() * Spawner.hp_ramp(Main.I.run_time))
	Main.I.show_banner("С палубы «Левиафана» взлетают «Чайки»!", 2.0)


## Главный калибр: кольцо крупных снарядов и прицельная тройка
func _main_battery() -> void:
	var off := randf() * TAU
	for i in 22:
		var dir := Vector2.from_angle(off + TAU * i / 22.0)
		Main.I.projectiles.spawn_enemy_bullet(global_position + dir * radius, dir * 260.0, kind(), true)
	var p := Main.I.player
	if p != null:
		var to := (p.global_position - global_position).normalized()
		for j in 3:
			Main.I.projectiles.spawn_enemy_bullet(global_position + to * radius, to.rotated((j - 1) * 0.1) * 420.0, kind(), true)
	Main.I.sfx.play("explode_big", -10.0, 0.6, global_position)


# ---------- попадания: корпус — вытянутая капсула вдоль курса ----------

func _hull_dist(q: Vector2) -> float:
	var fw := Vector2.from_angle(heading)
	var a := global_position - fw * _len_px * 0.45
	var b := global_position + fw * _len_px * 0.45
	var ab := b - a
	var k := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-3), 0.0, 1.0)
	return q.distance_to(a + ab * k) - _len_px * float(SPEC[variant]["w"])


func seg_test(a: Vector2, b: Vector2) -> bool:
	for i in 5:
		if _hull_dist(a.lerp(b, i / 4.0)) < 0.0:
			return true
	return false


func aoe_dist(pos: Vector2) -> float:
	return _hull_dist(pos)


func _die() -> void:
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: warship %s sunk" % variant)
	Main.I.sfx.play("ship_sink", 0.0, 0.85 if variant == "leviathan" else 1.0, global_position)
	super()


func _draw() -> void:
	if not draw_enemy_sprite(String(SPEC[variant]["tex"]), float(SPEC[variant]["len"]), Color.WHITE, heading):
		var fw := Vector2.from_angle(heading) * _len_px * 0.5
		draw_line(-fw, fw, Color(0.5, 0.52, 0.55), _len_px * 0.16)
	if shield > 0.0:
		draw_arc(Vector2.ZERO, radius + 14.0, 0.0, TAU * shield / shield_max, 48, Color(0.5, 0.8, 1.0, 0.8), 4.0)
	if _sam_lock > 0.0:
		var p := Main.I.player
		if p != null and p.hp > 0.0:
			var a := 0.35 + 0.5 * absf(sin(_t * 30.0))
			draw_line(Vector2.ZERO, to_local(p.global_position), Color(1, 0.15, 0.1, a), 3.0)
	draw_string(Hud.ui_font(), Vector2(-140, -radius - 30.0), title, HORIZONTAL_ALIGNMENT_CENTER, 280, 18, Color(1, 0.85, 0.7))
