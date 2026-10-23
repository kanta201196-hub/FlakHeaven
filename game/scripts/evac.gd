class_name EvacZone
extends Node2D
## Эвакуация «коридором»: после аса на 60 с открывается маршрут из 3 ворот.
## Пролети через все по порядку — и тебя забирают. Самолёт не обязан тормозить или кружить:
## ворота проходятся на любой скорости, а маршрут изгибается — нужно вести самолёт.

const GATES := 3
const GATE_R0 := 120.0
var GATE_R := GATE_R0   # 3.2: узел «Бак» расширяет ворота и окно
var WINDOW := 60.0

var gates: Array = []    # мировые позиции
var passed := 0
var time_left := 60.0
var _t := 0.0


func setup(from: Vector2, heading: float) -> void:
	var c: String = Main.I.cls_id
	WINDOW = Profile.evac_window(c)
	GATE_R = GATE_R0 * Profile.gate_r_k(c)
	time_left = WINDOW
	var dir := heading + randf_range(-1.0, 1.0)
	var pos := from + Vector2.from_angle(dir) * 950.0
	for i in GATES:
		gates.append(pos)
		dir += randf_range(-1.2, 1.2)
		pos += Vector2.from_angle(dir) * randf_range(650.0, 850.0)
	global_position = Vector2.ZERO


func target_pos() -> Vector2:
	return gates[mini(passed, GATES - 1)]


func _ready() -> void:
	z_index = -1


func _process(delta: float) -> void:
	_t += delta
	time_left -= delta
	var p := Main.I.player
	if p != null and p.hp > 0.0 and passed < GATES:
		if p.global_position.distance_to(gates[passed]) < GATE_R + p.radius:
			passed += 1
			Main.I.fx.ring(gates[passed - 1], GATE_R * 1.4, Color(0.5, 1.0, 0.6))
			Main.I.sfx.play("gate", -8.0, 1.0 + passed * 0.15)
			time_left += 5.0 # каждые пройденные ворота дают немного времени
			if passed >= GATES:
				Events.evac_reached.emit()
				queue_free()
				return
	if time_left <= 0.0:
		Events.evac_closed.emit()
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	# линия маршрута
	for i in range(passed, GATES - 1):
		draw_dashed_line(gates[i], gates[i + 1], Color(0.4, 1.0, 0.6, 0.25), 3.0, 18.0)
	for i in range(passed, GATES):
		var g: Vector2 = gates[i]
		var cur := i == passed
		var a := 0.9 if cur else 0.35
		draw_arc(g, GATE_R, 0.0, TAU, 48, Color(0.4, 1.0, 0.6, a), 6.0 if cur else 3.0)
		if cur:
			draw_circle(g, GATE_R, Color(0.3, 1.0, 0.5, 0.06 + 0.06 * pulse))
			draw_arc(g, GATE_R + 14.0 + 8.0 * pulse, 0.0, TAU, 48, Color(0.6, 1.0, 0.7, 0.5), 2.0)
		draw_string(Hud.ui_font(), g + Vector2(-60, 8), "%d / %d" % [i + 1, GATES], HORIZONTAL_ALIGNMENT_CENTER, 120, 26, Color(0.7, 1.0, 0.75, a))
