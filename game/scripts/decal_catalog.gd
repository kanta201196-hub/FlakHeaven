class_name DecalCatalog
## Plane decal art and paints (spec docs/superpowers/specs/2026-10-27-plane-decals-design.md): image id → atlas cell,
## paint id → colour. Saves keep ids, never atlas cells, so re-ordering the atlas (tools/decal_atlas.py) breaks
## no profile. Pure data, no autoloads: unit tests load it directly.

const ATLAS_PATH := "res://art/decals/decal_atlas.png"
const ATLAS_COLS := 8
const ATLAS_ROWS := 12   ## rows 4-11: the Deluxe pack (tools/decal_editions.py)
const DIGIT0 := 16   ## atlas cell of «0»; «1»…«9» follow
const DIGIT_W := 0.62   ## share of a cell's width a digit glyph takes (the glyphs are narrow)
const NUMBER := "number"   ## image id of a side number: the record's text gives the digits
const TALLY_MAX := 20   ## marks drawn at most in a kill tally

## image id → [atlas cell, width in cells, kind]; kind: "pic" — one picture, "tally" — a mark repeated by the count
const IMAGES := {
	"skull_winged": [0, 1, "pic"], "skull_wrench": [1, 1, "pic"], "skull_flame": [2, 1, "pic"],
	"bolt": [3, 1, "pic"], "ace_card": [4, 1, "pic"], "dice": [5, 1, "pic"], "chevrons": [6, 1, "pic"],
	"sun": [7, 1, "pic"], "wasp": [8, 1, "pic"], "rook": [9, 1, "pic"], "whale": [10, 1, "pic"],
	"cat": [11, 1, "pic"], "shark_mouth": [12, 2, "pic"], "eye": [14, 1, "pic"], "peaks": [15, 1, "pic"],
	"number": [16, 1, "number"],
	"tally_air": [26, 1, "tally"], "tally_ground": [27, 1, "tally"], "tally_bomb": [28, 1, "tally"],
	"shark_eye": [29, 1, "pic"],
}


## Deluxe pack «Набор “Эскадрилья”» (ED-04, ED-08; Kanta 06.11, two editions at launch): ten author stickers per class
## and the twenty «Хулиганский ящик» meme stickers, cells from 32 (tools/decal_editions.py). Kept out of IMAGES so the
## base editor, its unlock rules and their test stay as they are; the editor lists them only while pack_shown().
const PACK_IMAGES := {
	"wasp_missile": [32, 1, "pic"], "honeycomb": [33, 1, "pic"], "sting_arrow": [34, 1, "pic"],
	"winged_bolt": [35, 1, "pic"], "wasp_ace": [36, 1, "pic"], "reticle": [37, 1, "pic"], "swallow": [38, 1, "pic"],
	"daredevil": [39, 1, "pic"], "nose_flames": [40, 1, "pic"], "tally_wasp": [41, 1, "tally"],
	"rook_bomb": [42, 1, "pic"], "feather_dagger": [43, 1, "pic"], "horseshoe": [44, 1, "pic"],
	"sledgehammer": [45, 1, "pic"], "raven_skull": [46, 1, "pic"], "wolf_jaw": [47, 1, "pic"],
	"wrench_bolt": [48, 1, "pic"], "tank_reticle": [49, 1, "pic"], "jester": [50, 1, "pic"],
	"hourglass": [51, 1, "pic"], "whale_bomb": [52, 1, "pic"], "spout": [53, 1, "pic"], "anchor": [54, 1, "pic"],
	"wave": [55, 1, "pic"], "compass_rose": [56, 1, "pic"], "lighthouse": [57, 1, "pic"], "bomb_bow": [58, 1, "pic"],
	"owl": [59, 1, "pic"], "bear": [60, 1, "pic"], "turtle": [61, 1, "pic"], "key_f": [62, 1, "pic"],
	"gg": [63, 1, "pic"], "three_am": [64, 1, "pic"], "pixel_shades": [65, 1, "pic"], "bug_feature": [66, 1, "pic"],
	"dumbbell_wings": [67, 1, "pic"], "snail_ping": [68, 1, "pic"], "loading_bar": [69, 1, "pic"],
	"afk_zzz": [70, 1, "pic"], "pixel_heart": [71, 1, "pic"], "capybara": [72, 1, "pic"],
	"goose_wrench": [73, 1, "pic"], "rubber_duck": [74, 1, "pic"], "cute_bomb": [75, 1, "pic"],
	"baguette": [76, 1, "pic"], "arrow_gear": [77, 1, "pic"], "grumpy_navigator": [78, 1, "pic"],
	"fine_smile": [79, 1, "pic"], "bang": [80, 1, "pic"], "no_feed_whale": [81, 1, "pic"],
}

