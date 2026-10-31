class_name Livery
## Тест 3.5-s4 (второй список), п. 35 (Kanta): выбор окраски самолёта — по 3 варианта к текущей на класс.
## Без новых текстур: каждой поверхности своего самолёта (модель ангара или боя + механизация, детали,
## створки, кормовая кабина) ставится ShaderMaterial поверх её же albedo / normal / ORM-текстур (или вершинного
## цвета у деталей). Яркость исходной текстуры даёт рисунок камуфляжа (тёмные пятна / основной тон / светлые
## пятна → цвета палитры) и мелкие детали (швы, панели); очень тёмное (сопла, ниши) не трогается.
## Стекло фонаря (тест 3.5-s5, п. 2) — отдельная поверхность «glass» (ShaderMaterial shaders/canopy_glass.tres,
## tools/blender/canopy_glass.py): одно на все окраски, здесь не перекрашивается.
## «Леопард» и «Тигр» — процедурный узор в осях модели (нос +X, верх +Y), «Классика» «Кита» и «Чёрный с красным» —
## раскладка по верху / низу и по габариту модели. Глянец — низкая шероховатость, мат — высокая.
## Один проход, без compute — GL Compatibility. Вариант без цветов — исходная окраска модели (шейдер не ставится).
## Свои знаки (Insignia) и полосы ведомых не перекрашиваются; ведомые — всегда в своей окраске.

## id → [название, тёмный, основной, светлый, шероховатость, металл, узор, цвет узора A, цвет узора B]
## Узоры: 0 — нет, 1 — леопард, 2 — тигр, 3 — верх белый, низ голубой, синие полоса по борту, киль и законцовки; 4 — красные нос, законцовки, киль;
## 5 — разрывной камуфляж: основной (песок) / тёмный (охра) / узор A (тёмно-оливково-бурый) крупными пятнами с чёткими краями,
##     узор B — светлое брюхо (тест 3.5-s6, С-1, решение Kanta 18.10: свой «Грач» и «Кит» читаются на бежевой земле);
## 6 — тёмные законцовки крыльев и стабилизатора (узор A), светлое брюхо (узор B)
## Первый вариант — окраска по умолчанию (профиль без выбора, ""); у «Грача» и «Кита» это «Песочный камуфляж»,
## исходная окраска модели («Камуфляж» / «Песок», без шейдера) — по своему id, выбор в профиле сохраняется.
const SAND_CAMO := ["sand_camo", "Песочный камуфляж", Color(0.60, 0.37, 0.18), Color(0.85, 0.77, 0.58), Color(0.91, 0.85, 0.70), 0.7, 0.05, 5,
	Color(0.19, 0.17, 0.10), Color(0.74, 0.72, 0.66)]
## «Хаки» на бежевой земле сливается (С-1, п. 2): тёмные законцовки крыльев и стабилизатора, светлое брюхо (узор 6)
const KHAKI := ["khaki", "Хаки", Color(0.36, 0.35, 0.23), Color(0.45, 0.43, 0.29), Color(0.52, 0.50, 0.35), 0.78, 0.05, 6,
	Color(0.13, 0.13, 0.09), Color(0.70, 0.73, 0.68)]
## «Классика» «Кита» (S9-21, Kanta 23.10): белая окраска на песке Нагорья под солнцем выгорала в чистый белый, в ангаре —
## глянцевые блики. Белый остаётся белым по смыслу, но грязно-светлый и матовый: тон ≈ 0,51 (sRGB) с тёплой
## примесью, шероховатость 0,88, металл 0,05; голубое брюхо и синие полосы — приглушённые. Грязь — узор 3 в шейдере.
## Тон ниже, чем кажется нужным: тонмаппер боя (Filmic, белая точка 1,0) поднимает середину — альбедо 0,58
## на солнце выходит в 245/255, 0,51 — в ≈ 215 (грязно-белый на песке); в ангаре (белая точка 1,6) — светло-серый мат.
const CLASSIC_KIT := ["classic", "Классика", Color(0.43, 0.42, 0.39), Color(0.52, 0.51, 0.48), Color(0.565, 0.555, 0.52), 0.88, 0.05, 3,
	Color(0.15, 0.28, 0.48), Color(0.37, 0.46, 0.55)]
## Kanta 27.10 (build s13, item 4) took two of the natural proposals for all three planes (pattern 7, see NATURAL):
## «Степь» — khaki, ochre and dark brown in wavy disruptive bands with hard edges; «Скальный осколок» — grey-brown
## angular splinter patches with straight masked edges. Their turrets wear the same paint (TURRET_PAINT).
const STEPPE := ["steppe", "Степь", Color(0.50, 0.40, 0.26), Color(0.53, 0.52, 0.36), Color(0.70, 0.66, 0.52), 0.88, 0.03, 7,
	Color(0.27, 0.25, 0.18), Color(0.64, 0.63, 0.56),
	{"style": 2, "scale": 4.0, "cut": Vector2(0.36, 0.22), "edge": 0.0, "fade": 0.5, "grime": 0.9, "belly": 1.0, "seed": 6.0}]
const ROCK := ["rock", "Скальный осколок", Color(0.46, 0.38, 0.30), Color(0.55, 0.53, 0.49), Color(0.70, 0.69, 0.66), 0.88, 0.03, 7,
	Color(0.31, 0.30, 0.29), Color(0.63, 0.65, 0.65),
	{"style": 1, "scale": 5.5, "cut": Vector2(0.33, 0.33), "edge": 0.0, "fade": 0.45, "grime": 0.9, "belly": 1.0, "seed": 2.0}]
## Kanta 27.10 took all ten round-2 proposals for all three planes (pattern 7, styles 0, 3, 6–12; see NATURAL for
## the params). Natural: «Лесная тень» — dark olive with brown and near-black green soft blotches; «Морской туман» —
## two close greys in big soft patches; «Вулканический пепел» — near-charcoal with grey clouds and a light speckle;
## «Тростник» — straw with long olive and brown streaks along the flow.
const FOREST := ["forest", "Лесная тень", Color(0.36, 0.29, 0.21), Color(0.33, 0.36, 0.24), Color(0.50, 0.52, 0.40), 0.88, 0.03, 7,
	Color(0.17, 0.19, 0.14), Color(0.50, 0.53, 0.47),
	{"style": 0, "scale": 7.0, "cut": Vector2(0.54, 0.60), "edge": 0.03, "fade": 0.4, "grime": 0.9, "belly": 1.0, "seed": 11.0}]
## Snow (Kanta's note on the review): the belly is a mid blue-grey, not a near-white, so a bank over snow still shows
## a darker underside, and the darker patches are a step deeper than on the review frames
const SEA_FOG := ["sea_fog", "Морской туман", Color(0.33, 0.36, 0.39), Color(0.47, 0.50, 0.51), Color(0.62, 0.63, 0.62), 0.88, 0.03, 7,
	Color(0.40, 0.43, 0.46), Color(0.56, 0.59, 0.62),
	{"style": 0, "scale": 3.0, "cut": Vector2(0.52, 0.70), "edge": 0.08, "fade": 0.35, "grime": 0.8, "belly": 1.0, "seed": 12.0}]
const ASH := ["ash", "Вулканический пепел", Color(0.33, 0.32, 0.30), Color(0.24, 0.24, 0.23), Color(0.45, 0.44, 0.42), 0.9, 0.03, 7,
	Color(0.52, 0.51, 0.48), Color(0.45, 0.45, 0.44),
	{"style": 3, "scale": 4.5, "cut": Vector2(0.55, 0.70), "edge": 0.05, "fade": 0.5, "grime": 0.8, "belly": 1.0, "seed": 13.0}]
const REED := ["reed", "Тростник", Color(0.42, 0.42, 0.27), Color(0.70, 0.62, 0.42), Color(0.80, 0.74, 0.58), 0.88, 0.03, 7,
	Color(0.40, 0.30, 0.20), Color(0.70, 0.68, 0.58),
	{"style": 6, "scale": 5.0, "cut": Vector2(0.56, 0.62), "edge": 0.02, "fade": 0.45, "grime": 0.8, "belly": 1.0, "seed": 14.0}]
