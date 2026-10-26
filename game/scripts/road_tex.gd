class_name RoadTex
extends RefCounted
## Photo textures (CC0, game/art/ground/road) for map roads and village streets, trenches and sandbags.
## Kanta 26.10: «поищи нормальные текстуры… дорог», «текстуры окопов и мешков… если плохие замени».
## Trenches and sandbags use their sets always. Roads and streets have preview looks picked with
## `--roadtex=N` (bench frames for Kanta's choice); look 0, the default, keeps the flat road colour and plain
## streets until a look is chosen. `--roadtex=old` draws everything as before this change (bench "before" frames).

const DIR := "res://art/ground/road/"

## look → road set, road tile (world px), road tint, street set, street tile (world px), street tint.
## Tiles are about 2.5× the photo's real size at the map scale (a truck ≈ 8 m ≈ 28 px), so the pattern
## still reads at gameplay height.
const LOOKS := {
	1: {"road": "road_tracks", "road_tile": 70.0, "road_tint": Color(1.02, 0.94, 0.84),
		"lane": "road_gravel", "lane_tile": 26.0, "lane_tint": Color(1.05, 0.98, 0.9)},
	2: {"road": "road_gravel", "road_tile": 26.0, "road_tint": Color(1.0, 0.95, 0.88),
		"lane": "lane_flag", "lane_tile": 20.0, "lane_tint": Color(1.08, 1.0, 0.9)},
	3: {"road": "road_sand", "road_tile": 24.0, "road_tint": Color(1.08, 1.0, 0.9),
		"lane": "lane_cobble", "lane_tile": 28.0, "lane_tint": Color(1.05, 0.98, 0.9)},
}

static var _look := -1
static var _old := false


## The look picked on the command line (`--roadtex=N`), 0 when none or unknown
static func look() -> int:
	if _look < 0:
		_look = 0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--roadtex="):
				var v := a.get_slice("=", 1)
				_old = v == "old"
				_look = int(v) if LOOKS.has(int(v)) and not _old else 0
	return _look


## Road set of the current look on the ground material (ground3d.gdshader); nothing for look 0
static func apply_ground(sm: ShaderMaterial) -> void:
	var l: Dictionary = LOOKS.get(look(), {})
	if l.is_empty() or not ResourceLoader.exists(DIR + l["road"] + "_albedo.jpg"):
		return
	sm.set_shader_parameter("road_tex", true)
	sm.set_shader_parameter("t_road", load(DIR + l["road"] + "_albedo.jpg"))
	sm.set_shader_parameter("n_road", load(DIR + l["road"] + "_nh.jpg"))
	sm.set_shader_parameter("road_tile", l["road_tile"])
	var c: Color = l["road_tint"]
	sm.set_shader_parameter("road_tint", Vector3(c.r, c.g, c.b))


## Trench, sandbag and (for a look) street sets on the village material (adobe.gdshader)
static func apply_adobe(sm: ShaderMaterial) -> void:
	look()
	if _old:
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
	var l: Dictionary = LOOKS.get(look(), {})
	if l.is_empty() or not ResourceLoader.exists(DIR + l["lane"] + "_albedo.jpg"):
		return
	sm.set_shader_parameter("lane_tex", true)
	sm.set_shader_parameter("lane_tex_a", load(DIR + l["lane"] + "_albedo.jpg"))
	sm.set_shader_parameter("lane_nh", load(DIR + l["lane"] + "_nh.jpg"))
	sm.set_shader_parameter("lane_tile", l["lane_tile"])
	var c: Color = l["lane_tint"]
	sm.set_shader_parameter("lane_tint", Vector3(c.r, c.g, c.b))
