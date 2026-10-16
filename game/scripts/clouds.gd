class_name Clouds
extends Node2D
## Облака выше самолётов (2.6): полупрозрачные, с параллаксом (летят «выше» — смещаются быстрее земли),
## медленный ветер, тень на земле. Около самолёта игрока становятся прозрачнее — не мешают бою.

const CHUNK := 2200.0
const CHANCE := 0.45
const PARALLAX := 0.35   # насколько облака «выше»: 0 — на земле
const WIND := Vector2(14.0, 6.0)

var _tex: Array = []
var _t := 0.0
var shadows: CloudShadows


func _ready() -> void:
	z_index = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in [1, 2]:
		var p := "res://art/objects/c_cloud%d.png" % i
		if ResourceLoader.exists(p):
			_tex.append(load(p))
	shadows = CloudShadows.new()
	shadows.owner_clouds = self


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if is_instance_valid(shadows):
		shadows.queue_redraw()


func view() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2()
	var center := cam.get_screen_center_position()
	var half := get_viewport_rect().size / cam.zoom * 0.5
	return Rect2(center - half, half * 2.0)


## Список облаков вокруг камеры: [мировая точка «на земле», размер, поворот, текстура]
func items() -> Array:
	var out: Array = []
	if _tex.is_empty():
		return out
	var v := view()
	if v.size == Vector2.ZERO:
		return out
	var drift := WIND * _t
	var g := v.grow(1600.0)
	g.position -= drift
	var rng := RandomNumberGenerator.new()
	for cx in range(int(floorf(g.position.x / CHUNK)), int(floorf(g.end.x / CHUNK)) + 1):
		for cy in range(int(floorf(g.position.y / CHUNK)), int(floorf(g.end.y / CHUNK)) + 1):
			rng.seed = hash(Vector2i(cx, cy)) ^ 0xc10d
			if rng.randf() > CHANCE:
				continue
			var p := Vector2((cx + rng.randf()) * CHUNK, (cy + rng.randf()) * CHUNK) + drift
			out.append([p, rng.randf_range(420.0, 700.0), rng.randf() * TAU, _tex[rng.randi() % _tex.size()]])
	return out


func _draw() -> void:
	if Render3D.enabled:
		return
	var v := view()
	var cam_c := v.get_center()
	var player_pos := cam_c
	if Main.I != null and is_instance_valid(Main.I.player):
		player_pos = Main.I.player.global_position
	for it in items():
		var ground_p: Vector2 = it[0]
		var p := ground_p + (ground_p - cam_c) * PARALLAX # выше — быстрее уходит к краям
		var size: float = it[1] * (1.0 + PARALLAX)
		if not v.grow(size).has_point(p):
			continue
		var t: Texture2D = it[3]
		var k := size / float(t.get_width())
		var a := 0.42
		var d := p.distance_to(player_pos)
		a *= clampf((d - size * 0.15) / (size * 0.45), 0.25, 1.0) # над самолётом — прозрачнее
		draw_set_transform(p, it[2], Vector2(k, k))
		draw_texture(t, -t.get_size() / 2.0, Color(1, 1, 1, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class CloudShadows:
	extends Node2D
	var owner_clouds: Clouds

	func _ready() -> void:
		z_index = -8

	func _draw() -> void:
		if owner_clouds == null or Render3D.enabled:   # в 3D тень облаков рисует шейдер земли
			return
		var v := owner_clouds.view()
		for it in owner_clouds.items():
			var p: Vector2 = it[0] + Vector2(160.0, 240.0) # солнце сверху-слева — тень вниз-вправо
			var size: float = it[1]
			if not v.grow(size).has_point(p):
				continue
			var t: Texture2D = it[3]
			var k := size / float(t.get_width())
			draw_set_transform(p, it[2], Vector2(k, k))
			draw_texture(t, -t.get_size() / 2.0, Color(0.05, 0.04, 0.02, 0.22))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
