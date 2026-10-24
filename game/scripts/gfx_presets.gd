class_name GfxPresets
extends RefCounted
## Graphics options and quality presets (UI-01 step 3, plan table «Graphics options»). Every
## option is stored as an index into its value list; a preset is one index per option. The four
## presets reproduce the old single «Качество графики» switch exactly, so nobody's picture
## changes until they touch an option (preset numbers get tuned from fps on Kanta's PC in step 5).
## Pure data and rules, unit-tested in `game/tests/gfx_presets_test.gd`; `Render3D.apply_gfx`
## turns the effective values into engine calls.

## Option ids in display order inside the graphics tab
const IDS := ["scale", "upscale", "aa", "shadows", "shadow_dist", "shadow_res", "ssao", "ssil", "glow",
	"terrain", "props", "effects"]

## Render scale, percent of the output resolution (`Viewport.scaling_3d_scale`)
const SCALES := [50, 60, 70, 80, 90, 100]
## Directional shadow atlas sizes
const SHADOW_RES := [1024, 2048, 4096, 8192]

const AA_OFF := 0
const AA_FXAA := 1
const AA_MSAA2 := 2
const AA_MSAA4 := 3
const AA_MSAA8 := 4
const AA_TAA := 5

const SHADOWS_OFF := 0
const SHADOWS_LOW := 1
const SHADOWS_MEDIUM := 2
## Godot's default soft shadow filter (soft low): what the game used before step 3
const SHADOWS_HIGH := 3
const SHADOWS_ULTRA := 4

## Value labels per option (translation keys); the list length is the option's value count
const LABELS := {
	"scale": ["50 %", "60 %", "70 %", "80 %", "90 %", "100 %"],
	"upscale": ["Билинейный", "FSR 1", "FSR 2"],
	"aa": ["Выкл", "FXAA", "MSAA 2×", "MSAA 4×", "MSAA 8×", "TAA"],
	"shadows": ["Выкл", "Низкие", "Средние", "Высокие", "Ультра"],
	"shadow_dist": ["Ближе", "Весь экран"],
	"shadow_res": ["1024", "2048", "4096", "8192"],
	"ssao": ["Выкл", "Низкое", "Среднее", "Высокое"],
	"ssil": ["Выкл", "Вкл"],
	"glow": ["Выкл", "Вкл"],
	"terrain": ["Низкая", "Средняя", "Высокая", "Максимальная"],
	"props": ["Мало", "Средне", "Много", "Максимум"],
	"effects": ["Низкое", "Среднее", "Высокое", "Максимальное"],
}

## Presets «Низкое», «Среднее», «Высокое», «Максимальное» (same names as `Settings.GFX`)
const PRESETS := [
	{"scale": 1, "upscale": 0, "aa": AA_OFF, "shadows": SHADOWS_HIGH, "shadow_dist": 1, "shadow_res": 0,
		"ssao": 0, "ssil": 0, "glow": 1, "terrain": 0, "props": 0, "effects": 0},
	{"scale": 3, "upscale": 0, "aa": AA_OFF, "shadows": SHADOWS_HIGH, "shadow_dist": 1, "shadow_res": 1,
		"ssao": 0, "ssil": 0, "glow": 1, "terrain": 1, "props": 1, "effects": 1},
	{"scale": 5, "upscale": 0, "aa": AA_OFF, "shadows": SHADOWS_HIGH, "shadow_dist": 1, "shadow_res": 2,
		"ssao": 0, "ssil": 0, "glow": 1, "terrain": 2, "props": 2, "effects": 2},
	{"scale": 5, "upscale": 0, "aa": AA_MSAA2, "shadows": SHADOWS_HIGH, "shadow_dist": 1, "shadow_res": 2,
		"ssao": 0, "ssil": 0, "glow": 1, "terrain": 3, "props": 3, "effects": 3},
]

## GPU cost of each option at its highest value, 1–5 bars, for the description panel
const COST := {"scale": 5, "upscale": 2, "aa": 4, "shadows": 3, "shadow_dist": 2, "shadow_res": 3, "ssao": 4,
	"ssil": 4, "glow": 1, "terrain": 3, "props": 3, "effects": 2}


static func count(id: String) -> int:
	return (LABELS[id] as Array).size()


## A copy of preset `i` (clamped), safe to edit.
static func preset(i: int) -> Dictionary:
	return (PRESETS[clampi(i, 0, PRESETS.size() - 1)] as Dictionary).duplicate()


## Index of the preset these options match exactly, or −1 for «Своё».
static func preset_of(opts: Dictionary) -> int:
	for i in PRESETS.size():
		var p: Dictionary = PRESETS[i]
		var same := true
		for id: String in IDS:
			if int(opts.get(id, -1)) != int(p[id]):
				same = false
				break
		if same:
			return i
	return -1


## Options loaded from settings.json: unknown keys dropped, ints restored from JSON floats,
## missing or out-of-range values taken from preset `base`.
static func sanitize(raw: Dictionary, base: int) -> Dictionary:
	var out := preset(base)
	for id: String in IDS:
		if raw.has(id):
			var v := int(raw[id])
			if v >= 0 and v < count(id):
				out[id] = v
	return out


## Whether value `v` of option `id` can be drawn by the current renderer. Compatibility in
## Godot 4.4.1 has MSAA and soft shadows but no FXAA, TAA, FSR, SSAO, SSIL or glow (checked on
## the 4.4.1 build: FXAA changes no pixel there), and the frame turns darker without sun shadows.
static func supported(id: String, v: int, forward_plus: bool) -> bool:
	if forward_plus:
		return true
	match id:
		"aa":
			return v != AA_FXAA and v != AA_TAA
		"upscale", "ssao", "ssil", "glow":
			return v == 0
		"shadows":
			return v != SHADOWS_OFF
	return true


## True when some value of option `id` needs Forward+ (shown with a «Forward+» note).
static func needs_forward_plus(id: String) -> bool:
	for v in count(id):
		if not supported(id, v, false):
			return true
	return false


## Value the engine actually gets for `id` = `v`: what the renderer cannot draw falls back to
## the nearest value it can (off for effects, low shadows instead of none).
static func fallback(id: String, v: int, forward_plus: bool) -> int:
	if supported(id, v, forward_plus):
		return v
	return SHADOWS_LOW if id == "shadows" else 0


## `fallback` applied to every option.
static func effective(opts: Dictionary, forward_plus: bool) -> Dictionary:
	var out := opts.duplicate()
	for id: String in IDS:
		out[id] = fallback(id, int(out.get(id, 0)), forward_plus)
	return out