## Unusual, in the spirit of «Розовый леопард» and «Тигр»: «Ослепитель» — black and white stripes, each big angular
## piece striped its own way, some stripes blue-grey; «Пиксельная фуксия» — digital camouflage, fuchsia and dark
## violet over light lilac; «Акула» — a calm grey plane with a shark mouth on the nose (NOSE); «Полярный тигр» — tiger
## stripes in graphite over white; «Ржавое железо» — bare matte metal with rust runs and panels in primer;
## «Гоночная шахматка» — yellow with a black-and-yellow chequer on the nose, wing tips and fin top.
const DAZZLE := ["dazzle", "Ослепитель", Color(0.08, 0.08, 0.09), Color(0.78, 0.78, 0.75), Color(0.82, 0.82, 0.80), 0.86, 0.03, 7,
	Color(0.35, 0.40, 0.48), Color(0.78, 0.78, 0.75),
	{"style": 7, "scale": 3.5, "cut": Vector2(0.5, 0.0), "edge": 0.0, "fade": 0.2, "grime": 0.6, "belly": 0.0, "seed": 15.0}]
const PIXEL := ["pixel", "Пиксельная фуксия", Color(0.70, 0.18, 0.48), Color(0.62, 0.58, 0.64), Color(0.72, 0.70, 0.74), 0.86, 0.03, 7,
	Color(0.25, 0.13, 0.30), Color(0.70, 0.68, 0.72),
	{"style": 8, "scale": 4.0, "cut": Vector2(0.53, 0.62), "edge": 0.0, "fade": 0.25, "grime": 0.6, "belly": 0.5, "seed": 16.0}]
const SHARK := ["shark", "Акула", Color(0.05, 0.05, 0.05), Color(0.48, 0.50, 0.50), Color(0.92, 0.90, 0.84), 0.86, 0.03, 7,
	Color(0.55, 0.06, 0.05), Color(0.74, 0.75, 0.74),
	{"style": 9, "scale": 3.0, "cut": Vector2(0.6, 1.0), "edge": 0.06, "fade": 0.3, "grime": 0.8, "belly": 1.0, "seed": 17.0}]
## Snow (Kanta's note on the review): the white is an off-white grey (0.74, not 0.80) so the sun does not burn it out
## over snow, the graphite stripes are wider (cut.x scales the stripe width) and carry on across the belly, and the
## belly is a cold mid grey, so the plane keeps a dark-light pattern and a darker underside against snow
const ARCTIC_TIGER := ["arctic_tiger", "Полярный тигр", Color(0.16, 0.17, 0.19), Color(0.74, 0.75, 0.75), Color(0.80, 0.80, 0.79), 0.86, 0.03, 7,
	Color(0.16, 0.17, 0.19), Color(0.50, 0.53, 0.57),
	{"style": 10, "scale": 1.0, "cut": Vector2(1.35, 0.5), "edge": 0.0, "fade": 0.15, "grime": 0.8, "belly": 0.85, "seed": 18.0}]
const RUST := ["rust", "Ржавое железо", Color(0.45, 0.24, 0.12), Color(0.55, 0.55, 0.53), Color(0.62, 0.62, 0.60), 0.55, 0.6, 7,
	Color(0.55, 0.58, 0.30), Color(0.55, 0.55, 0.53),
	{"style": 11, "scale": 7.0, "cut": Vector2(0.62, 0.18), "edge": 0.03, "fade": 0.1, "grime": 1.0, "belly": 0.0, "seed": 19.0}]
const CHEQUER := ["chequer", "Гоночная шахматка", Color(0.06, 0.06, 0.06), Color(0.80, 0.62, 0.12), Color(0.86, 0.74, 0.40), 0.82, 0.03, 7,
	Color(0.06, 0.06, 0.06), Color(0.80, 0.62, 0.12),
	{"style": 12, "scale": 18.0, "cut": Vector2(0.5, 0.5), "edge": 0.0, "fade": 0.3, "grime": 0.8, "belly": 0.0, "seed": 20.0}]
## The ten round-2 liveries in picker order (natural first)
const ROUND2 := [FOREST, SEA_FOG, ASH, REED, DAZZLE, PIXEL, SHARK, ARCTIC_TIGER, RUST, CHEQUER]
## Turret paint per livery: [suffix of the baked turret GLBs (turret_paint.py PALETTES "<class>_<suffix>",
## models/turrets/<turret>_<suffix>.glb), colour of the ring collar under the turret (the baked base a touch darker,
## like WeaponModels.TURRET_MODELS body for the sand camo)]. Other liveries keep the sand-camo turrets.
const TURRET_PAINT := {
	"steppe": ["steppe", Color(0.42, 0.41, 0.28)],
	"rock": ["rock", Color(0.43, 0.42, 0.38)],
	"forest": ["forest", Color(0.26, 0.29, 0.19)],
	"sea_fog": ["sea_fog", Color(0.37, 0.39, 0.40)],
	"ash": ["ash", Color(0.19, 0.19, 0.18)],
	"reed": ["reed", Color(0.55, 0.48, 0.33)],
	"dazzle": ["dazzle", Color(0.61, 0.61, 0.59)],
	"pixel": ["pixel", Color(0.48, 0.46, 0.50)],
	"shark": ["shark", Color(0.37, 0.39, 0.39)],
	"arctic_tiger": ["arctic_tiger", Color(0.58, 0.59, 0.59)],
	"rust": ["rust", Color(0.43, 0.43, 0.42)],
	"chequer": ["chequer", Color(0.63, 0.49, 0.09)],
}
const VARIANTS := {
	"fighter": [
		["classic", "Классика"],
		# Kanta 24.10: keep the neutral grey «Оса» 1 shipped with before the Highland camouflage became its own paint
		["grey", "Серый", Color(0.33, 0.35, 0.37), Color(0.42, 0.44, 0.46), Color(0.56, 0.58, 0.61), 0.8, 0.05, 0],
		["sand", "Песок", Color(0.56, 0.43, 0.29), Color(0.80, 0.69, 0.50), Color(0.88, 0.80, 0.63), 0.62, 0.05, 0],
		["black_gloss", "Чёрный глянец", Color(0.05, 0.05, 0.056), Color(0.075, 0.075, 0.082), Color(0.12, 0.12, 0.13), 0.14, 0.3, 0],
		["pink_leopard", "Розовый леопард", Color(0.86, 0.52, 0.64), Color(0.96, 0.62, 0.74), Color(1.0, 0.74, 0.83), 0.55, 0.05, 1,
			Color(0.22, 0.07, 0.13), Color(0.80, 0.36, 0.50)],
		STEPPE,
		ROCK,
		FOREST, SEA_FOG, ASH, REED, DAZZLE, PIXEL, SHARK, ARCTIC_TIGER, RUST, CHEQUER,
	],
	"attacker": [
		SAND_CAMO,
		["camo", "Камуфляж"],
		KHAKI,
		["black_matte", "Чёрный мат", Color(0.05, 0.05, 0.05), Color(0.085, 0.085, 0.085), Color(0.12, 0.12, 0.115), 0.95, 0.0, 0],
		["tiger", "Тигр", Color(0.78, 0.42, 0.10), Color(0.88, 0.50, 0.14), Color(0.93, 0.58, 0.20), 0.6, 0.05, 2,
			Color(0.05, 0.04, 0.035), Color(0.92, 0.86, 0.72)],
		STEPPE,
		ROCK,
		FOREST, SEA_FOG, ASH, REED, DAZZLE, PIXEL, SHARK, ARCTIC_TIGER, RUST, CHEQUER,
	],
	"bomber": [
		SAND_CAMO,
		["sand", "Песок"],
		CLASSIC_KIT,
		KHAKI,
		["black_red", "Чёрный с красным", Color(0.04, 0.04, 0.045), Color(0.07, 0.07, 0.075), Color(0.11, 0.11, 0.115), 0.42, 0.25, 4,
			Color(0.78, 0.07, 0.05), Color(0.0, 0.0, 0.0)],
		STEPPE,
		ROCK,
		FOREST, SEA_FOG, ASH, REED, DAZZLE, PIXEL, SHARK, ARCTIC_TIGER, RUST, CHEQUER,
	],
}

