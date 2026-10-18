class_name CloudPuffs
extends MultiMeshInstance3D
## M-31 (тест 3.5-s5, решение Kanta 18.10.2026): объёмные облака — вариант А предложения
## docs/proposals/volumetric-clouds.md. Облако — 10–22 «пуфа» (круглых клубов, повёрнутых к камере)
## на разной высоте; все пуфы всех облаков — один MultiMesh, один вызов отрисовки.
##   • Форма — по силуэту прежней текстуры облака (c_cloud1/2): пуфы ставятся туда, где силуэт плотный,
##     поэтому тень на земле (шейдер земли рисует её по той же текстуре) совпадает с облаком.
##   • Два вида: высокие кучевые (y ≈ 300–480, над самолётами, с тёмным «днищем» и светлой вершиной)
##     и низкие рваные клочья на высоте самолётов (y ≈ −50…+60) — самолёт пролетает над ними и сквозь них.
##   • Пуфы над самолётом игрока (между ним и камерой) растворяются — бой читается; у камеры — тоже.
##   • Самолёт в низком облаке — белёсая вуаль по краям экрана (центр чистый), плавный вход и выход.
## Качество графики: «Низкое» — прежние плоские облака (Render3D), «Среднее» — 10 пуфов на облако
## без вуали, «Высокое» — 15, «Максимальное» — 22.

const PUFFS := [0, 10, 15, 22]
const MAX_INST := 400
const HIGH_BASE := Vector2(300.0, 350.0)
const LOW_BASE := Vector2(-45.0, 25.0)
const FLOATS := 16                 # 12 — матрица 3×4, 4 — INSTANCE_CUSTOM

var _cache := {}                   # зерно облака → описание (пуфы в осях облака)
var _sil := []                     # силуэты текстур облака: [PackedByteArray 48×48]
var _sil_tex := []
var _gfx := -1
var _buf := PackedFloat32Array()
var _veil_layer: CanvasLayer
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var immersion := 0.0               # 0…1: насколько самолёт игрока внутри низкого облака
var shown := 0                     # сколько пуфов нарисовано в этом кадре (замер)
var fill := 0.0                    # их площадь на экране, в долях кадра (≈ сколько «экранов» прозрачной заливки)

const SIL := 48


func _init() -> void:
	name = "CloudPuffs"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = MAX_INST
	mm.visible_instance_count = 0
	multimesh = mm
	_buf.resize(MAX_INST * FLOATS)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cloud_puff.gdshader")
	mat.render_priority = 10       # после следов и теней (прозрачные), до слоя боя (100)
	mat.set_shader_parameter("noise_tex", _noise())
	material_override = mat
	custom_aabb = AABB(Vector3(-9000, -1000, -9000), Vector3(18000, 3000, 18000))


func _ready() -> void:
	_veil_layer = CanvasLayer.new()
	_veil_layer.layer = 5           # под интерфейсом (Hud — слой 10)
	add_child(_veil_layer)
	_veil = ColorRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float k = 0.0;
