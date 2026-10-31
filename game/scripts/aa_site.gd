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
## Kanta 24.10 (repeated rule): by the river only the convoy on its road. Real distance to the river
## line (Terrain3D.river_clear): the bunker at least RIVER_REAL px, vehicles and their moves at least
## CAR_RIVER_REAL (road edge is ~107 px, so a clear ~60 px strip beyond it); never in a river or a
## village stream. Level ground at any height counts: wide fans, hill flats, mesa tops (RV-01 relief).
## RIVER_MIN / CAR_RIVER_MIN — the same in river_field units, only to steer find_floor's search
## (the field overstates distance near bends, so it is never the final check).
const RIVER_REAL := 260.0
const CAR_RIVER_REAL := 170.0
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
	setup_spots(place(Terrain3D.active(), center, rot, randf_range(0.9, 1.2)), hp_mult, dps)


## The site on spots already placed by place() ([bunker, zsu, zsu, sam, radar]): the spawner places it
## itself to check the distance from the player first (S14-04).
func setup_spots(spots: PackedVector2Array, hp_mult: float, dps := 0.0) -> void:
	var center := spots[0]
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
## Bunker: level dry ground at least RIVER_REAL from the river, near center; vehicles around it
## along the valley, on the same bank, at least CAR_RIVER_REAL from the river, not in water.
static func place(tr: Terrain3D, center: Vector2, rot: float, spread_k := 1.0) -> PackedVector2Array:
	var along := Vector2.ZERO
	if tr != null:
		center = spot(tr, center, 900.0, 0.0, [], RIVER_REAL, RIVER_MIN)
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
			q = spot(tr, q, 260.0, side, avoid, CAR_RIVER_REAL, CAR_RIVER_MIN, center)
		out.append(q)
	return out


## A point for one piece of the site near want: level, dry (no river, no village stream), on bank
## side (0 — any), not within avoid ([point, radius] pairs) and at least min_real px from the river
## line. find_floor proposes the spot (field_min steers it off the valley floor); if the real check
## fails, rings of candidates up to ~2.9 km around want are tried, nearest first, then (vehicles) a
## ring right around home — the bunker, which is farther from the river than any vehicle needs.
## Nothing fits — the level dry candidate with the largest river field (cheap guess of the farthest);
## none level and dry at all — the find_floor point pushed out of the river.
static func spot(tr: Terrain3D, want: Vector2, radius: float, side: float, avoid: Array,
		min_real: float, field_min: float, home := Vector2.INF) -> Vector2:
	var q := tr.find_floor(want, radius, side, avoid, field_min, true, INF, true)
	if _fits(tr, q, side, avoid) and tr.river_clear(q, min_real):
		return q
	var best := q
	var best_f := absf(tr.river_field(q.x, q.y)) if _fits(tr, q, side, avoid) else -1.0
	for ring in range(1, 25):
		var r := ring * 120.0
		var n := 6 + ring * 2
		var a0 := float(ring) * 0.7   # rings turned against each other: no radial gaps
		for i in n:
			var c := want + Vector2.from_angle(a0 + TAU * i / n) * r
			if not _fits(tr, c, side, avoid):
				continue
			if tr.river_clear(c, min_real):
				return c
			var f := absf(tr.river_field(c.x, c.y))
			if f > best_f:
				best_f = f
				best = c
	if home.is_finite():
		for r: float in [SPACING * 1.05, SPACING * 1.4, SPACING * 1.8]:
			for i in 16:
				var c := home + Vector2.from_angle(TAU * i / 16.0) * r
				if _fits(tr, c, side, avoid) and tr.river_clear(c, min_real):
					return c
	if best_f < 0.0:   # nothing level and dry anywhere around: at least out of the river (old behaviour)
		return tr.out_of_river_guard(q, field_min - Terrain3D.RIVER_GUARD)
	return best


## Cheap part of the site spot check: level ground at any height, out of river and stream water,
## on the given bank, clear of the avoid circles
static func _fits(tr: Terrain3D, p: Vector2, side: float, avoid: Array) -> bool:
	if side != 0.0 and signf(tr.river_field(p.x, p.y)) != side:
		return false
	for k in avoid:
		if p.distance_to(k[0]) < float(k[1]):
			return false
	return tr.flat_at(p, 0.0, INF) and not tr.in_water(p, 10.0)


func _ready() -> void:
	z_index = -3
	for g in targets:
		Main.I.world.add_child.call_deferred(g)


## Missile `who` of the site's launchers (the fortified area has its own, see FortArea).
func who() -> String:
	return "ПВО"


## May launcher g start a lock now? The AA site has no cap; FortArea limits missiles in the air.
func can_launch(_g: GroundTarget) -> bool:
	return true


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