## Build s13, item 4 (Kanta 27.10: «разные варианты раскраски и камуфляжа, разнообразь, сделай естественными»):
## proposal paints for all three player planes, rendered only on the bench (--livproposals); Kanta took «Степь» and
## «Скальный осколок» (STEPPE, ROCK above), the rest stay here as bench-only proposals. Pattern 7 — natural
## camouflage in model axes: [id, name, colour 2 (c_dark), base (c_mid), sun-bleach tint (c_light), roughness, metal,
## 7, colour 3 (pat_a), belly (pat_b), params].
## params: style — 0 soft sprayed blotches, 1 hard splinter (planar cells), 2 wavy disruptive bands, 3 fine mottle
## over soft clouds, 4 one worn tone with repainted panels, 5 worn whitewash over the base, 6 long streaks along the
## flow, 7 dazzle (angular pieces, each striped its own way), 8 digital (fields built of square «pixels»), 9 plain coat
## with a shark mouth on the nose (NOSE), 10 tiger stripes (cut.x — stripe width, 1 as «Тигр»), 11 bare metal with
## rust (colour 2) and primer panels (colour 3), 12 chequer on the nose, wing tips and fin top; scale — pattern
## frequency per plane length (× CLASS_SCALE, so a bigger plane wears relatively smaller patches, as real paint
## would); cut — noise levels above which colour 2 / colour 3 show (higher — less area); edge — edge softness in
## noise units (0 — hard, with a pixel of antialiasing); fade — sun bleaching of the upper surfaces; grime — flow
## streaks, tail soot and chipping; belly — how strongly the light belly replaces the camouflage (0 — wraps round).
## Colours are fictional (no national scheme is copied); sRGB, the shader takes them as source_color.
const NATURAL := [
	["nat_dune", "Выгоревшая дюна", Color(0.52, 0.36, 0.22), Color(0.76, 0.66, 0.48), Color(0.86, 0.80, 0.68), 0.86, 0.03, 7,
		Color(0.36, 0.33, 0.22), Color(0.70, 0.70, 0.64),
		{"style": 0, "scale": 5.0, "cut": Vector2(0.52, 0.58), "edge": 0.035, "fade": 0.45, "grime": 0.8, "belly": 1.0, "seed": 1.0}],
	["nat_olive", "Старая олива", Color(0.26, 0.28, 0.18), Color(0.38, 0.37, 0.24), Color(0.55, 0.53, 0.40), 0.9, 0.03, 7,
		Color(0.50, 0.48, 0.34), Color(0.52, 0.53, 0.49),
		{"style": 4, "scale": 9.0, "cut": Vector2(0.22, 0.12), "edge": 0.0, "fade": 0.8, "grime": 1.0, "belly": 1.0, "seed": 3.0}],
	["nat_alt", "Высотная дымка", Color(0.47, 0.48, 0.48), Color(0.58, 0.58, 0.56), Color(0.68, 0.67, 0.64), 0.9, 0.03, 7,
		Color(0.40, 0.41, 0.42), Color(0.68, 0.69, 0.68),
		{"style": 3, "scale": 4.0, "cut": Vector2(0.55, 0.66), "edge": 0.06, "fade": 0.35, "grime": 0.7, "belly": 1.0, "seed": 4.0}],
	["nat_dusk", "Сумерки", Color(0.34, 0.36, 0.39), Color(0.46, 0.48, 0.50), Color(0.60, 0.60, 0.60), 0.9, 0.03, 7,
		Color(0.27, 0.28, 0.30), Color(0.62, 0.63, 0.63),
		{"style": 2, "scale": 3.2, "cut": Vector2(0.42, 0.20), "edge": 0.025, "fade": 0.4, "grime": 0.8, "belly": 1.0, "seed": 5.0}],
	["nat_clay", "Глина и пыль", Color(0.56, 0.38, 0.27), Color(0.71, 0.62, 0.50), Color(0.82, 0.77, 0.68), 0.88, 0.03, 7,
		Color(0.42, 0.35, 0.28), Color(0.68, 0.66, 0.60),
		{"style": 0, "scale": 9.0, "cut": Vector2(0.55, 0.61), "edge": 0.06, "fade": 0.5, "grime": 0.8, "belly": 0.0, "seed": 7.0}],
	["nat_frost", "Зимняя побелка", Color(0.34, 0.34, 0.24), Color(0.74, 0.72, 0.67), Color(0.78, 0.76, 0.71), 0.94, 0.02, 7,
		Color(0.56, 0.55, 0.47), Color(0.70, 0.69, 0.66),
		{"style": 5, "scale": 8.0, "cut": Vector2(0.68, 0.58), "edge": 0.03, "fade": 0.2, "grime": 0.9, "belly": 0.6, "seed": 8.0}],
]
## Pattern 7 frequency per class: battle sizes are 1.0 / 1.25 / 1.6 (PlaneClasses), so a bigger plane gets a
## finer pattern in its own model units and its patches stay about the size of the fighter's on screen
const CLASS_SCALE := {"fighter": 1.0, "attacker": 1.2, "bomber": 1.45}
## Shark mouth (style 9, «Акула») placed by each plane's own nose: [x of the mouth's front end (just behind the nose
## cone tip, the pitot probe excluded), x of its back corner, height y of the nose axis, nose radius at the back
## corner], model axes (nose +X, up +Y, plane length 1). Measured on the hangar models (cross-sections of the skin
## near the nose); the battle models share the shape and axes. The mouth is laid out in x along the nose and in the
## angle round the nose axis, so it keeps its shape on the tapering cone, and the eye is sized by the radius.
const NOSE := {
	"fighter_1": [0.425, 0.245, -0.031, 0.027],
	"fighter_2": [0.485, 0.29, -0.034, 0.045],
	"attacker_1": [0.43, 0.24, -0.06, 0.042],
	"attacker_2": [0.45, 0.25, -0.064, 0.042],
	"bomber_1": [0.44, 0.25, -0.063, 0.032],
	"bomber_2": [0.45, 0.27, -0.042, 0.031],
}

## Исходная окраска модели: [яркость основного тона (линейная), ниже этой яркости — не трогать (фонарь, сопла)]
## по гистограммам текстур ангара (у моделей боя те же текстуры, уменьшенные).
## «Оса 1» (VIS-01, Sketchfab model in the Highlands camo, sf_recipes.HIGHLAND): luminance peaks 0.027 (dark olive-brown
## spots), 0.057 (sand-brown, the main tone), 0.077 (grey-tan spots), 0.18 (blue-grey belly). Base 0.056 puts the dark
## spots in the dark band, grey-tan slightly lighter than the base, the belly in the light band; below 0.012 —
## nozzle, wells, cockpit
const SRC := {
	"fighter_1": [0.056, 0.012], "fighter_2": [0.14, 0.022],
	"attacker_1": [0.056, 0.011], "attacker_2": [0.056, 0.011],
	"bomber_1": [0.079, 0.013], "bomber_2": [0.078, 0.013],
}
## Тест 3.5-s7: хвосты мотогондол (выхлоп) — металл в карте ORM; без отдельного тона они перекрашивались в светлый
## тон окраски и под небом ангара выходили бело-голубыми «мятыми» пятнами. Темнее тона окраски (×0,7) и металлом —
## только внутри коробок выхлопа в осях модели (Godot: нос +X, верх +Y, по z — зеркально оба крыла), с мягким краем;
## одиночные пятна металла Meshy на фюзеляже, носу и коках не трогаются.
## [порог металла (B карты ORM), [x0, x1, |z|0, |z|1, y0, y1] внутренние, …наружные]; по вершинам с металлом > 0,42
const EXHAUST := {
	"bomber_1": [0.36, [-0.16, -0.01, 0.105, 0.19, -0.12, -0.02], [-0.14, 0.04, 0.24, 0.32, -0.13, -0.04]],
}

