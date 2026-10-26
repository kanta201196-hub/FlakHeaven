class_name Pickups
extends Node2D
## Трофеи: опыт (зелёные ромбы), ремкомплекты (белый крест) и груз конвоя (ящик с запчастями).
## Подбираются сами, если пролететь рядом: в радиусе ~4 корпусов самолёта они притягиваются.

var _t := 0.0
var items: Array[Dictionary] = [] # {"p", "kind": "xp"/"repair"/"cargo", "v": значение, "pull": bool, "spd"}


func _ready() -> void:
	z_index = 1


func drop_xp(pos: Vector2, value: float) -> void:
	# Крупные враги роняют несколько ромбов
	var n := clampi(int(value / 3.0), 1, 6)
	var each := float(value) / n
	for i in n:
		var off := Vector2.from_angle(randf() * TAU) * randf_range(0.0, 10.0 + 6.0 * n)
		items.append({"p": pos + off, "kind": "xp", "v": each, "pull": false, "spd": 0.0})
	if items.size() > 500:
		# Слишком много на карте — самые старые зачисляем сразу
		var old: Dictionary = items.pop_front()
		if old["kind"] == "xp":
			Main.I.add_xp(float(old["v"]))


## EX-10: поздний бой без бессмертия — с 10:00 ремкомплекты падают реже, к 20:00 — 40% от прежнего
const REPAIR_LATE_FROM := 600.0
const REPAIR_LATE_MIN := 0.4


static func repair_late_k(t: float) -> float:
	return lerpf(1.0, REPAIR_LATE_MIN, clampf((t - REPAIR_LATE_FROM) / 600.0, 0.0, 1.0))


func drop_repair(pos: Vector2) -> void:
	if randf() > repair_late_k(Main.I.run_time):
		return
	items.append({"p": pos, "kind": "repair", "v": 25.0, "pull": false, "spd": 0.0})


## A-03: груз сожжённого грузовика конвоя — запчасти, подбираются пролётом
func drop_cargo(pos: Vector2, value: float) -> void:
	items.append({"p": pos, "kind": "cargo", "v": value, "pull": false, "spd": 0.0})


func _process(delta: float) -> void:
	_t += delta
	var pl := Main.I.player
	if pl == null or pl.hp <= 0.0:
		queue_redraw()
		return
	var pp := pl.global_position
	var r := pl.pickup_radius()
	var any := false
	for i in range(items.size() - 1, -1, -1):
		var it := items[i]
		var p: Vector2 = it["p"]
		var d := p.distance_to(pp)
		if not it["pull"] and d < r:
			it["pull"] = true
			it["spd"] = 250.0
		if it["pull"]:
			it["spd"] = float(it["spd"]) + 2200.0 * delta
			p = p.move_toward(pp, (float(it["spd"]) + pl.velocity.length()) * delta)
			it["p"] = p
			if p.distance_to(pp) < 18.0:
				if it["kind"] == "xp":
					Main.I.add_xp(float(it["v"]))
					any = true
				elif it["kind"] == "cargo":
					Main.I.run.grant_parts(float(it["v"]), &"cargo", false)   # late bonus applied at drop
					Main.I.fx.text(pp + Vector2(0, -40), "Груз: +%d запчастей" % int(it["v"]), Color(1.0, 0.85, 0.45))
					Main.I.sfx.play("pickup", -10.0, 0.8)
				else:
					pl.heal(float(it["v"]), "box")
					Main.I.fx.text(pp + Vector2(0, -40), "+%d прочности" % int(it["v"]), Color(0.6, 1.0, 0.8))
					Main.I.sfx.play("repair", -12.0, 1.5)
				items.remove_at(i)
		elif d > 3500.0:
			items.remove_at(i)
	if any:
		Main.I.sfx.play("pickup", -18.0, randf_range(0.9, 1.2))
	queue_redraw()


## Perf (--perf) times every 2D layer's _draw: it runs in the deferred flush after _process, outside the probes
func _draw() -> void:
	var t0 := Time.get_ticks_usec() if Perf.on else 0
	_draw_layer()
	if Perf.on:
		Perf.sub("draw.pickups", t0)


