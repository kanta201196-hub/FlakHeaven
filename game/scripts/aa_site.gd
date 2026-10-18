class_name AASite
extends Node2D
## Активность «Удар по позиции ПВО» (по концепту): на карте появляется оборудованная позиция —
## 2 ЗСУ, ЗРК, РЛС и командный бункер. Указатель у края экрана ведёт к ней.
## Подлёт ближе 1000 пикс включает таймер 60 с. 3.5: цель — командный бункер: уничтожен бункер —
## позиция взята (внеочередной выбор карточки и запчасти), техника без командования уезжает.
## ЗСУ и ЗРК переезжают вокруг бункера, прикрывая его, ЗСУ сбивают наши ракеты и НАР.
## Не успел — позиция остаётся и продолжает стрелять, награды нет.

const LIMIT := 60.0
const ACTIVATE_R := 1150.0   # M-37: позиция шире (радиус ~200 → ~330) — обнаружение раньше на столько же
const SPACING := 150.0   # тест 3.5-s4: машины позиции не ближе этого друг к другу; M-37: 110 → 150, позиция реже
const SPREAD := 1.6      # M-37 (Kanta 18.10): позиция ПВО шире — раскладка и переезды дальше от бункера
const FLOOR_MID := 200.0 # тест 3.5-s7: центр позиции — посередине ровного дна долины (px от линии реки)
const ACROSS := 90.0     # поперёк долины машины не дальше этого от центра — не заезжают на склон
const RIVER_GUARD_CAR := Terrain3D.RIVER_GUARD + 10.0

var targets: Array = []
var active := false     # стреляет ли (после подлёта)
var timer := LIMIT
var done := false
var failed := false
var bunker: GroundTarget = null
var anchor := Vector2.ZERO   # 3.5: центр позиции на рельефе (логическая позиция — проекция, см. GroundTarget.air_pos)


func setup(center: Vector2, hp_mult: float, dps := 0.0) -> void:
	# 3D-рельеф: техника ПВО стоит на дне долины, а не на хребте (правила — s4-landscape-rules.md)
	var tr := Terrain3D.active()
	var rot := randf() * TAU   # тест 3.5-s4: раскладка поворачивается целиком — машины не съезжаются в кучу
	var along := Vector2.ZERO
	if tr != null:
		# тест 3.5-s7: вся позиция — на равнине дна долины. Ровная полоса вдоль реки ~300 px шириной,
		# позиция ~800 px: центр — посередине полосы, раскладка вытянута вдоль долины, поперёк сжата
		# (раньше центр уводили на 416 px от реки — это уже подножие склона, и машины вставали на склон)
		var at := tr.find_floor(center, 900.0, 0.0, [], FLOOR_MID, true)
		if not tr.flat_at(at):   # вокруг одни горы — на ближайшую равнину у реки
			at = tr.find_floor(tr.floor_near(center, FLOOR_MID + 20.0), 400.0, 0.0, [], FLOOR_MID, true)
		if not tr.flat_at(at):   # и там ущелье — широкий поиск (редко: ~1 позиция из 100)
			at = tr.find_floor(center, 2600.0, 0.0, [], FLOOR_MID, true)
		center = at
		center = tr.out_of_river_guard(center, 60.0)   # M-35: бункер с обваловкой — не в охранной зоне реки
		var e := 8.0
		var g := Vector2(tr.river_field(center.x + e, center.y) - tr.river_field(center.x - e, center.y),
			tr.river_field(center.x, center.y + e) - tr.river_field(center.x, center.y - e))
		if g.length_squared() > 1e-10:
			along = g.normalized().orthogonal()
	global_position = center
	anchor = center
	var layout := [["bunker", Vector2.ZERO], ["zsu", Vector2(-170, -90)], ["zsu", Vector2(170, 110)],
		["sam", Vector2(140, -150)], ["radar", Vector2(-150, 140)]]
	for l in layout:
		var g := GroundTarget.new()
		g.setup(l[0], self, hp_mult, dps)
		if l[0] == "bunker":
			bunker = g
		var off := (l[1] as Vector2).rotated(rot) * SPREAD * randf_range(0.9, 1.2) if l[0] != "bunker" else Vector2.ZERO
		if along != Vector2.ZERO and l[0] != "bunker":   # вдоль долины — полный разнос, поперёк — в пределах ровной полосы
			var a := off.dot(along)
			var c := off.dot(along.orthogonal())
			off = along * (1.0 if a >= 0.0 else -1.0) * maxf(absf(a), SPACING) * 1.3 + along.orthogonal() * clampf(c * 0.35, -ACROSS, ACROSS)
		g.position = center + off
		if tr != null and l[0] != "bunker":
			# своя точка рядом с назначенной, на том же берегу, на равнине, не ближе SPACING к другим машинам и бункеру
			var avoid := []
			for o in targets:
				avoid.append([(o as GroundTarget).position, SPACING])
			g.position = tr.find_floor(g.position, 260.0, signf(tr.river_field(center.x, center.y)), avoid, RIVER_GUARD_CAR, true)
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
	draw_circle(Vector2.ZERO, 260.0 * SPREAD, Color(0.35, 0.3, 0.2, 0.18))
	if not active and not done:
		draw_arc(Vector2.ZERO, ACTIVATE_R, 0.0, TAU, 96, Color(1.0, 0.85, 0.3, 0.12), 2.0)
