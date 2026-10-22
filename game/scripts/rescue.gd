class_name Rescue
extends Node2D
## EX-09: активность «Сбитый пилот» (операция «Сухое русло», линия «Где Гром?»).
## На земле — аварийный маяк. Подлетите — вертолёт спасателей идёт за пилотом, держите небо над маяком
## HOLD с: отсчёт идёт, пока вы ближе HOLD_R. Враги летят к маяку. Успели — выбор из редких карточек,
## пилот рассказывает, где видел парашют «Грома». Не успели за LIMIT с — вертолёт уходит без пилота.

const ACTIVATE_R := 900.0
const HOLD_R := 900.0
const HOLD := 30.0
const LIMIT := 120.0
const WAVE_EVERY := 5.0

var active := false
var timer := HOLD
var life := LIMIT
var done := false
var failed := false
var _wave_t := 2.0


func setup(center: Vector2) -> void:
	var tr := Terrain3D.active()
	if tr != null:
		center = tr.find_floor(center, 900.0, 0.0, [], AASite.FLOOR_MID, true)
	global_position = center
	z_index = 0


func _process(delta: float) -> void:
	var m := Main.I
	queue_redraw()
	if done or failed or m.state != "playing":
		return
	var p := m.player
	if p == null or p.hp <= 0.0:
		return
	life -= delta
	var d := global_position.distance_to(p.global_position)
	if not active:
		if d < ACTIVATE_R:
			active = true
			Story.say(Story.DISPATCH, "Слышу аварийный маяк! Наш пилот внизу — прикройте вертолёт.")
			Story.say("Спасатель", "Забираем! Держите небо ещё полминуты.")
			m.show_banner("Сбитый пилот: держите небо над маяком 30 с", 3.0)
	else:
		if d < HOLD_R:
			timer -= delta
		_wave_t -= delta
		if _wave_t <= 0.0:
			_wave_t = WAVE_EVERY
			_wave(p)
		if timer <= 0.0:
			_success(m)
			return
	if life <= 0.0:
		_fail(m)


## Враги идут на маяк: пара дронов с случайной стороны
func _wave(p: Player) -> void:
	var ang := randf() * TAU
	for i in 2:
		var dr := Drone.new()
		dr.lane = (i - 0.5) * 70.0
		dr.position = global_position + Vector2.from_angle(ang) * 1100.0
		Main.I.world.add_child(dr)
		dr.apply_hp_mult(Main.I.spawner.hp_mult() * Spawner.hp_ramp(Main.I.run_time))
		dr.heading = (p.global_position - dr.position).angle()


func _success(m: Main) -> void:
	done = true
	m.activities_done += 1
	Campaign.set_flag("rescued")
	m.pending_levels += 1
	m.rare_picks += 1
	m.rare_reasons.append("ЗА СПАСЁННОГО ПИЛОТА")
	m.parts += 40.0 * m.continue_mult()
	m.player.add_course_pts(1)
	m.show_banner("Пилот спасён! Награда: выбор из редких карточек и +40 запчастей", 4.0)
	Story.say("Спасённый", "Спасибо, звено. Я видел парашют «Грома» — у старых крепостей.")
	m.sfx.play("evac", -4.0, 1.3)
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: activity success rescue at %.0f" % m.run_time)
	_finish(m)


func _fail(m: Main) -> void:
	failed = true
	Story.say(Story.DISPATCH, "Вертолёт ушёл без пилота. Ищем дальше.")
	m.on_activity_failed("rescue")
	_finish(m)


func _finish(m: Main) -> void:
	if m.spawner != null and m.spawner.activity_node == self:
		m.spawner.activity_node = null
	var t := create_tween()
	t.tween_interval(4.0)
	t.tween_callback(queue_free)


## Маяк: пульсирующие кольца и круг зоны прикрытия
func _draw() -> void:
	var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	var col := Color(0.4, 1.0, 0.55) if done else (Color(0.6, 0.6, 0.6) if failed else Color(1.0, 0.35, 0.25))
	draw_circle(Vector2.ZERO, 10.0, col)
	for i in 3:
		var r := 24.0 + fmod(Time.get_ticks_msec() * 0.05 + i * 40.0, 120.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(col, 0.6 * (1.0 - r / 144.0)), 3.0)
	if active and not done and not failed:
		draw_arc(Vector2.ZERO, HOLD_R, 0.0, TAU, 96, Color(0.4, 1.0, 0.55, 0.25 + 0.15 * k), 4.0)
