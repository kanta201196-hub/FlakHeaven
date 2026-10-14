class_name Pickups
extends Node2D
## Трофеи: опыт (зелёные ромбы) и ремкомплекты (белый крест).
## Подбираются сами, если пролететь рядом: в радиусе ~4 корпусов самолёта они притягиваются.

var _t := 0.0
var items: Array[Dictionary] = [] # {"p", "kind": "xp"/"repair", "v": значение, "pull": bool, "spd"}


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


func drop_repair(pos: Vector2) -> void:
	items.append({"p": pos, "kind": "repair", "v": 25.0, "pull": false, "spd": 0.0})


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
				else:
					pl.heal(float(it["v"]))
					Main.I.fx.text(pp + Vector2(0, -40), "+%d прочности" % int(it["v"]), Color(0.6, 1.0, 0.8))
					Main.I.sfx.play("repair", -12.0, 1.5)
				items.remove_at(i)
		elif d > 3500.0:
			items.remove_at(i)
	if any:
		Main.I.sfx.play("pickup", -18.0, randf_range(0.9, 1.2))
	queue_redraw()


func _draw() -> void:
	for it in items:
		var p: Vector2 = it["p"]
		if it["kind"] == "xp":
			# 3.1: опыт заметнее — крупнее, тёмный контур, свечение и пульсация
			var s := (7.0 + minf(float(it["v"]), 8.0)) * (1.0 + 0.12 * sin(_t * 6.0 + p.x * 0.01))
			# рисуем в локальных координатах: на дальних участках бесконечной карты
			# триангуляция полигона в мировых координатах теряет точность
			draw_set_transform(p)
			if Fx._soft != null:
				draw_texture_rect(Fx._soft, Rect2(Vector2(-s, -s) * 2.2, Vector2(s, s) * 4.4), false, Color(0.3, 1.0, 0.75, 0.45))
			var o := s * 1.35
			draw_colored_polygon(PackedVector2Array([Vector2(0, -o), Vector2(o * 0.7, 0), Vector2(0, o), Vector2(-o * 0.7, 0)]), Color(0.02, 0.15, 0.08, 0.9))
			draw_colored_polygon(PackedVector2Array([Vector2(0, -s), Vector2(s * 0.7, 0), Vector2(0, s), Vector2(-s * 0.7, 0)]), Color(0.35, 1.0, 0.7))
			draw_colored_polygon(PackedVector2Array([Vector2(0, -s * 0.55), Vector2(s * 0.3, -s * 0.1), Vector2(0, s * 0.1), Vector2(-s * 0.3, -s * 0.1)]), Color(0.9, 1.0, 0.95))
			draw_set_transform(Vector2.ZERO)
		else:
			draw_circle(p, 11.0, Color(1, 1, 1, 0.25))
			draw_rect(Rect2(p - Vector2(8, 2.5), Vector2(16, 5)), Color(1, 1, 1))
			draw_rect(Rect2(p - Vector2(2.5, 8), Vector2(5, 16)), Color(1, 1, 1))
