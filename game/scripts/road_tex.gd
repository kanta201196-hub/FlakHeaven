class_name RoadTex
extends RefCounted
## Photo textures (CC0, game/art/ground/road) for village streets, trenches and sandbags.
## Kanta 26.10: «поищи нормальные текстуры… дорог», «текстуры окопов и мешков… если плохие замени»; of the
## preview looks he took the stone flagstone streets and kept the map road's own flat colour (only wider,
## Terrain3D.ROAD_W). `--roadtex=old` draws the village as before this change (bench "before" frames).

const DIR := "res://art/ground/road/"
## Street set, tile (world px; about 2.5× the photo's real size at the map scale, so the slabs still read at
## gameplay height) and tint towards the village palette
const LANE := "lane_flag"
const LANE_TILE := 20.0
const LANE_TINT := Color(1.08, 1.0, 0.9)

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
