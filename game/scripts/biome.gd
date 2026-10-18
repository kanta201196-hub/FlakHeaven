class_name Biome
extends RefCounted
## Биомы кампании (тред «Второй биом», 18.10.2026). Биом выбирается операцией кампании (Campaign.OPS, поле
## "biome") до создания мира: Background, рельеф (Terrain3D.river_field), цвета земли и воды читают Biome.cur().
## «Нагорье Шахрисанг» — долины с рекой и дорогой; «Архипелаг Таласора» — вариант A «Пролив»
## (docs/biome2/placement-variants.md): река Нагорья становится широким проливом с островами и бухтами,
## дорога — фарватером; берег поднимается тем же рельефом, что и склоны Нагорья.

const HIGHLAND := "highland"
const ARCHIPELAGO := "archipelago"

const DATA := {
	HIGHLAND: {
		"name": "Нагорье Шахрисанг",
		"sea": false,
		"relief_k": 1.0,
		# цвета зон земли (shaders/ground3d.gdshader, значения по умолчанию)
		"ground": {"zone_floor": Color(0.92, 0.88, 0.84), "zone_fan": Color(0.74, 0.71, 0.67),
			"zone_slope": Color(0.76, 0.66, 0.57), "zone_crest": Color(0.6, 0.56, 0.52),
			"rock_tint": Color(0.74, 0.66, 0.58), "scree_color": Color(0.7, 0.66, 0.6), "saturation": 0.8},
		"bg": Color(0.52, 0.47, 0.4),
	},
	ARCHIPELAGO: {
		"name": "Архипелаг Таласора",
		"sea": true,
		"strait": 1000.0,      # полуширина пролива от оси (бывшей реки), px: вода ~40 % кадра
		"isl_from": 0.34,     # острова — не ближе этой доли полуширины к оси: фарватер свободен
		"isl_freq": 1.0 / 950.0,
		"isl_thr": 0.3,       # порог шума острова (больше — островов меньше)
		"isl_k": 520.0,       # шум → px от берега острова
		"relief_k": 0.62,     # холмы островов ниже гор Нагорья
		# Средиземноморье (docs/biome2/archipelago.md): светлый песок пляжей, маквис на склонах, известняк на гребнях
		"ground": {"zone_floor": Color(0.96, 0.92, 0.8), "zone_fan": Color(0.7, 0.72, 0.56),
			"zone_slope": Color(0.62, 0.66, 0.5), "zone_crest": Color(0.8, 0.79, 0.74),
			"rock_tint": Color(0.86, 0.84, 0.78), "scree_color": Color(0.85, 0.83, 0.77), "saturation": 0.9},
		"bg": Color(0.2, 0.42, 0.52),
	},
}

static var id := HIGHLAND


static func cur() -> Dictionary:
	return DATA.get(id, DATA[HIGHLAND])


static func sea() -> bool:
	return bool(cur().get("sea", false))


static func title() -> String:
	return String(cur()["name"])


static func g(key: String, def: Variant = null) -> Variant:
	return cur().get(key, def)
