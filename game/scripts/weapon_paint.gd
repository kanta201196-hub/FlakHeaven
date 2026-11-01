class_name WeaponPaint
extends RefCounted
## Service paint for what the hangar shows close up (S14-13, Kanta 31.10: "natural paint for missiles, weapons
## and stands"): the hangar versions of the weapons, their pylons and the stands of the weapon store. Swaps each
## plain StandardMaterial3D of a mesh for shaders/weapon_paint.gdshader, which keeps that material's colour,
## textures, roughness and metal and adds the wear of a store in daily use (fading, grime streaks, dust, chips,
## section seams, uneven matte roughness). Glass, transparent and glowing surfaces keep their own material.
## Used by WeaponModels (hq meshes, hq pylons) and Hangar3D (stands, cradles); combat meshes are not touched.

const SHADER := preload("res://shaders/weapon_paint.gdshader")
## Ring seams between body sections, as X in body lengths from the centre (weapon_paint.gdshader `seams`).
## Missiles: seeker/guidance, warhead, motor joints; bombs: nose and tail cone joints. Others: none.
const SEAMS := {
	"missile": Vector4(-0.3, -0.06, 0.17, 0.31),
	"bomb": Vector4(-0.27, 0.22, 9.0, 9.0),
}
const MISSILES: Array[String] = ["aam", "srm", "agm", "arm"]
const BOMBS: Array[String] = ["hebomb", "bombs"]

static var _meshes := {}
static var _mats := {}


## `src` with every paintable surface in the service paint, cached per source mesh and parameters. `weapon` picks
## the seams (SEAMS: missiles and bombs; "" or anything else — none); `body_r` is the round body's radius in
## mesh units (0 — no seams); `sat` keeps that share of the colours' saturation and `tone` scales them (stands
## in loud factory colours are toned down). Returns `src` itself when it is null or not an ArrayMesh.
static func paint_mesh(src: Mesh, weapon := "", body_r := 0.0, sat := 1.0, tone := 1.0) -> Mesh:
	if not src is ArrayMesh:
		return src
	var key := "%d_%s_%.2f_%.2f" % [src.get_instance_id(), weapon, sat, tone]
	if _meshes.has(key):
		return _meshes[key]
	var am := (src as ArrayMesh).duplicate() as ArrayMesh
	var bb := src.get_aabb()
	var size := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	var seams := Vector4(9.0, 9.0, 9.0, 9.0)
	if weapon in MISSILES:
		seams = SEAMS["missile"]
	elif weapon in BOMBS:
		seams = SEAMS["bomb"]
	for si in src.get_surface_count():
		am.surface_set_material(si, paint(src.surface_get_material(si), size, body_r / maxf(size, 1e-4), seams, sat, tone))
	_meshes[key] = am
	return am


## The service-paint version of material `m` for an object `size` mesh units long; `body_r` (object lengths),
## `seams`, `sat` and `tone` as in weapon_paint.gdshader. Materials that are not a plain opaque
## StandardMaterial3D come back as they are. Cached per source material and parameters.
static func paint(m: Material, size: float, body_r := 0.0, seams := Vector4(9.0, 9.0, 9.0, 9.0), sat := 1.0,
		tone := 1.0) -> Material:
	if not m is StandardMaterial3D:
		return m
	var sm := m as StandardMaterial3D
	var nm := String(sm.resource_name).to_lower()
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.emission_enabled or nm.contains("glass"):
		return m
	var key := "%d_%.4f_%.4f_%s_%.2f_%.2f" % [sm.get_instance_id(), size, body_r, seams, sat, tone]
	if _mats.has(key):
		return _mats[key]
	var out := ShaderMaterial.new()
	out.shader = SHADER
	out.set_shader_parameter("albedo", sm.albedo_color)
	out.set_shader_parameter("use_albedo_tex", sm.albedo_texture != null)
	if sm.albedo_texture != null:
		out.set_shader_parameter("albedo_tex", sm.albedo_texture)
	out.set_shader_parameter("uv_xform", Vector4(sm.uv1_scale.x, sm.uv1_scale.y, sm.uv1_offset.x, sm.uv1_offset.y))
	out.set_shader_parameter("roughness", sm.roughness)
	out.set_shader_parameter("use_rough_tex", sm.roughness_texture != null)
	if sm.roughness_texture != null:
		out.set_shader_parameter("rough_tex", sm.roughness_texture)
		out.set_shader_parameter("rough_ch", _channel(sm.roughness_texture_channel))
	out.set_shader_parameter("metallic", sm.metallic)
	out.set_shader_parameter("use_metal_tex", sm.metallic_texture != null)
	if sm.metallic_texture != null:
		out.set_shader_parameter("metal_tex", sm.metallic_texture)
		out.set_shader_parameter("metal_ch", _channel(sm.metallic_texture_channel))
	var nrm := sm.normal_enabled and sm.normal_texture != null
	out.set_shader_parameter("use_normal_tex", nrm)
	if nrm:
		out.set_shader_parameter("normal_tex", sm.normal_texture)
		out.set_shader_parameter("normal_scale", sm.normal_scale)
	var ao := sm.ao_enabled and sm.ao_texture != null
	out.set_shader_parameter("use_ao_tex", ao)
	if ao:
		out.set_shader_parameter("ao_tex", sm.ao_texture)
		out.set_shader_parameter("ao_ch", _channel(sm.ao_texture_channel))
	out.set_shader_parameter("size", size)
	out.set_shader_parameter("body_r", body_r)
	out.set_shader_parameter("seams", seams)
	out.set_shader_parameter("sat", sat)
	out.set_shader_parameter("tone", tone)
	_mats[key] = out
	return out


## Plain service paint of colour `c` (sRGB) for code-built parts (pylons, cradles, box stands): `rough` and
## `metal` as on a StandardMaterial3D, patterns sized for an object `size` units long.
static func plain(c: Color, rough: float, metal: float, size: float) -> ShaderMaterial:
	var key := "plain_%s_%.3f_%.3f_%.4f" % [c.to_html(), rough, metal, size]
	if not _mats.has(key):
		var sm := StandardMaterial3D.new()
		sm.albedo_color = c
		sm.roughness = rough
		sm.metallic = metal
		_mats[key] = paint(sm, size)
	return _mats[key]


static func _channel(ch: BaseMaterial3D.TextureChannel) -> Vector4:
	match ch:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return Vector4(1, 0, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0, 0, 0, 1)
	return Vector4(0.299, 0.587, 0.114, 0)   # grayscale