## S11-14 / S11-15 (playtest 3.5-s11, Kanta: «проблемы с текстурами» on «Кит» 2 and «Грач»): the hangar remesh closed
## the jet intakes and nozzles with caps and baked them mid or light (source luminance 0.02–0.08, above the l_keep
## cut-off), so every paint scheme painted the inside of the engines: orange tiger stripes inside the intakes,
## off-white «Классика» inside the nozzles, over the lumpy remeshed duct walls. Inside these openings the surface
## takes a dark sooty metal instead of the paint. Per plane, in model axes (nose +X, up +Y, both sides by |z|):
## [axis y, axis |z|, nacelle radius r, [intake x0, x1], [nozzle x0, x1]]. A point counts as inside when it lies
## within 0.9 r of the axis in one of the x spans and faces the axis or along it (the duct walls and the caps), so
## the outer skin of the nacelle and of the nozzle keeps the paint. Measured on the hangar models (radial fit of the
## nacelle skin, caps found by their ±X normals); the battle models share the shape and axes.
const ENGINE_HOLES := {
	"attacker_1": [-0.0387, 0.0884, 0.0335, [0.065, 0.13], [-0.26, -0.15]],
	"attacker_2": [-0.0293, 0.0919, 0.0404, [0.035, 0.12], [-0.31, -0.20]],
	"bomber_2": [-0.0144, 0.0702, 0.0295, [-0.135, 0.0], [-0.29, -0.24]],
}

static var _shader: Shader
static var _force := ""   # стенд: --livery=<id> — окраска своего самолёта в бою, если у класса такая есть


## Список вариантов класса: [[id, название], …]; первый — по умолчанию
## With --livproposals (bench only) the NATURAL proposals follow the class's own paints
static func list(cls: String) -> Array:
	var out: Array = []
	for v: Array in _all(cls):
		out.append([v[0], v[1]])
	return out


## The class's paints, plus the NATURAL proposals on the bench (--livproposals)
static func _all(cls: String) -> Array:
	var l: Array = VARIANTS.get(cls, [])
	if _proposals and VARIANTS.has(cls):
		l = l + NATURAL
	return l


## `--livproposals` read once: list()/current() run every hangar frame (review 2026-10-30, R-10)
static var _proposals: bool = OS.get_cmdline_user_args().has("--livproposals")


static func _find(cls: String, id: String) -> Array:
	for v: Array in _all(cls):
		if v[0] == id:
			return v
	return []


## Выбранная окраска класса (из профиля; стенд --livery=… сильнее)
static func current(cls: String) -> String:
	if _force == "":
		_force = "-"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--livery="):
				_force = a.get_slice("=", 1)
	if _force != "-" and not _find(cls, _force).is_empty():
		return _force
	var id := Profile.livery(cls)
	if _find(cls, id).is_empty():
		var l: Array = VARIANTS.get(cls, [[""]])
		return String(l[0][0])
	return id


## Turret paint of livery `id` (default: the class's current one): [GLB suffix, ring collar colour], or [] for the
## sand-camo turrets
## (WeaponModels.turret_file / turret_model pick the baked files and the collar by it)
static func turret_paint(cls: String, id := "") -> Array:
	return TURRET_PAINT.get(id if id != "" else current(cls), [])


## Перекрасить модель самолёта (корень модели ангара или боевой; key — «fighter_1» и т. п.). Звать после того,
## как подвешены механизация, детали, створки и кормовая кабина. Исходная окраска (вариант без цветов) — ничего не делает.
static func apply(model: Node3D, cls: String, lvl: int, id: String) -> void:
	var v := _find(cls, id)
	if v.size() < 8:
		return
	var key := "%s_%d" % [cls, lvl]
	var src: Array = SRC.get(key, [0.1, 0.012])
	var ex: Array = EXHAUST.get(key, [])
	var holes: Array = ENGINE_HOLES.get(key, [])
	var nose: Array = NOSE.get(key, [])
	# основной меш (текстура Meshy) — по нему габарит модели для узоров
	var box := AABB()
	var body: Array = []
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if _skip(mi, model):
			continue
		var m := mi.mesh.surface_get_material(0) as BaseMaterial3D
		if m != null and m.albedo_texture != null:
			var xf := _rel(mi, model)
			var bb := xf * mi.mesh.get_aabb()
			box = bb if body.is_empty() else box.merge(bb)
			body.append(mi)
	if body.is_empty():
		return
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if _skip(mi, model):
			continue
		var xf := _rel(mi, model)
		for si in mi.mesh.get_surface_count():
			# вид поверхности — по имени материала в GLB (у механизации поверх стоит общий материал WingMech)
			var m0 := mi.mesh.surface_get_material(si)
			var m := mi.get_surface_override_material(si)
			var sm := _material(m if m != null else m0, String(m0.resource_name) if m0 != null else "", v, src, xf, box, ex, holes,
					float(CLASS_SCALE.get(cls, 1.0)), nose)
			if sm != null:
				mi.set_surface_override_material(si, sm)


## Перекрашиваем модель и подвешенные к ней механизацию, детали, створки, кормовую кабину;
## знаки, модули прокачки и полосы ведомых — нет
static func _skip(mi: MeshInstance3D, model: Node3D) -> bool:
	var n: Node = mi
	if mi.mesh == null:
		return true   # an empty placeholder (SkinPatch missed the skin, Render3D keeps the node so it is not retried)
	while n != null and n != model:
		if String(n.name) in ["insignia", "module_parts", "wing_kit"]:
			return true
		n = n.get_parent()
	return false


