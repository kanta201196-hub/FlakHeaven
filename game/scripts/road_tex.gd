class_name RoadTex
extends RefCounted
## Photo textures (CC0, game/art/ground/road) for village streets, trenches and sandbags.
## Kanta 26.10: "find proper road textures", "trench and sandbag textures: replace them if they are bad"; of the
## preview looks he took the stone flagstone streets and kept the map road's own flat colour (only wider,
## Terrain3D.ROAD_W). `--roadtex=old` draws the village as before this change (bench "before" frames).

const DIR := "res://art/ground/road/"
## Street set, tile (world px; about 2.5× the photo's real size at the map scale, so the slabs still read at
## gameplay height) and tint towards the village palette. S14-14: the stones are toned to the packed earth round
## them (less saturation, no orange cast; they read as orange stripes on the ground before), and LANE_DUST — the
## dust between the stones and under the last stones of a street's edge — is that packed earth's own tone
## (measured from Forward+ frames of the Highland ground)
const LANE := "lane_flag"
const LANE_TILE := 20.0
const LANE_TINT := Color(1.04, 1.03, 1.06)
const LANE_SAT := 0.45
const LANE_DUST := Color(0.48, 0.43, 0.41)

static var _old := -1


## True with `--roadtex=old` on the command line
static func old() -> bool:
	if _old < 0:
		_old = 1 if OS.get_cmdline_user_args().has("--roadtex=old") else 0
	return _old == 1


## Trench, sandbag and street sets on the village material (adobe.gdshader)
static func apply_adobe(sm: ShaderMaterial) -> void:
	if old():
		sm.set_shader_parameter("bag_tex_on", false)
		sm.set_shader_parameter("trench_tex", false)
		return
	if ResourceLoader.exists(DIR + "bag_hessian_albedo.jpg"):
		sm.set_shader_parameter("bag_tex", load(DIR + "bag_hessian_albedo.jpg"))
		sm.set_shader_parameter("bag_nh", load(DIR + "bag_hessian_nh.jpg"))
	var trench := ResourceLoader.exists(DIR + "trench_soil_albedo.jpg") and ResourceLoader.exists(DIR + "trench_planks_albedo.jpg")
	sm.set_shader_parameter("trench_tex", trench)
	if trench:
		sm.set_shader_parameter("soil_tex", load(DIR + "trench_soil_albedo.jpg"))
		sm.set_shader_parameter("soil_nh", load(DIR + "trench_soil_nh.jpg"))
		sm.set_shader_parameter("plank_tex", load(DIR + "trench_planks_albedo.jpg"))
	if not ResourceLoader.exists(DIR + LANE + "_albedo.jpg"):
		return
	sm.set_shader_parameter("lane_tex", true)
	sm.set_shader_parameter("lane_tex_a", load(DIR + LANE + "_albedo.jpg"))
	sm.set_shader_parameter("lane_nh", load(DIR + LANE + "_nh.jpg"))
	sm.set_shader_parameter("lane_tile", LANE_TILE)
	sm.set_shader_parameter("lane_tint", Vector3(LANE_TINT.r, LANE_TINT.g, LANE_TINT.b))
	sm.set_shader_parameter("lane_sat", LANE_SAT)
	sm.set_shader_parameter("lane_dust", LANE_DUST)   # a Color: Forward+ converts it like the ground photos