## Unit XP diamond (outline, body, highlight), scaled per item by draw_set_transform.
## draw_primitive takes a convex quad as is; draw_colored_polygon triangulated every call,
## and late in a sortie up to 500 diamonds lie on the map.
const _XP_OUT := [Vector2(0, -1.35), Vector2(0.945, 0), Vector2(0, 1.35), Vector2(-0.945, 0)]
const _XP_BODY := [Vector2(0, -1), Vector2(0.7, 0), Vector2(0, 1), Vector2(-0.7, 0)]
const _XP_HI := [Vector2(0, -0.55), Vector2(0.3, -0.1), Vector2(0, 0.1), Vector2(-0.3, -0.1)]
const _XP_OUT_C := Color(0.02, 0.15, 0.08, 0.9)
const _XP_BODY_C := Color(0.35, 1.0, 0.7)
const _XP_HI_C := Color(0.9, 1.0, 0.95)
## The widest thing drawn is the XP glow: 2.2 × s, s ≤ 15 × 1.12 ≈ 17 → 37 px from the centre
const _CULL_MARGIN := 40.0

var _pts_out := PackedVector2Array(_XP_OUT)
var _pts_body := PackedVector2Array(_XP_BODY)
var _pts_hi := PackedVector2Array(_XP_HI)
var _col_out := PackedColorArray([_XP_OUT_C, _XP_OUT_C, _XP_OUT_C, _XP_OUT_C])
var _col_body := PackedColorArray([_XP_BODY_C, _XP_BODY_C, _XP_BODY_C, _XP_BODY_C])
var _col_hi := PackedColorArray([_XP_HI_C, _XP_HI_C, _XP_HI_C, _XP_HI_C])
var _no_uv := PackedVector2Array()


## Draws only the items on screen. Pickups live up to 3500 px from the player and pile up in a
## long fight (PC bench 26.10: draw.pickups + its flush grew to ~4.4 ms by 15:00), and every
## off-screen one still cost its draw commands each frame.
func _draw_layer() -> void:
	var view := (get_viewport().get_canvas_transform() * get_global_transform()).affine_inverse() * get_viewport_rect()
	view = view.grow(_CULL_MARGIN)
	for it in items:
		var p: Vector2 = it["p"]
		if not view.has_point(p):
			continue
		if it["kind"] == "xp":
			# 3.1: опыт заметнее — крупнее, тёмный контур, свечение и пульсация
			var s := (7.0 + minf(float(it["v"]), 8.0)) * (1.0 + 0.12 * sin(_t * 6.0 + p.x * 0.01))
			# рисуем в локальных координатах: на дальних участках бесконечной карты
			# мировые координаты теряют точность
			draw_set_transform(p, 0.0, Vector2(s, s))
			if Fx._soft != null:
				draw_texture_rect(Fx._soft, Rect2(-2.2, -2.2, 4.4, 4.4), false, Color(0.3, 1.0, 0.75, 0.45))
			draw_primitive(_pts_out, _col_out, _no_uv)
			draw_primitive(_pts_body, _col_body, _no_uv)
			draw_primitive(_pts_hi, _col_hi, _no_uv)
			draw_set_transform(Vector2.ZERO)
		elif it["kind"] == "cargo":
			# ящик груза: доски и обвязка, мягкое золотое свечение — видно на песке
			if Fx._soft != null:
				draw_texture_rect(Fx._soft, Rect2(p - Vector2(26, 26), Vector2(52, 52)), false, Color(1.0, 0.8, 0.3, 0.5))
			draw_rect(Rect2(p - Vector2(10, 7), Vector2(20, 14)), Color(0.15, 0.1, 0.05))
			draw_rect(Rect2(p - Vector2(9, 6), Vector2(18, 12)), Color(0.62, 0.45, 0.25))
			draw_line(p + Vector2(-9, 0), p + Vector2(9, 0), Color(0.2, 0.13, 0.07), 2.0)
		else:
			draw_circle(p, 11.0, Color(1, 1, 1, 0.25))
			draw_rect(Rect2(p - Vector2(8, 2.5), Vector2(16, 5)), Color(1, 1, 1))
			draw_rect(Rect2(p - Vector2(2.5, 8), Vector2(5, 16)), Color(1, 1, 1))