## Преобразование меша в оси модели (без собственного масштаба корня модели в бою)
static func _rel(mi: Node3D, model: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != model:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Paint material for one surface: `ex` — exhaust boxes (EXHAUST), `holes` — engine openings (ENGINE_HOLES) of the
## plane, both only for the textured skin (mode 0); `cls_scale` — CLASS_SCALE of the plane for pattern 7 (NATURAL);
## `nose` — the plane's NOSE entry for the shark mouth (style 9; empty — no mouth); null for surfaces that keep their
## own material.
static func _material(m: Material, nm: String, v: Array, src: Array, xf: Transform3D, box: AABB, ex: Array = [],
		holes: Array = [], cls_scale: float = 1.0, nose: Array = []) -> ShaderMaterial:
	var bm := m as BaseMaterial3D
	if bm == null or nm == "glass":
		return null                     # стекло фонаря (ShaderMaterial «glass») — одно на все окраски
	var mode := -1
	if bm.albedo_texture != null:
		mode = 0                        # обшивка Meshy: текстуры
	elif nm.begins_with("mech_skin"):
		mode = 1                        # механизация, створки, кормовая кабина: вершинный цвет (снят с текстуры)
	elif nm.begins_with("detail_") and not nm.begins_with("detail_dark"):
		mode = 2                        # детали силуэта: цвет материала
	if mode < 0:
		return null                     # швы, стекло, ниши, тёмные детали — как есть
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _shader
	sm.set_shader_parameter("src_mode", mode)
	if mode == 0:
		sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
		sm.set_shader_parameter("has_normal", bm.normal_texture != null)
		if bm.normal_texture != null:
			sm.set_shader_parameter("normal_tex", bm.normal_texture)
			sm.set_shader_parameter("normal_scale", bm.normal_scale)
		var orm := bm.roughness_texture
		sm.set_shader_parameter("has_orm", orm != null)
		if orm != null:
			sm.set_shader_parameter("orm_tex", orm)
	else:
		sm.set_shader_parameter("src_color", bm.albedo_color)
		sm.set_shader_parameter("src_rough", bm.roughness)
	sm.set_shader_parameter("vcol_mul", 1.3 if mode == 1 else 1.0)
	sm.set_shader_parameter("l_base", float(src[0]))
	sm.set_shader_parameter("l_keep", float(src[1]))
	if mode == 0 and ex.size() == 3:
		sm.set_shader_parameter("ex_metal", float(ex[0]))
		for i in 2:
			var b: Array = ex[i + 1]
			sm.set_shader_parameter("ex_min%d" % i, Vector3(b[0], b[4], b[2]))
			sm.set_shader_parameter("ex_max%d" % i, Vector3(b[1], b[5], b[3]))
	if mode == 0 and holes.size() == 5:
		var hi: Array = holes[3]
		var hn: Array = holes[4]
		sm.set_shader_parameter("has_holes", true)
		sm.set_shader_parameter("hole_axis", Vector3(holes[0], holes[1], holes[2]))
		sm.set_shader_parameter("hole_x", Vector4(hi[0], hi[1], hn[0], hn[1]))
	sm.set_shader_parameter("c_dark", v[2])
	sm.set_shader_parameter("c_mid", v[3])
	sm.set_shader_parameter("c_light", v[4])
	sm.set_shader_parameter("liv_rough", float(v[5]))
	sm.set_shader_parameter("liv_metal", float(v[6]))
	sm.set_shader_parameter("pattern", int(v[7]))
	if v.size() > 9:
		sm.set_shader_parameter("pat_a", v[8])
		sm.set_shader_parameter("pat_b", v[9])
	if v.size() > 10:   # pattern 7 (NATURAL): style and weathering
		var np: Dictionary = v[10]
		sm.set_shader_parameter("nat_style", int(np.get("style", 0)))
		sm.set_shader_parameter("nat_scale", float(np.get("scale", 5.0)) * cls_scale)
		sm.set_shader_parameter("nat_cut", np.get("cut", Vector2(0.53, 0.6)))
		sm.set_shader_parameter("nat_edge", float(np.get("edge", 0.03)))
		sm.set_shader_parameter("nat_fade", float(np.get("fade", 0.5)))
		sm.set_shader_parameter("nat_grime", float(np.get("grime", 0.8)))
		sm.set_shader_parameter("nat_belly", float(np.get("belly", 1.0)))
		sm.set_shader_parameter("nat_seed", float(np.get("seed", 0.0)))
		if nose.size() == 4:
			sm.set_shader_parameter("shark_nose", Vector4(nose[0], nose[1], nose[2], nose[3]))
	sm.set_shader_parameter("to_model", Projection(xf))
	sm.set_shader_parameter("box_min", box.position)
	sm.set_shader_parameter("box_size", box.size)
	return sm


const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform int src_mode = 0;   // 0 — текстуры, 1 — вершинный цвет, 2 — цвет материала
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform float normal_scale = 1.0;
uniform vec4 src_color : source_color = vec4(1.0);
uniform float src_rough = 0.6;
uniform float vcol_mul = 1.0;
uniform float l_base = 0.1;
uniform float l_keep = 0.012;
uniform float ex_metal = 2.0;   // 2 — выхлопа нет
uniform vec3 ex_min0 = vec3(0.0);
uniform vec3 ex_max0 = vec3(0.0);
uniform vec3 ex_min1 = vec3(0.0);
uniform vec3 ex_max1 = vec3(0.0);
uniform bool has_holes = false;   // Livery.ENGINE_HOLES: intakes and nozzles stay dark metal
uniform vec3 hole_axis = vec3(0.0);   // nacelle axis y, |z|, radius
uniform vec4 hole_x = vec4(0.0);      // intake x0, x1, nozzle x0, x1
uniform vec3 c_dark : source_color;
uniform vec3 c_mid : source_color;
uniform vec3 c_light : source_color;
uniform float liv_rough = 0.6;
uniform float liv_metal = 0.05;
uniform int pattern = 0;
uniform vec3 pat_a : source_color;
uniform vec3 pat_b : source_color;
uniform mat4 to_model = mat4(1.0);
uniform vec3 box_min = vec3(-0.5);
uniform vec3 box_size = vec3(1.0);
// pattern 7 (Livery.NATURAL)
uniform int nat_style = 0;
uniform float nat_scale = 5.0;
uniform vec2 nat_cut = vec2(0.53, 0.6);
uniform float nat_edge = 0.03;
uniform float nat_fade = 0.5;
uniform float nat_grime = 0.8;
uniform float nat_belly = 1.0;
uniform float nat_seed = 0.0;
uniform vec4 shark_nose = vec4(0.0);   // style 9 (Livery.NOSE): mouth front x, back x, nose axis y, nose radius

const float CAMO_DARK = 0.52;
const float CAMO_OCHRE = 0.53;

varying vec3 lp;
varying vec3 ln;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), u.x), mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), u.x), mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0)), u.x), u.y);
	return mix(a, b, u.z);
}
// крупные пятна с неровным краем: основная частота + мелкая рябь края
float blobs(vec3 p) {
	return 0.62 * vnoise3(p) + 0.28 * vnoise3(p * 2.1 + 7.3) + 0.10 * vnoise3(p * 4.7 + 3.1);
}
vec2 hash22(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

// внутри коробки (x, y, |z|) с мягким краем 0,02
float in_box(vec3 p, vec3 a, vec3 b) {
	vec3 lo = smoothstep(a - 0.02, a + 0.02, p);
	vec3 hi = 1.0 - smoothstep(b - 0.02, b + 0.02, p);
	return lo.x * lo.y * lo.z * hi.x * hi.y * hi.z;
}

// S11-14/15: 1 inside an engine opening (Livery.ENGINE_HOLES): near the nacelle axis in an intake or nozzle span and
// facing the axis or along it (duct walls, caps); the outer skin faces away from the axis and keeps the paint
float x_span(float x, float a, float b) {
	return smoothstep(a - 0.004, a + 0.004, x) * (1.0 - smoothstep(b - 0.004, b + 0.004, x));
}
float engine_hole(vec3 p, vec3 n) {
	vec2 d = vec2(p.y - hole_axis.x, abs(p.z) - hole_axis.y);
	float rad = length(d);
	float near_axis = 1.0 - smoothstep(0.84 * hole_axis.z, 0.92 * hole_axis.z, rad);
	float radial = dot(d, vec2(n.y, n.z * sign(p.z))) / max(rad, 1e-4);
	float facing = max(1.0 - smoothstep(-0.2, 0.15, radial), smoothstep(0.5, 0.7, abs(n.x)));
	float span = max(x_span(p.x, hole_x.x, hole_x.y), x_span(p.x, hole_x.z, hole_x.w));
	return near_axis * facing * span;
}

// style 9: shark mouth on both sides of the nose (Livery.NOSE). u runs along the nose from the mouth's front end (0)
// to its back corner (1); the opening is an angle round the nose axis, so the shape holds on the tapering cone.
// Returns (outline, inside, teeth, eye ring) weights and the eye's pupil.
vec4 shark_mouth(vec3 p, out float pupil) {
	pupil = 0.0;
	if (shark_nose.x <= shark_nose.y) return vec4(0.0);
	float u = (shark_nose.x - p.x) / (shark_nose.x - shark_nose.y);
	vec2 d = vec2(abs(p.z), p.y - shark_nose.z);
	float rad = length(d);
	float ang = atan(d.y, max(d.x, 1e-5));   // + up from the side line
	float on_nose = 1.0 - smoothstep(1.5 * shark_nose.w, 1.9 * shark_nose.w, rad);   // the nose skin, not wings or intakes
	float uc = clamp(u, 0.0, 1.0);
	float in_u = smoothstep(-0.01, 0.0, u) * (1.0 - smoothstep(1.0, 1.01, u)) * on_nose;
	float h = 0.78 * pow(sin(3.1416 * pow(uc, 1.35)), 0.55);   // half opening (rad), widest behind the middle
	float dv = ang + 0.22;   // the lips meet a little under the side line
	float aw = fwidth(dv) + 0.004;
	float inside = (1.0 - smoothstep(h - aw, h + aw, abs(dv))) * in_u;
	float outline = (1.0 - smoothstep(h + 0.11 - aw, h + 0.11 + aw, abs(dv))) * in_u;
	// teeth from both lips, 8 along the mouth, half the opening long at most
	float tri = abs(fract(uc * 8.0) - 0.5) * 2.0;
	float tl = min(0.3, 0.5 * h) * (1.0 - tri);
	float teeth = inside * (1.0 - smoothstep(tl - aw, tl + aw, h - abs(dv)));
	// eye above the back of the mouth, clear of the upper lip's outline, sized by the nose radius
	float ue = 0.8;
	float he = 0.78 * pow(sin(3.1416 * pow(ue, 1.35)), 0.55);
	float xe = shark_nose.x - ue * (shark_nose.x - shark_nose.y);
	vec2 e = vec2((p.x - xe) / shark_nose.w, (ang - (he - 0.22 + 0.56)) * rad / shark_nose.w);
	float el = length(e);
	float ew = fwidth(el) + 0.01;
	float ring = (1.0 - smoothstep(0.36 - ew, 0.36 + ew, el)) * on_nose;
	pupil = (1.0 - smoothstep(0.2 - ew, 0.2 + ew, el)) * on_nose;
	return vec4(outline, inside, teeth, ring);
}

// леопард: розетки — разорванное тёмное кольцо, внутри чуть темнее основы; между ними мелкие пятна.
// Every rosette of the 3x3 neighbourhood is drawn whole and the strongest wins: taking only the nearest cell cut
// a ring off along the straight cell border wherever two rosettes came close, a hard unfiltered edge that read as
// pixel steps (Kanta 31.10). Edges and ring breaks are drawn about one screen pixel wide (fwidth of the cell grid,
// continuous across cell borders): crisp up close, no shimmer far away.
vec2 leopard(vec2 uv) {
	vec2 g = uv * 12.0;
	vec2 i = floor(g); vec2 f = fract(g);
	float wob = 0.85 + 0.3 * vnoise(uv * 60.0);
	float gn = 0.35 * vnoise(uv * 40.0);
	float pf = length(fwidth(g));   // screen pixel in cell units, continuous across cell borders
	float e = max(0.006, 0.75 * pf);
	float ring = 0.0; float inner = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = hash22(i + o);
			vec2 r = o + 0.15 + 0.7 * h - f;
			float d = length(r) * wob;
			float rad = 0.30 + 0.08 * h.x;
			// the ring's breaks: as crisp as the ring itself (pixel width along the arc, ~1/r per radian)
			float ga = max(0.03, 2.25 * pf / max(length(r), 0.05));
			float gaps = smoothstep(-0.55 - ga, -0.55 + ga, sin(atan(r.y, r.x) * 3.0 + h.x * 40.0) + gn);
			ring = max(ring, smoothstep(rad - 0.125 - e, rad - 0.125 + e, d)
					* (1.0 - smoothstep(rad + 0.055 - e, rad + 0.055 + e, d)) * gaps);
			inner = max(inner, 1.0 - smoothstep(rad - 0.135 - e, rad - 0.135 + e, d));
		}
	}
	return vec2(ring, inner);
}

