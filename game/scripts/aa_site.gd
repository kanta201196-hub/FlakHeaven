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
const FLOOR_MID := 200.0 # тест 3.5-s7: середина ровного дна долины, px от линии реки (точка спасения пилота)
const ACROSS := 90.0     # поперёк долины машины не дальше этого от центра — не заезжают на склон
## Kanta 24.10 (repeated rule): by the river only the convoy on its road. The bunker stands at least
## RIVER_MIN px from the river line (valley floor ends at 260, road edge at 107), vehicles and their
## moves at least CAR_RIVER_MIN; never in a river or a village stream. Level ground at any height
## counts: wide fans, hill flats, mesa tops (RV-01 relief).
const RIVER_MIN := 430.0
const CAR_RIVER_MIN := 320.0

var targets: Array = []
var active := false     # стреляет ли (после подлёта)
var timer := LIMIT
var done := false
var failed := false
var bunker: GroundTarget = null
var anchor := Vector2.ZERO   # 3.5: центр позиции на рельефе (логическая позиция — проекция, см. GroundTarget.air_pos)


func setup(center: Vector2, hp_mult: float, dps := 0.0) -> void:
	var rot := randf() * TAU   # тест 3.5-s4: раскладка поворачивается целиком — машины не съезжаются в кучу
	var spots := place(Terrain3D.active(), center, rot, randf_range(0.9, 1.2))
	center = spots[0]
	global_position = center
	anchor = center
	var kinds := ["bunker", "zsu", "zsu", "sam", "radar"]
	for i in kinds.size():
		var g := GroundTarget.new()
		g.setup(kinds[i], self, hp_mult, dps)
		if kinds[i] == "bunker":
			bunker = g
		g.position = spots[i]
		targets.append(g)


## Where the site stands: [bunker, zsu, zsu, sam, radar] world points (pure placement, unit-tested
## in game/tests/aa_site_test.gd). tr null (2D) — layout around center as is.
## Bunker: level ground at least RIVER_MIN from the river, nearest to center; vehicles around it
## along the valley, on the same bank, at least CAR_RIVER_MIN from the river, not in water.
static func place(tr: Terrain3D, center: Vector2, rot: float, spread_k := 1.0) -> PackedVector2Array:
	var along := Vector2.ZERO
	if tr != null:
		var at := tr.find_floor(center, 900.0, 0.0, [], RIVER_MIN, true, INF)
		if not tr.flat_at(at, 0.0, INF) or absf(tr.river_field(at.x, at.y)) < RIVER_MIN:
			# around center only slopes or the river: off the valley floor on the nearest bank
			at = tr.find_floor(tr.floor_near(center, RIVER_MIN + 40.0), 600.0, 0.0, [], RIVER_MIN, true, INF)
		if not tr.flat_at(at, 0.0, INF) or absf(tr.river_field(at.x, at.y)) < RIVER_MIN:
			at = tr.find_floor(center, 2600.0, 0.0, [], RIVER_MIN, true, INF)   # rare: wide search
		center = tr.out_of_river_guard(at, RIVER_MIN - Terrain3D.RIVER_GUARD)
		var e := 8.0
		var g := Vector2(tr.river_field(center.x + e, center.y) - tr.river_field(center.x - e, center.y),
			tr.river_field(center.x, center.y + e) - tr.river_field(center.x, center.y - e))
		if g.length_squared() > 1e-10:
			along = g.normalized().orthogonal()
	var out := PackedVector2Array([center])
	var offs := [Vector2(-170, -90), Vector2(170, 110), Vector2(140, -150), Vector2(-150, 140)]
	var side := signf(tr.river_field(center.x, center.y)) if tr != null else 0.0
	for o: Vector2 in offs:
		var off := o.rotated(rot) * SPREAD * spread_k
		if along != Vector2.ZERO:   # вдоль долины — полный разнос, поперёк — в пределах ровной полосы
			var a := off.dot(along)
			var c := off.dot(along.orthogonal())
			off = along * (1.0 if a >= 0.0 else -1.0) * maxf(absf(a), SPACING) * 1.3 + along.orthogonal() * clampf(c * 0.35, -ACROSS, ACROSS)
		var q := center + off
		if tr != null:
			# своя точка рядом с назначенной, на том же берегу, ровная, не ближе SPACING к другим и бункеру
			var avoid := []
			for t in out:
				avoid.append([t, SPACING])
			var want := q
			q = tr.find_floor(want, 260.0, side, avoid, CAR_RIVER_MIN, true, INF)
			if absf(tr.river_field(q.x, q.y)) < CAR_RIVER_MIN:   # canyon or cliff around: look wider
				q = tr.find_floor(want, 700.0, side, avoid, CAR_RIVER_MIN, true, INF)
			q = tr.out_of_river_guard(q, CAR_RIVER_MIN - Terrain3D.RIVER_GUARD)   # never toward the river
		out.append(q)
	return out


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
			Events.activity_succeeded.emit(&"ground")
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
		Events.banner.emit("Позиция ПВО обнаружила вас! 60 с на уничтожение", 3.0)
		Main.I.sfx.play("aa_alert", -2.0, 0.6)
	if active and not failed and not done:
		timer -= delta
		if timer <= 0.0:
			failed = true
			Events.banner.emit("Позиция ПВО устояла — награды не будет", 3.0)
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
