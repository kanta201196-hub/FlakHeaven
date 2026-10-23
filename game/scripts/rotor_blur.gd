class_name RotorBlur
## S9-22 (Kanta 23.10): вращающийся винт вертолёта выглядел чёрным пятном — тёмные лопасти (альбедо ≈ 0,17) крутились
## поверх тёмного полупрозрачного диска. Теперь лопасти в бою не рисуются (остаются втулка, гасители и комли лопастей —
## срез по радиусу в шейдере), вместо них — тонкий светло-серый диск размытия: альфа 0,22…0,40, по нему мягкие
## полосы лопастей с резким передним краем и затухающим следом, у законцовок — чуть плотнее кольцо.
## Диск — дочерний узел винта: крутится вместе с ним (render3d.gd, _rotors), полосы идут по ходу вращения.
## Лопасти и втулка в GLB — один меш (tools/blender/helicopter.py), поэтому срез шейдером, а не скрытие узла;
## разделять модель на два меша ради этого не нужно.

## Несущий винт: радиус лопастей 10,65 м · 0,0526 (масштаб GLB) ≈ 0,56; втулка с комлями — до 0,046.
## Рулевой: лопасти 1,95 м ≈ 0,10; втулка — до 0,012.

static var _disc_shader: Shader
static var _hub_shader: Shader


## Поставить диск размытия на узел винта (идемпотентно: узлы из пула уже с диском).
## face_z — винт крутится вокруг локальной Z (рулевой), иначе вокруг Y (несущий).
static func attach(rotor: MeshInstance3D, radius: float, blades: int, keep_r: float, face_z: bool) -> void:
	if rotor == null or rotor.get_node_or_null("blur") != null:
		return
	if _disc_shader == null:
		_disc_shader = Shader.new()
		_disc_shader.code = DISC
		_hub_shader = Shader.new()
		_hub_shader.code = HUB
	# лопасти: срез по радиусу, текстура и шероховатость — исходного материала
	for si in rotor.mesh.get_surface_count():
		var bm := rotor.mesh.surface_get_material(si) as BaseMaterial3D
		if bm == null:
			continue
		var hm := ShaderMaterial.new()
		hm.shader = _hub_shader
		hm.set_shader_parameter("albedo_tex", bm.albedo_texture)
		hm.set_shader_parameter("albedo_col", bm.albedo_color)
		hm.set_shader_parameter("has_normal", bm.normal_texture != null)
		if bm.normal_texture != null:
			hm.set_shader_parameter("normal_tex", bm.normal_texture)
		hm.set_shader_parameter("rough", clampf(bm.roughness, 0.8, 0.95))
		hm.set_shader_parameter("keep_r", keep_r)
		hm.set_shader_parameter("face_z", face_z)
		rotor.set_surface_override_material(si, hm)
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * radius * 2.0
	pm.orientation = PlaneMesh.FACE_Z if face_z else PlaneMesh.FACE_Y
	var dm := ShaderMaterial.new()
	dm.shader = _disc_shader
	dm.set_shader_parameter("radius", radius)
	dm.set_shader_parameter("blades", float(blades))
	dm.set_shader_parameter("hub", keep_r / radius)
	dm.set_shader_parameter("face_z", face_z)
	pm.material = dm
	var disc := MeshInstance3D.new()
	disc.name = "blur"
	disc.mesh = pm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rotor.add_child(disc)


const DISC := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.62, 0.62, 0.60);   // тонмаппер боя поднимает: на экране ≈ 0,8
uniform float radius = 0.56;
uniform float blades = 5.0;
uniform float hub = 0.08;          // доля радиуса: внутри — втулка, диска нет
uniform bool face_z = false;
uniform float a_base = 0.22;       // ровная дымка диска
uniform float a_streak = 0.18;     // полосы лопастей поверх

varying vec2 pp;

void vertex() {
	pp = (face_z ? VERTEX.xy : VERTEX.xz) / radius;
}

void fragment() {
	float r = length(pp);
	float aa = fwidth(r) + 0.004;
	float edge = 1.0 - smoothstep(1.0 - aa * 1.5, 1.0, r);
	float inner = smoothstep(hub, hub + 0.12, r);
	// полоса: резкий передний край у лопасти, затухающий след позади (винт крутится к большему углу)
	float s = fract(atan(pp.y, pp.x) * blades / 6.2831853);
	float trail = exp(-(1.0 - s) * 4.0) * (1.0 - smoothstep(0.985, 1.0, s));
	// у втулки лопасть узкая и медленная — полосы слабее, к законцовкам заметнее
	trail *= smoothstep(0.15, 0.6, r);
	float tip = smoothstep(0.86, 0.94, r) * 0.05;
	ALBEDO = tint;
	ALPHA = clamp(a_base + a_streak * trail + tip, 0.0, 0.42) * edge * inner;
}
"""

const HUB := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform bool has_normal = false;
uniform float rough = 0.85;
uniform float keep_r = 0.05;
uniform bool face_z = false;

varying float rr;

void vertex() {
	rr = length(face_z ? VERTEX.xy : VERTEX.xz);
}

void fragment() {
	if (rr > keep_r) {
		discard;
	}
	ALBEDO = texture(albedo_tex, UV).rgb * albedo_col.rgb;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	ROUGHNESS = rough;
	METALLIC = 0.1;
}
"""