// leopard() on the three model planes, blended by the normal: a hard switch to the dominant axis flickered pixel by
// pixel on the remeshed skin's uneven normals and cut the rosettes along jagged lines on curved surfaces
vec2 leopard_tri(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(6.0));
	w /= max(w.x + w.y + w.z, 1e-5);
	return leopard(p.zy) * w.x + leopard(p.xz) * w.y + leopard(p.xy) * w.z;
}

// тигр: изогнутые поперечные полосы, к концам сужаются; k — stripe width (1 — «Тигр», «Полярный тигр» wider)
float tiger_w(vec3 p, float k) {
	float w = vnoise(p.xz * 4.0 + p.y * 3.0) * 1.4 + vnoise(p.xz * 11.0) * 0.45;
	float s = p.x * 15.0 + abs(p.z) * 5.0 + w + p.y * 3.0;
	float tri = abs(fract(s) - 0.5);
	// ширина полосы меняется вдоль неё — к концам сужается до нуля (рваный «клин»)
	float along = vnoise(vec2(floor(s) * 5.1, 0.0) + vec2(abs(p.z) * 7.0 + p.y * 8.0, p.x * 3.0));
	float width = (0.24 * smoothstep(0.25, 0.75, along) + 0.03 * vnoise(p.xz * 30.0)) * k;
	return 1.0 - smoothstep(width - 0.03, width, tri);
}
float tiger(vec3 p) {
	return tiger_w(p, 1.0);
}

// pattern 7: a field's edge at level c — soft by nat_edge, never sharper than a pixel
float nat_step(float f, float c) {
	float w = max(nat_edge, fwidth(f) + 0.002);
	return smoothstep(c - w, c + w, f);
}

// pattern 7: soft patches — blobs over a warped domain, so they are uneven and elongated, never round
float nat_soft(vec3 p, float s) {
	vec3 w = vec3(vnoise3(p * 0.8 + s), vnoise3(p * 0.8 + s + 13.7), vnoise3(p * 0.8 + s + 29.1)) - 0.5;
	return blobs(p + w * 1.1 + vec3(s * 3.7));
}

// pattern 7: 3D cells — id (0…1) of the nearest feature point; the walls between cells are planes, so on the
// skin the edges run straight like masked splinter paint or panel borders
float nat_cell(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	float d1 = 9.0; float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 r = o + vec3(hash3(i + o), hash3(i + o + 17.3), hash3(i + o + 41.9)) - f;
				float d = dot(r, r);
				if (d < d1) { d1 = d; id = hash3(i + o + 7.7); }
			}
		}
	}
	return id;
}

// pattern 7: nat_cell with its border — id of the nearest cell, id2 of the cell across the nearest wall and edge,
// the distance to that wall (p units). The masked splinter edges blend over one pixel by it instead of a hard
// step(id), which stair-stepped along the texel and pixel grid in hangar close-ups (Kanta s14)
float nat_cell_e(vec3 p, out float id2, out float edge) {
	vec3 i = floor(p); vec3 f = fract(p);
	float d1 = 9.0; float id = 0.0; vec3 r1 = vec3(0.0); vec3 c1 = vec3(0.0);
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 r = o + vec3(hash3(i + o), hash3(i + o + 17.3), hash3(i + o + 41.9)) - f;
				float d = dot(r, r);
				if (d < d1) { d1 = d; id = hash3(i + o + 7.7); r1 = r; c1 = o; }
			}
		}
	}
	edge = 9.0; id2 = id;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = c1 + vec3(float(x), float(y), float(z));
				vec3 r = o + vec3(hash3(i + o), hash3(i + o + 17.3), hash3(i + o + 41.9)) - f;
				vec3 dr = r - r1;
				float l2 = dot(dr, dr);
				if (l2 > 1e-6) {
					float e = dot(0.5 * (r1 + r), dr * inversesqrt(l2));
					if (e < edge) { edge = e; id2 = hash3(i + o + 7.7); }
				}
			}
		}
	}
	return id;
}

// weight of the nearest cell against the one across the wall: 0.5 on the wall, full a pixel inside
float cell_aa(float edge) {
	return clamp(0.5 + 0.5 * edge / max(fwidth(edge), 1e-5), 0.0, 1.0);
}

