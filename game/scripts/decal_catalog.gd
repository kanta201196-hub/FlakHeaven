class_name DecalCatalog
## Plane decal art and paints (spec docs/superpowers/specs/2026-10-27-plane-decals-design.md): image id → atlas cell,
## paint id → colour. Saves keep ids, never atlas cells, so re-ordering the atlas (tools/decal_atlas.py) breaks
## no profile. Pure data, no autoloads: unit tests load it directly.

const ATLAS_PATH := "res://art/decals/decal_atlas.png"
const ATLAS_COLS := 8
const ATLAS_ROWS := 4
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
	return IMAGES.has(id)


## Kind of the image: "pic", "number" or "tally"
static func kind(id: String) -> String:
	return String((IMAGES[id] as Array)[2]) if IMAGES.has(id) else ""


## Width / height of the image (cells wide); a number's width comes from its digits instead
static func aspect(id: String) -> float:
	return float((IMAGES[id] as Array)[1]) if IMAGES.has(id) else 1.0


## Atlas rect (UV 0…1) of an atlas cell, `w` cells wide
static func cell_rect(cell: int, w: int = 1) -> Rect2:
	var col := cell % ATLAS_COLS
	var row := floori(cell / float(ATLAS_COLS))
	return Rect2(float(col) / ATLAS_COLS, float(row) / ATLAS_ROWS, float(w) / ATLAS_COLS, 1.0 / ATLAS_ROWS)


## Atlas rect of the image `id` (the whole picture; for a number — the cell of «0»)
static func image_rect(id: String) -> Rect2:
	var e: Array = IMAGES.get(id, [0, 1, "pic"])
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