## Matte paints the player picks from (sRGB); index = position, so the shader gets a fixed array
const PAINTS := {
	"bone": Color(0.87, 0.83, 0.72), "white": Color(0.90, 0.89, 0.84), "sand": Color(0.80, 0.71, 0.53),
	"ochre": Color(0.76, 0.55, 0.22), "orange": Color(0.87, 0.56, 0.13), "rust": Color(0.67, 0.29, 0.15),
	"red": Color(0.72, 0.16, 0.10), "olive": Color(0.36, 0.40, 0.25), "teal": Color(0.20, 0.45, 0.48),
	"bluegrey": Color(0.42, 0.50, 0.58), "black": Color(0.07, 0.07, 0.075), "gunmetal": Color(0.25, 0.27, 0.29),
}
const INK := Color(0.06, 0.06, 0.065)   ## outline paint, the same on every decal
const DEFAULT_C1 := "bone"
const DEFAULT_C2 := "red"


## True when `id` names a decal image
static func has_image(id: String) -> bool:
	return IMAGES.has(id) or PACK_IMAGES.has(id)


## Atlas entry of `id` from the base set or the pack ([] when unknown)
static func _entry(id: String) -> Array:
	return IMAGES.get(id, PACK_IMAGES.get(id, []))


## True while the pack's stickers are offered in the editor. Until the Steam DLC check exists (ED-05) only the
## bench shows them (--livproposals, the same flag as the proposal liveries), so players see no change.
static func pack_shown() -> bool:
	return _pack_flag


static var _pack_flag: bool = OS.get_cmdline_user_args().has("--livproposals")


## Kind of the image: "pic", "number" or "tally"
static func kind(id: String) -> String:
	var e := _entry(id)
	return String(e[2]) if not e.is_empty() else ""


## Width / height of the image (cells wide); a number's width comes from its digits instead
static func aspect(id: String) -> float:
	var e := _entry(id)
	return float(e[1]) if not e.is_empty() else 1.0


## Atlas rect (UV 0…1) of an atlas cell, `w` cells wide
static func cell_rect(cell: int, w: int = 1) -> Rect2:
	var col := cell % ATLAS_COLS
	var row := floori(cell / float(ATLAS_COLS))
	return Rect2(float(col) / ATLAS_COLS, float(row) / ATLAS_ROWS, float(w) / ATLAS_COLS, 1.0 / ATLAS_ROWS)


## Atlas rect of the image `id` (the whole picture; for a number — the cell of «0»)
static func image_rect(id: String) -> Rect2:
	var e := _entry(id)
	if e.is_empty():
		e = [0, 1, "pic"]
	return cell_rect(int(e[0]), int(e[1]))


## Atlas rect of digit `d` (0…9), cut to the glyph's width
static func digit_rect(d: int) -> Rect2:
	var r := cell_rect(DIGIT0 + clampi(d, 0, 9))
	var cut := r.size.x * (1.0 - DIGIT_W) * 0.5
	return Rect2(r.position.x + cut, r.position.y, r.size.x * DIGIT_W, r.size.y)


## Index of a paint in PAINTS order (0 for an unknown id)
static func paint_index(id: String) -> int:
	var i := PAINTS.keys().find(id)
	return maxi(i, 0)


## All paints in index order plus the ink last (for the shader's palette array)
static func palette() -> PackedColorArray:
	var out := PackedColorArray()
	for k: String in PAINTS:
		out.append(PAINTS[k])
	out.append(INK)
	return out