// pattern 7: weights of colour 2 (x) and colour 3 (y) by nat_style at the scaled model point p, normal n
vec2 nat_pattern(vec3 p, vec3 n) {
	float s = nat_seed;
	if (nat_style == 1) {
		// hard splinter: cells turned and stretched along a diagonal, a little hand wobble on the edges
		float a = 0.55 + s;
		vec3 r = vec3(p.x * cos(a) - p.z * sin(a), p.y, p.x * sin(a) + p.z * cos(a));
		r += (vec3(vnoise3(p * 3.0 + s), vnoise3(p * 3.0 + s + 5.1), vnoise3(p * 3.0 + s + 9.4)) - 0.5) * 0.08;
		float id2; float e;
		float id = nat_cell_e(r * vec3(0.55, 1.0, 1.5), id2, e);
		float c2 = step(id, nat_cut.x);
		float c2b = step(id2, nat_cut.x);
		vec2 wa = vec2(c2, (1.0 - c2) * step(id, nat_cut.x + nat_cut.y));
		vec2 wb = vec2(c2b, (1.0 - c2b) * step(id2, nat_cut.x + nat_cut.y));
		return mix(wb, wa, cell_aa(e));
	} else if (nat_style == 2) {
		// wavy disruptive bands across the plane, their width breathing along them
		float warp = (nat_soft(p * 0.7, s) - 0.5) * 2.2;
		float d = p.x * 0.75 + p.z * 0.62 + p.y * 0.3 + warp;
		float f = fract(d);
		float w = max(nat_edge, fwidth(d) + 0.002);
		float c2 = (1.0 - smoothstep(nat_cut.x - w, nat_cut.x + w, f)) * smoothstep(0.0, w, f);
		float c3 = smoothstep(nat_cut.x - w, nat_cut.x + w, f) * (1.0 - smoothstep(nat_cut.x + nat_cut.y - w, nat_cut.x + nat_cut.y + w, f));
		return vec2(c2, c3);
	} else if (nat_style == 3) {
		// soft clouds of colour 2, fine mottle of colour 3 over everything
		return vec2(nat_step(nat_soft(p, s), nat_cut.x), nat_step(blobs(p * 3.4 + vec3(s)), nat_cut.y));
	} else if (nat_style == 4) {
		// one tone: panels repainted darker (colour 2) or left to bleach (colour 3), cells longer along the flow
		float id2; float e;
		float id = nat_cell_e(p * vec3(0.55, 1.2, 1.0) + vec3(s), id2, e);
		float c2 = step(id, nat_cut.x);
		float c2b = step(id2, nat_cut.x);
		vec2 wa = vec2(c2 * 0.55, (1.0 - c2) * step(id, nat_cut.x + nat_cut.y) * 0.6);
		vec2 wb = vec2(c2b * 0.55, (1.0 - c2b) * step(id2, nat_cut.x + nat_cut.y) * 0.6);
		return mix(wb, wa, cell_aa(e));
	} else if (nat_style == 5) {
		// whitewash: colour 2 (the paint under it) where it wore through — more on forward-facing edges and in
		// streaks along the flow; colour 3 where the wash is thin
		float wear = nat_soft(p * vec3(0.6, 1.0, 1.4), s) + 0.22 * smoothstep(0.3, 0.9, n.x)
				+ 0.12 * (vnoise3(vec3(p.x * 0.6, p.y * 9.0, p.z * 9.0) + vec3(s)) - 0.5);
		return vec2(nat_step(wear, nat_cut.x), nat_step(wear, nat_cut.y));
	} else if (nat_style == 6) {
		// reed: long thin streaks along the airflow (x), two layers
		vec3 r = vec3(p.x * 0.18, p.y * 2.6, p.z * 2.6);
		float f = blobs(r + vec3(s)) + 0.15 * (vnoise3(p * 1.5 + vec3(s)) - 0.5);
		return vec2(nat_step(f, nat_cut.x), nat_step(blobs(r * 1.3 + vec3(s + 7.0)), nat_cut.y));
	} else if (nat_style == 7) {
		// dazzle: big angular cells, each striped in its own direction; half the cells colour 2, half colour 3
		float id = nat_cell(p * 0.45 + vec3(s));
		float a = id * 6.2832;
		vec3 dir = normalize(vec3(cos(a), 0.5 * sin(a * 3.0), sin(a)));
		float d = dot(p, dir) * 1.6;
		float w = max(nat_edge, fwidth(d) + 0.002);
		float stripe = smoothstep(0.25 - w, 0.25 + w, abs(fract(d) - 0.5));
		float c2 = step(id, nat_cut.x);
		return vec2(stripe * c2, stripe * (1.0 - c2));
	} else if (nat_style == 8) {
		// digital: the fields sampled on a cube grid, so the patches are built of square «pixels» (two sizes)
		vec3 g = (floor(p * 4.4) + 0.5) / 4.4;
		vec3 g2 = (floor(p * 8.8) + 0.5) / 8.8;
		return vec2(step(nat_cut.x, nat_soft(g, s)), step(nat_cut.y, blobs(g2 * 1.3 + vec3(s + 3.0))));
	}
	// soft sprayed blotches: two warped fields, colour 3 over colour 2
	return vec2(nat_step(nat_soft(p, s), nat_cut.x), nat_step(nat_soft(p * 1.15 + vec3(4.2), s + 5.0), nat_cut.y));
}

