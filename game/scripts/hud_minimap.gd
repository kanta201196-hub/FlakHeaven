class_name HudMinimap
extends RefCounted
## Правка 24 (тест 3.5-s4): миникарта в левом нижнем углу. Север сверху, игрок в центре.
## Река — по полю долин рельефа (кэш-картинка, пересчёт при сдвиге), враги — точки,
## асы и активности — крупные значки, эвакуация и заправщик — зелёные.
## Размер и прозрачность — в настройках («Игра → Миникарта»).

const RANGE := 2600.0   # радиус обзора в мире, px
const RIVER_N := 40     # сетка кэша реки

var ctrl: Control
var _river_tex: ImageTexture = null
var _river_at := Vector2(INF, INF)


func _init(c: Control) -> void:
	ctrl = c


## Прямоугольник карты на экране (пусто — карта выключена)
static func rect(size: Vector2) -> Rect2:
	var px: float = Settings.MINIMAP_SIZES[Settings.minimap]
	if px <= 0.0:
		return Rect2()
	return Rect2(16, size.y - px - 16, px, px)


func draw(m: Main, size: Vector2) -> void:
	var r := rect(size)
	if r.size.x <= 0.0 or not is_instance_valid(m.player):
		return
	var a: float = Settings.MINIMAP_ALPHA[Settings.minimap_alpha]
	var c := r.get_center()
	var k := r.size.x * 0.5 / RANGE
	var pp := m.player.global_position
	ctrl.draw_rect(r, Color(0.04, 0.05, 0.05, 0.75 * a))
	_draw_river(r, pp, a)
	ctrl.draw_rect(r, Color(0.85, 0.75, 0.5, 0.6 * a), false, 1.5)
	# кольцо дальности пушки — масштаб для глаза
	ctrl.draw_arc(c, m.player.gun_range() * k, 0.0, TAU, 32, Color(1, 1, 1, 0.12 * a), 1.0)
	var to_map := func(wp: Vector2) -> Vector2:
		var d: Vector2 = (wp - pp) * k
		var lim := r.size.x * 0.5 - 4.0
		return c + Vector2(clampf(d.x, -lim, lim), clampf(d.y, -lim, lim))
	# враги: воздух — красные точки, наземные — оранжевые квадраты, асы — крупные малиновые
	for n in m.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0:
			continue
		var q: Vector2 = to_map.call(e.global_position)
		if e.is_boss:
			ctrl.draw_circle(q, 5.0, Color(1.0, 0.3, 0.65, a))
			ctrl.draw_arc(q, 7.5, 0.0, TAU, 16, Color(0, 0, 0, 0.7 * a), 1.5)
		elif e.is_ground:
			ctrl.draw_rect(Rect2(q - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.6, 0.25, 0.9 * a))
		elif not (e is Drone):
			ctrl.draw_circle(q, 2.2, Color(1.0, 0.3, 0.25, 0.95 * a))
		else:
			ctrl.draw_circle(q, 1.4, Color(1.0, 0.45, 0.4, 0.6 * a))
	# активность — ромб её цвета, эвакуация и заправщик — зелёные
	var node: Node = m.spawner.activity_node if m.spawner != null else null
	if is_instance_valid(node) and node is Node2D:
		var col := HudFlight.C_AA
		if node is Convoy:
			col = HudFlight.C_CONVOY
		elif node is Transport:
			col = HudFlight.C_TRANSPORT
		elif node is RivalAce:
			col = Color(1.0, 0.3, 0.35)
		_diamond(to_map.call((node as Node2D).global_position), 7.0, Color(col.r, col.g, col.b, a))
	if is_instance_valid(m.evac):
		_diamond(to_map.call(m.evac.target_pos()), 7.0, Color(0.4, 1.0, 0.5, a))
	var tk: Node2D = m.spawner.fuel.tanker if m.spawner != null and m.spawner.fuel != null else null
	if is_instance_valid(tk):
		ctrl.draw_circle(to_map.call(tk.global_position), 4.0, Color(0.45, 1.0, 0.55, a))
	for w in m.player.wingmen:
		if is_instance_valid(w) and (w as Node2D).visible:
			ctrl.draw_circle(to_map.call((w as Node2D).global_position), 2.5, Color(0.75, 0.6, 1.0, a))
	# игрок — стрелка по курсу
	var h := m.player.heading
	var tri := PackedVector2Array([c + Vector2.from_angle(h) * 8.0, c + Vector2.from_angle(h + 2.4) * 6.0, c + Vector2.from_angle(h - 2.4) * 6.0])
	ctrl.draw_colored_polygon(tri, Color(1, 1, 1, a))
	var f := Hud.ui_font()
	ctrl.draw_string_outline(f, r.position + Vector2(6, 14), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.8 * a))
	ctrl.draw_string(f, r.position + Vector2(6, 14), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.9, a))


func _diamond(p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	ctrl.draw_colored_polygon(pts, Color(0, 0, 0, 0.7 * col.a))
	var inner := PackedVector2Array([p + Vector2(0, -s + 2), p + Vector2(s - 2, 0), p + Vector2(0, s - 2), p + Vector2(-s + 2, 0)])
	ctrl.draw_colored_polygon(inner, col)


## Река: кэш-картинка по полю долин; пересчёт, когда игрок сдвинулся на 1/8 обзора
func _draw_river(r: Rect2, pp: Vector2, a: float) -> void:
	if Render3D.I == null or Render3D.I.terrain == null:
		return
	if _river_tex == null or pp.distance_to(_river_at) > RANGE / 8.0:
		var img := Image.create(RIVER_N, RIVER_N, false, Image.FORMAT_RGBA8)
		var step := RANGE * 2.0 / RIVER_N
		for iy in RIVER_N:
			for ix in RIVER_N:
				var wp := pp + Vector2((ix + 0.5) * step - RANGE, (iy + 0.5) * step - RANGE)
				var v := absf(Render3D.I.terrain.river_field(wp.x, wp.y))
				var w := clampf(1.0 - (v - Terrain3D.D_RIVER) / (step * 0.6), 0.0, 1.0)
				img.set_pixel(ix, iy, Color(0.3, 0.6, 0.85, w))
		_river_tex = ImageTexture.create_from_image(img)
		_river_at = pp
	# кэш снят в другой точке — берём из него окно под текущую позицию (за краем — крайние пиксели)
	var src := Rect2((pp - _river_at) / (RANGE * 2.0) * RIVER_N, Vector2(RIVER_N, RIVER_N))
	ctrl.draw_texture_rect_region(_river_tex, r, src, Color(1, 1, 1, 0.8 * a))
