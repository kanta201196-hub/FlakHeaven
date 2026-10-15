class_name AASite
extends Node2D
## Активность «Удар по позиции ПВО» (по концепту): на карте появляется оборудованная позиция —
## 2 ЗСУ, ЗРК, РЛС и командный бункер. Указатель у края экрана ведёт к ней.
## Подлёт ближе 1000 пикс включает таймер 60 с. Уничтожил всё — внеочередное повышение уровня
## и запчасти. Не успел — позиция остаётся и продолжает стрелять, награды нет.

const LIMIT := 60.0
const ACTIVATE_R := 1000.0

var targets: Array = []
var active := false     # стреляет ли (после подлёта)
var timer := LIMIT
var done := false
var failed := false


func setup(center: Vector2, hp_mult: float) -> void:
	# 3D-рельеф: техника ПВО стоит на дне долины, а не на хребте (правила — s4-landscape-rules.md)
	if Render3D.I != null and Render3D.I.terrain != null and Render3D.I.terrain._bg != null:
		center = Render3D.I.terrain.find_floor(center)
	global_position = center
	var layout := [["bunker", Vector2.ZERO], ["zsu", Vector2(-170, -90)], ["zsu", Vector2(170, 110)],
		["sam", Vector2(140, -150)], ["radar", Vector2(-150, 140)]]
	for l in layout:
		var g := GroundTarget.new()
		g.setup(l[0], self, hp_mult)
		g.position = center + (l[1] as Vector2).rotated(randf() * TAU) * randf_range(0.9, 1.2)
		if Render3D.I != null and Render3D.I.terrain != null and Render3D.I.terrain._bg != null:
			g.position = Render3D.I.terrain.find_floor(g.position, 260.0)
		targets.append(g)


func _ready() -> void:
	z_index = -3
	for g in targets:
		Main.I.world.add_child.call_deferred(g)


func radar_alive() -> bool:
	for g in targets:
		if is_instance_valid(g) and g.variant == "radar" and g.hp > 0.0:
			return true
	return false


func left() -> int:
	var n := 0
	for g in targets:
		if is_instance_valid(g) and g.hp > 0.0:
			n += 1
	return n


func on_target_destroyed(_g: GroundTarget) -> void:
	# вызывается до удаления цели; проверяем на следующем кадре
	_check_done.call_deferred()


func _check_done() -> void:
	if done or left() > 0:
		return
	done = true
	if not failed:
		Main.I.on_activity_success("ground")
	queue_free()


func _process(delta: float) -> void:
	var p := Main.I.player
	if p == null:
		return
	if not active and p.global_position.distance_to(global_position) < ACTIVATE_R:
		active = true
		Main.I.show_banner("Позиция ПВО обнаружила вас! 60 с на уничтожение", 3.0)
		Main.I.sfx.play("lock", -2.0, 0.6)
	if active and not failed and not done:
		timer -= delta
		if timer <= 0.0:
			failed = true
			Main.I.show_banner("Позиция ПВО устояла — награды не будет", 3.0)
	# ушли далеко после провала — позицию убираем
	if failed and p.global_position.distance_to(global_position) > 3000.0:
		for g in targets:
			if is_instance_valid(g):
				g.queue_free()
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	# площадка позиции и радиус обнаружения
	draw_circle(Vector2.ZERO, 260.0, Color(0.35, 0.3, 0.2, 0.18))
	if not active:
		draw_arc(Vector2.ZERO, ACTIVATE_R, 0.0, TAU, 96, Color(1.0, 0.85, 0.3, 0.12), 2.0)