void vertex() {
	lp = (to_model * vec4(VERTEX, 1.0)).xyz;
	ln = normalize((to_model * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 src;
	float rough0 = src_rough;
	float metal0 = 0.0;
	if (src_mode == 0) {
		src = texture(albedo_tex, UV).rgb;
		if (has_orm) {
			vec3 orm = texture(orm_tex, UV).rgb;
			rough0 = orm.g;
			metal0 = orm.b;
		}
		if (has_normal) {
			NORMAL_MAP = texture(normal_tex, UV).rgb;
			NORMAL_MAP_DEPTH = normal_scale;
		}
	} else if (src_mode == 1) {
		src = COLOR.rgb * vcol_mul;
	} else {
		src = src_color.rgb;
	}
	float l = dot(src, vec3(0.2126, 0.7152, 0.0722));
	// fine detail of the source skin (panel lines, grime) as a ratio to its local mean (a coarse mip): the whole-
	// pattern liveries (5, 7) keep the panel lines but no longer show the source camouflage under them — its soft
	// blotch edges came through as smeared patches and texel steps on the new paint (Kanta s14). Brightening is
	// capped low: the mip mixes in the dark atlas gutter at island borders
	float detail = 1.0;
	if (src_mode == 0) {
		float lm = dot(textureLod(albedo_tex, UV, 4.5).rgb, vec3(0.2126, 0.7152, 0.0722));
		detail = clamp(l / max(lm, 1e-4), 0.72, 1.04);
	}
	float t = l / l_base;
	// тест 3.5-s7: вершинный цвет механизации и створок снят с текстуры грубой сеткой — по нему только светлые
	// пятна камуфляжа, без тёмной полосы (иначе закрылки серые на белой «Классике» и в «квадратиках»)
	if (src_mode == 1) {
		t = clamp(t, 1.0, 2.2);
	}
	// полосы яркости исходного камуфляжа → тёмный / основной / светлый тон варианта
	float wd = 1.0 - smoothstep(0.45, 0.75, t);
	float wl = smoothstep(1.35, 1.8, t);
	vec3 col = mix(mix(c_mid, c_dark, wd), c_light, wl);
	// мелкие детали (швы, панели, грязь) — отклонение от середины своей полосы, приглушённо
	float centre = mix(mix(1.0, 0.3, wd), 2.4, wl);
	col *= mix(1.0, clamp(t / centre, 0.7, 1.25), 0.5);
	// низ по нормали — широкий мягкий переход: у ремеша ангара треугольники неровные, узкий порог по
	// интерполированной нормали давал рваный зубчатый край на гондолах и кромках крыла (тест 3.5-s7)
	float under_n = smoothstep(-0.08, -0.62, ln.y);
	vec3 q = (lp - box_min) / box_size;   // 0…1 по габариту: x — хвост→нос, y — низ→верх, z — левое→правое крыло
	float rough_add = 0.0;   // pattern 7: roughness variation of the paint
	float metal_k = 1.0;     // pattern 7 bare metal: rust and primer are not metallic
	if (pattern == 1) {
		vec2 lr = leopard_tri(lp, ln);
		col = mix(col, pat_b * mix(1.0, clamp(t / centre, 0.8, 1.15), 0.5), lr.y * 0.8);
		col = mix(col, pat_a, lr.x);
	} else if (pattern == 2) {
		float belly = under_n;
		col = mix(col, pat_b, belly);
		col = mix(col, pat_a, tiger(lp) * (1.0 - belly * 0.85));
	} else if (pattern == 3) {
		// бело-голубая «классика»: низ голубой, по борту синяя полоса, киль синий
		float under = under_n;
		col = mix(col, pat_b * mix(1.0, clamp(t / centre, 0.8, 1.15), 0.5), under);
		float side = smoothstep(0.55, 0.8, abs(ln.z)) * (1.0 - smoothstep(0.55, 0.8, abs(ln.y)));
		float band = (1.0 - smoothstep(0.04, 0.05, abs(q.y - 0.5))) * side * step(0.06, q.x);
		float fin = smoothstep(0.66, 0.72, q.y) * (1.0 - smoothstep(0.32, 0.4, q.x));
		float tips = smoothstep(0.41, 0.42, abs(q.z - 0.5));   // законцовки крыльев — видно сверху, из камеры боя
		col = mix(col, pat_a, max(max(band, fin), tips));
		// S9-21: грязь и копоть пятнами (до −9 %) и темнее к хвосту — белый не читается «чистым листом»
		float grime = smoothstep(0.35, 0.8, blobs(lp * 13.0 + vec3(5.3, 1.1, 2.7)));
		col *= (1.0 - 0.09 * grime) * mix(0.94, 1.0, smoothstep(0.0, 0.45, q.x));
	} else if (pattern == 4) {
		// чёрный с красным: нос, законцовки крыльев, верх киля
		float nose = smoothstep(0.915, 0.93, q.x);
		float tips = smoothstep(0.43, 0.445, abs(q.z - 0.5));
		float fin = smoothstep(0.80, 0.82, q.y);
		float red = max(max(nose, tips), fin);
		col = mix(col, pat_a * mix(1.0, clamp(t / centre, 0.8, 1.2), 0.4), red);
	} else if (pattern == 5) {
		// разрывной камуфляж в осях модели: охра и тёмные пятна поверх песка, края чёткие (сглаживание — на пиксель)
		float a = blobs(lp * vec3(7.5, 7.5, 7.5) + vec3(3.1, 0.0, 1.7));
		float b = blobs(lp * vec3(8.0, 8.0, 8.0) + vec3(-8.3, 4.2, 2.9));
		float aw = fwidth(a) + 0.002;
		float bw = fwidth(b) + 0.002;
		float dk = smoothstep(CAMO_DARK - aw, CAMO_DARK + aw, a);
		float oc = smoothstep(CAMO_OCHRE - bw, CAMO_OCHRE + bw, b);
		vec3 cam = mix(mix(c_mid, c_dark, oc), pat_a, dk);
		// светлое брюхо (видно на кренах и разворотах)
		float belly = under_n;
		cam = mix(cam, pat_b, belly);
		col = cam * mix(1.0, detail, 0.6);
	} else if (pattern == 6) {
		float belly = under_n;
		col = mix(col, pat_b * mix(1.0, clamp(t / centre, 0.8, 1.15), 0.5), belly);
		float tips = smoothstep(0.375, 0.385, abs(q.z - 0.5));
		float htail = smoothstep(0.215, 0.225, abs(q.z - 0.5)) * (1.0 - smoothstep(0.12, 0.13, q.x));
		col = mix(col, pat_a, max(tips, htail) * (1.0 - belly));
	} else if (pattern == 7) {
		// natural camouflage (Livery.NATURAL): pattern, a wavy belly line, then sun bleaching, uneven paint,
		// flow streaks, soot aft and chipped forward edges — no flat even paint
		vec3 n = normalize(ln);
		vec3 pn = lp * nat_scale;
		vec2 w;
		if (nat_style == 9) {   // shark: a plain coat with faint soft patches; the mouth goes on after the belly
			w = vec2(nat_step(nat_soft(pn, nat_seed), nat_cut.x) * 0.5, 0.0);
		} else if (nat_style == 10) {   // tiger stripes (as pattern 2, cut.x — width), weathered like the rest of 7
			w = vec2(tiger_w(lp, nat_cut.x), 0.0);
		} else if (nat_style == 11) {
			// bare metal: rust in soft fields, more on the lower faces; primer on whole repaired panels
			float rust = nat_step(nat_soft(pn, nat_seed) + 0.2 * smoothstep(0.0, -0.8, n.y), nat_cut.x);
			float pid2; float pe;
			float pid = nat_cell_e(pn * vec3(0.55, 1.2, 1.0) + vec3(nat_seed), pid2, pe);
			float primer = mix(step(pid2, nat_cut.y), step(pid, nat_cut.y), cell_aa(pe)) * (1.0 - rust);
			w = vec2(rust, primer);
			metal_k = 1.0 - max(rust, primer);
		} else if (nat_style == 12) {
			// chequer on the nose, the wing tips and the top of the fin, over a plain coat
			float zone = max(max(smoothstep(0.82, 0.83, q.x), smoothstep(0.38, 0.39, abs(q.z - 0.5))),
					smoothstep(0.72, 0.73, q.y) * (1.0 - smoothstep(0.32, 0.33, q.x)));
			vec3 cq = floor(lp * nat_scale);
			w = vec2(zone * mod(cq.x + cq.y + cq.z, 2.0), 0.0);
		} else {
			w = nat_pattern(pn, n);
		}
		vec3 cam = mix(mix(c_mid, c_dark, w.x), pat_a, w.y);
		if (nat_style == 5) {   // whitewash: colour 3 is a thin wash between the white and the paint under it
			cam = mix(mix(c_mid, pat_a, w.y), c_dark, w.x);
		}
		float bel = smoothstep(-0.02, -0.45, n.y + 0.2 * (vnoise3(lp * 9.0 + vec3(nat_seed)) - 0.5)) * nat_belly;
		cam = mix(cam, pat_b, bel);
		if (nat_style == 10) {   // snow: the graphite stripes carry on over the belly, so it never reads as one white
			cam = mix(cam, c_dark, w.x * bel * 0.8);
		}
		if (nat_style == 9) {
			// shark mouth: black outline (colour 2), dark red inside (colour 3), teeth and eye ring in the sun-bleach
			// tint, black pupil
			float pupil;
			vec4 sm = shark_mouth(lp, pupil);
			cam = mix(cam, c_dark, sm.x);
			cam = mix(cam, pat_a, sm.y);
			cam = mix(cam, c_light, sm.z);
			cam = mix(cam, c_light, sm.w);
			cam = mix(cam, c_dark, pupil);
		}
		cam *= mix(1.0, detail, 0.6);
		float top = smoothstep(0.1, 0.85, n.y);
		float fade_n = smoothstep(0.25, 0.75, blobs(lp * 3.5 + vec3(nat_seed * 2.3)));
		float lum = dot(cam, vec3(0.2126, 0.7152, 0.0722));
		vec3 bleach = mix(mix(cam, vec3(lum), 0.45) * 1.12, c_light, 0.3);
		float fd = clamp(nat_fade * (0.25 + 0.75 * top) * (0.35 + 0.65 * fade_n), 0.0, 1.0);
		cam = mix(cam, bleach, fd);
		cam *= 1.0 + 0.07 * (vnoise3(lp * 22.0 + vec3(nat_seed)) - 0.5) + 0.05 * (vnoise3(lp * 75.0) - 0.5);
		float st = vnoise3(vec3(lp.x * 4.0, lp.y * 60.0, lp.z * 60.0) + vec3(nat_seed));
		cam *= 1.0 - nat_grime * 0.1 * smoothstep(0.62, 0.92, st) * (0.4 + 0.6 * (1.0 - q.x));
		cam *= mix(1.0 - 0.1 * nat_grime, 1.0, smoothstep(0.0, 0.4, q.x));
		float chip = smoothstep(0.45, 0.9, n.x) * smoothstep(0.7, 0.78, vnoise3(lp * 140.0 + vec3(nat_seed)));
		cam = mix(cam, vec3(0.3, 0.29, 0.26) * 0.55, chip * nat_grime * 0.8);
		rough_add = 0.08 * (fade_n - 0.5) + 0.06 * fd + 0.04 * (vnoise3(lp * 30.0) - 0.5);
		col = cam;
	}
	// очень тёмное (фонарь, сопла, ниши) — исходный цвет
	float keep = 1.0 - smoothstep(l_keep * 0.6, l_keep, l);
	// хвосты гондол (выхлоп, см. Livery.EXHAUST) — тон окраски темнее и металлом, плавно, только в коробках выхлопа
	float mk = 0.0;
	if (ex_metal < 1.5) {
		vec3 pa = vec3(lp.x, lp.y, abs(lp.z));
		float zone = max(in_box(pa, ex_min0, ex_max0), in_box(pa, ex_min1, ex_max1));
		mk = zone * mix(0.6, 1.0, smoothstep(ex_metal - 0.14, ex_metal + 0.14, metal0));
	}
	col *= mix(1.0, 0.7, mk);
	// S11-14/15: inside intakes and nozzles — dark sooty metal from the source detail, not the paint
	float hole = has_holes ? engine_hole(lp, normalize(ln)) : 0.0;
	col = mix(col, min(src * 0.45, vec3(0.03)), hole);
	keep *= 1.0 - hole;
	ALBEDO = mix(col, src, keep);
	ROUGHNESS = mix(mix(mix(clamp(liv_rough + rough_add + (rough0 - 0.6) * 0.25, 0.05, 1.0), 0.5, mk), 0.6, hole), rough0, keep);
	METALLIC = mix(mix(mix(liv_metal * metal_k, 0.45, mk), 0.35, hole), 0.0, keep);
}
"""
