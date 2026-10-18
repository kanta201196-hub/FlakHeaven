class_name AASite
extends Node2D
## Активность «Удар по позиции ПВО» (по концепту): на карте появляется оборудованная позиция —
## 2 ЗСУ, ЗРК, РЛС и командный бункер. Указатель у края экрана ведёт к ней.
## Подлёт ближе 1000 пикс включает таймер 60 с. 3.5: цель — командный бункер: уничтожен бункер —
## позиция взята (внеочередной выбор карточки и запчасти), техника без командования уезжает.
## ЗСУ и ЗРК переезжают вокруг бункера, прикрывая его, ЗСУ сбивают наши ракеты и НАР.
## Не успел — позиция остаётся и продолжает стрелять, награды нет.

const LIMIT := 60.0
const ACTIVATE_R := 1000.0
const SPACING := 110.0   # тест 3.5-s4: машины позиции не ближе этого друг к другу (не «слипаются»)

var targets: Array = []
var active := false     # стреляет ли (после подлёта)
var timer := LIMIT
var done := false
var failed := false
var bunker: GroundTarget = null
var anchor := Vector2.ZERO   # 3.5: центр позиции на рельефе (логическая позиция — проекция, см. GroundTarget.air_pos)


## bunker_hp — нижняя граница прочности бункера (спавнер считает её от текущего урона игрока)
func setup(center: Vector2, hp_mult: float, bunker_hp := 0.0) -> void:
	# 3D-рельеф: техника ПВО стоит на дне долины, а не на хребте (правила — s4-landscape-rules.md)
	var tr: Terrain3D = Render3D.I.terrain if Render3D.I != null and Render3D.I.terrain != null and Render3D.I.terrain._bg != null else null
	if tr != null:
		# тест 3.5-s4 (п. 20): вся позиция (радиус ~250) — на сухом берегу, а не только её центр
		center = tr.find_floor(center, 900.0, 0.0, [], 260.0)
		var fixed := tr.fix_object({"pos": center, "size": 480.0, "name": "o_aa_site"})
		if fixed.has("pos"):   # не отвелась от воды — остаётся точка find_floor (сухое дно долины)
			center = fixed["pos"]
	global_position = center
	anchor = center
	var layout := [["bunker", Vector2.ZERO], ["zsu", Vector2(-170, -90)], ["zsu", Vector2(170, 110)],
		["sam", Vector2(140, -150)], ["radar", Vector2(-150, 140)]]
	var rot := randf() * TAU   # тест 3.5-s4: раскладка поворачивается целиком — машины не съезжаются в кучу
	for l in layout:
		var g := GroundTarget.new()
		g.setup(l[0], self, hp_mult)
		if l[0] == "bunker":
			bunker = g
			g.hp = maxf(g.hp, bunker_hp)
			g.max_hp = g.hp
		g.position = center + ((l[1] as Vector2).rotated(rot) * randf_range(0.9, 1.2) if l[0] != "bunker" else Vector2.ZERO)
		if tr != null and l[0] != "bunker":
			# своя точка рядом с назначенной, на том же берегу, не ближе SPACING к другим машинам и бункеру
			var avoid := []
			for o in targets:
				avoid.append([(o as GroundTarget).position, SPACING])
			g.position = tr.find_floor(g.position, 120.0, signf(tr.river_field(center.x, center.y)), avoid)
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


## Прочность бункера, 0–1 (для HUD)
func bunker_frac() -> float:
	if not is_instance_valid(bunker) or bunker.hp <= 0.0:
		return 0.0
	return bunker.hp / bunker.max_hp


func left() -> int:
	var n := 0
	for g in targets:
		if is_instance_valid(g) and g.hp > 0.0:
			n += 1
	return n


func on_target_destroyed(g: GroundTarget) -> void:
	if g == bunker and not done:
		# 3.5: бункер взят — позиция подавлена, остальная техника уезжает без командования
		done = true
		for t in targets:
			if is_instance_valid(t) and t != g:
				(t as GroundTarget).leaderless = true
		if not failed:
			Main.I.on_activity_success("ground")
		# активность закончена: следующая может начаться, остатки позиции убираются сами
		if Main.I.spawner != null and Main.I.spawner.activity_node == self:
			Main.I.spawner.activity_node = null
		return
	# вызывается до удаления цели; проверяем на следующем кадре
	_check_done.call_deferred()


func _check_done() -> void:
	if left() > 0:
		return
	done = true
	queue_free()


func _process(delta: float) -> void:
	global_position = GroundTarget.air_pos(anchor)
	var p := Main.I.player
	if p == null:
		return
	if not active and p.global_position.distance_to(global_position) < ACTIVATE_R:
		active = true
		Main.I.show_banner("Позиция ПВО обнаружила вас! 60 с на уничтожение", 3.0)
		Main.I.sfx.play("aa_alert", -2.0, 0.6)
	if active and not failed and not done:
		timer -= delta
		if timer <= 0.0:
			failed = true
			Main.I.show_banner("Позиция ПВО устояла — награды не будет", 3.0)
	# ушли далеко после провала или победы — остатки позиции убираем
	if (failed or done) and p.global_position.distance_to(global_position) > 2600.0:
		for g in targets:
			if is_instance_valid(g):
				g.queue_free()
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	# площадка позиции и радиус обнаружения
	draw_circle(Vector2.ZERO, 260.0, Color(0.35, 0.3, 0.2, 0.18))
	if not active and not done:
		draw_arc(Vector2.ZERO, ACTIVATE_R, 0.0, TAU, 96, Color(1.0, 0.85, 0.3, 0.12), 2.0)