uniform vec2 aspect = vec2(1.78, 1.0);
void fragment() {
	float r = length((UV - 0.5) * aspect) * 1.25;
	COLOR = vec4(0.93, 0.94, 0.96, k * smoothstep(0.22, 1.05, r));
}
"""
	_veil_mat.shader = sh
	_veil.material = _veil_mat
	_veil.visible = false
	_veil_layer.add_child(_veil)


## Шум для клубов: 4 варианта — четверти одной картинки 256×256
func _noise() -> Texture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 31
	n.frequency = 0.022
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.fractal_gain = 0.55
	var img := n.get_seamless_image(256, 256)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Силуэт текстуры облака (альфа, 48×48) — где ставить пуфы
func _silhouette(t: Texture2D) -> PackedByteArray:
	var i := _sil_tex.find(t)
	if i >= 0:
		return _sil[i]
	var out := PackedByteArray()
	out.resize(SIL * SIL)
	var img: Image = t.get_image() if t != null else null
	if img != null and img.is_compressed():
		img.decompress()
	if img != null and not img.is_compressed():
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(SIL, SIL, Image.INTERPOLATE_BILINEAR)
		for y in SIL:
			for x in SIL:
				out[y * SIL + x] = int(img.get_pixel(x, y).a * 255.0)
	else:   # запасной круг
		for y in SIL:
			for x in SIL:
				var d := Vector2(x + 0.5 - SIL * 0.5, y + 0.5 - SIL * 0.5).length() / (SIL * 0.5)
				out[y * SIL + x] = int(clampf(1.2 - d * 1.4, 0.0, 1.0) * 255.0)
	_sil_tex.append(t)
	_sil.append(out)
	return out


## Описание облака по его зерну: вид, высота, пуфы [смещение x, высота, смещение z, поперечник, тон, альфа, поворот, вариант+рваность]
func _make(it: Array, gfx: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(it[4]) ^ 0x5eed
	var low := rng.randf() < Tuning.g("cloud_low")
	var sil := _silhouette(it[3])
	var size: float = it[1]
	var rot: float = it[2]
	var n: int = PUFFS[gfx] if not low else maxi(6, int(PUFFS[gfx] * 0.8))
	var base := rng.randf_range(LOW_BASE.x, LOW_BASE.y) if low else rng.randf_range(HIGH_BASE.x, HIGH_BASE.y)
	var a0 := Tuning.g("cloud_alpha")
	var puffs: Array = []
	var tries := 0
	var hsum := 0.0
	while puffs.size() < n and tries < 400:
		tries += 1
		var u := rng.randf() - 0.5
		var v := rng.randf() - 0.5
		var a := float(sil[clampi(int((v + 0.5) * SIL), 0, SIL - 1) * SIL + clampi(int((u + 0.5) * SIL), 0, SIL - 1)]) / 255.0
		if a < 0.3 + 0.25 * rng.randf():
			continue
		var off := Vector2(u * cos(rot) - v * sin(rot), u * sin(rot) + v * cos(rot)) * size
		var y: float
		var dia: float
		var tone: float
		var al: float
		var wisp: float
		if low:
			y = base + rng.randf_range(-28.0, 28.0)
			dia = size * rng.randf_range(0.3, 0.45) * (0.7 + 0.4 * a)
			tone = rng.randf_range(0.65, 0.95)
			al = a0 * rng.randf_range(0.55, 0.75)
			wisp = 0.45
		elif puffs.size() < 2:
			# «днище»: широкие плоские тёмные клубы у основания — снизу облако темнее
			y = base - 12.0
			dia = size * rng.randf_range(0.42, 0.52)
			tone = 0.0
			al = a0 * 0.75
			wisp = 0.25
		else:
			# кучевая шапка: где силуэт плотнее — выше и крупнее, вершина светлая
			var lift := a * rng.randf_range(50.0, 150.0)
			y = base + lift
			dia = size * rng.randf_range(0.22, 0.36) * (0.65 + 0.45 * a)
			tone = clampf(0.25 + lift / 150.0 * 0.8, 0.0, 1.0)
			al = a0 * (0.75 + 0.25 * a)
			wisp = 0.12
		hsum += y
		puffs.append([off.x, y, off.y, dia, tone, al, rng.randf() * TAU, float(rng.randi() % 4) + wisp])
	puffs.sort_custom(func(p: Array, q: Array) -> bool: return float(p[1]) < float(q[1]))
	return {"low": low, "puffs": puffs, "h": hsum / maxf(puffs.size(), 1.0) if not puffs.is_empty() else base,
		"r": size * 0.75, "size": size}


## Описание облака (для теней на земле: средняя высота и размер)
func info(it: Array) -> Dictionary:
	if it.size() < 5:
		return {}
	return _cache.get(int(it[4]), {})


## Каждый кадр из Render3D._sync_clouds. focus — точка, над которой облака растворяются (самолёт игрока
## на заставке — ведущий звена); c2 — центр кадра на плоскости боя; d0 — расстояние камеры до него.
func sync(its: Array, cam: Camera3D, c2: Vector2, d0: float, focus: Vector3, gfx: int, delta: float) -> void:
	if gfx != _gfx:
		_gfx = gfx
		_cache.clear()
	position = Vector3(c2.x, 0.0, c2.y)
	var seen := {}
	var planes := cam.get_frustum()
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var vh := float(get_viewport().get_visible_rect().size.y)
	var fpx := vh * 0.5 / tan(deg_to_rad(cam.fov) * 0.5)
	var fdepth := (focus - cp).dot(fwd)
	var fsp := cam.unproject_position(focus) if fdepth > 1.0 else Vector2(-99999, -99999)
	var keys: Array = []
	var ent: Array = []
	var imm := 0.0
	var area := 0.0
	for it: Array in its:
		if it.size() < 5:
			continue
		var id := int(it[4])
		seen[id] = true
		if not _cache.has(id):
			_cache[id] = _make(it, gfx)
		var c: Dictionary = _cache[id]
		var gp: Vector2 = it[0]
		var center := Vector3(gp.x, float(c["h"]), gp.y)
		var r: float = c["r"] + 120.0
		var vis := true
		for pl: Plane in planes:
			if pl.distance_to(center) > r:
				vis = false
				break
		if not vis:
			continue
		var low: bool = c["low"]
		if low:
			var dxz := Vector2(focus.x - gp.x, focus.z - gp.y).length()
			if dxz < float(c["r"]) * 1.2:
				for p: Array in c["puffs"]:
					var pd := Vector2(focus.x - gp.x - p[0], focus.z - gp.y - p[2]).length()
					var rr: float = float(p[3]) * 0.5
					if absf(focus.y - float(p[1])) < rr:
						imm = maxf(imm, clampf(1.2 - pd / rr, 0.0, 1.0))
		for p: Array in c["puffs"]:
			var wp := Vector3(gp.x + p[0], p[1], gp.y + p[2])
			var depth := (wp - cp).dot(fwd)
			if depth < 5.0:
				continue
			var a: float = p[5] * smoothstep(d0 * 0.22, d0 * 0.45, depth)   # у камеры — растворяется
			if a < 0.01:
				continue
			if depth < fdepth + 40.0:
				# пуф между камерой и самолётом: чем ближе к нему на экране, тем прозрачнее
				var d := cam.unproject_position(wp).distance_to(fsp)
				var rpx: float = float(p[3]) * 0.5 * fpx / depth
				var k := clampf((d - rpx * 0.45 - 40.0) / (rpx * 0.55 + 150.0), 0.0, 1.0)
				# низкие клочья у самого самолёта не исчезают совсем — видно, что он идёт сквозь облако
				a *= lerpf(0.35 if float(p[1]) > focus.y - 60.0 and float(p[1]) < focus.y + 90.0 else 0.12, 1.0, k * k * (3.0 - 2.0 * k))
				if a < 0.01:
					continue
			var rr2: float = float(p[3]) * 0.5 * fpx / depth
			area += 4.0 * rr2 * rr2   # квадрат клуба целиком (столько пикселей рисует видеокарта)
			keys.append(Vector2(-depth, ent.size()))
			ent.append([wp, p[3], p[6], p[7], p[4], a])
			if ent.size() >= MAX_INST:
				break
		if ent.size() >= MAX_INST:
			break
	for id in _cache.keys():
		if not seen.has(id):
			_cache.erase(id)
	keys.sort()   # дальние раньше: прозрачные пуфы — от дальнего к ближнему
	var n := keys.size()
	var o := 0
	for kv: Vector2 in keys:
		var e: Array = ent[int(kv.y)]
		var wp: Vector3 = e[0]
		var s: float = e[1]
		_buf[o] = s; _buf[o + 1] = 0.0; _buf[o + 2] = 0.0; _buf[o + 3] = wp.x - c2.x
		_buf[o + 4] = 0.0; _buf[o + 5] = s; _buf[o + 6] = 0.0; _buf[o + 7] = wp.y
		_buf[o + 8] = 0.0; _buf[o + 9] = 0.0; _buf[o + 10] = s; _buf[o + 11] = wp.z - c2.y
		_buf[o + 12] = e[2]; _buf[o + 13] = e[3]; _buf[o + 14] = e[4]; _buf[o + 15] = e[5]
		o += FLOATS
	if n > 0:
		multimesh.buffer = _buf
	multimesh.visible_instance_count = n
	shown = n
	var vs := get_viewport().get_visible_rect().size
	fill = area / maxf(vs.x * vs.y, 1.0)
	# вуаль «внутри облака» (Высокое и Максимальное): плавный вход и выход
	var target := imm if gfx >= 2 else 0.0
	immersion = move_toward(immersion, target, delta * (2.5 if target > immersion else 1.5))
	_set_veil(immersion)


func _set_veil(k: float) -> void:
	if _veil == null:
		return
	_veil.visible = k > 0.005 and visible
	if _veil.visible:
		var vs := get_viewport().get_visible_rect().size
		_veil_mat.set_shader_parameter("k", k * 0.55)
		_veil_mat.set_shader_parameter("aspect", Vector2(vs.x / maxf(vs.y, 1.0), 1.0))


func hide_all() -> void:
	visible = false
	multimesh.visible_instance_count = 0
	shown = 0
	immersion = 0.0
	_set_veil(0.0)
