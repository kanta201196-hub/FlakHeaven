class_name StoryComic
extends RefCounted
## Comic pages of the Highlands story scenes (plan `docs/superpowers/plans/2026-11-07-comic-cutscenes.md`, ST-12;
## Kanta 07.11: «вариант 2» — panels with motion inside). Data only: `HudComic` draws a page, `ComicKeys` does the
## maths. Phase A builds every page from art already in the game (crops of the ST-11 key art and the story
## portraits); phase B adds generated close-ups and cut-out jets after Kanta's «да» on the generation package.
##
## A page is {"panels": [...]}, keyed by "<intro|outro|epilogue>_<scene key>" (scene key as in `StoryScenes`, so
## "intro_forts.recon", "epilogue_sky.south"). A panel:
##   t     — s of scene time when it slides in
##   rect  — [x, y, w, h] share of the page (the page is 16:9, fitted to the screen)
##   img   — texture path; src — [x, y, w, h] px of the part of the texture shown (cropped further to the panel aspect)
##   push  — [scale gain, dx, dy] slow push-in over the rest of the scene (dx, dy: share of the crop)
##   cap   — [line index, x, y]: a yellow caption plate with that line of the scene (panel share)
##   say   — [[line indices], x, y, w]: a speech balloon (page share) with the latest of those lines that has
##           started; speaker and enemy colour come from the line, so the words live only in `StoryScenes`
##   sfx   — [word, x, y, size (page height share), angle deg, colour]: a sound word (panel share)
##   shake — true: a short screen shake when the panel lands
##   fx    — engine effects, positions in texture px so they ride the push-in:
##           {"k": "smoke"|"dust", "at": Vector2, "drift": Vector2, "r": px, "n": count, "c": Color}
##           {"k": "glow", "at": Vector2, "r": px, "c": Color, "flick": 0..1}
##           {"k": "flak", "area": Rect2, "n": count}
##           {"k": "tracer", "a": Vector2, "b": Vector2, "n": count, "c": Color}
##           {"k": "rain"} · {"k": "ring", "at": Vector2, "r": px}
##           {"k": "fly", "img": path, "t0": s, "t1": s (of the panel's life), "from": Vector2, "to": Vector2 (panel
##            share), "s0", "s1": height (panel share)} — a cut-out jet crossing the panel; cut-outs are keyed out of
##            the ST-11 pictures (`art/story/cutout/`, rembg), so they match the painted jets exactly

const ART := "res://art/story/%s.jpg"
const CUT := "res://art/story/cutout/%s.png"
const PANEL := "res://art/story/panels/%s.jpg"   # phase B close-ups and empty-sky plates (Figma AI, Kanta's «1» 08.11)
const FULL := [0, 0, 1536, 864]
const KUPOL := "res://art/portraits/story_kupol.png"
const GROM := "res://art/portraits/story_grom.png"
const FACE := [0, 0, 460, 690]          # the whole portrait

const FIRE := Color(1.0, 0.55, 0.15)
const BURNER := Color(1.0, 0.62, 0.25)
const GREEN := Color(0.45, 1.0, 0.35)
const AMBER := Color(1.0, 0.75, 0.3)
const SMOKE := Color(0.13, 0.12, 0.12)
const DUST := Color(0.78, 0.66, 0.5)
const YELLOW := Color(1.0, 0.81, 0.25)

const PAGES := {
	"intro_sky": {"panels": [
		{"t": 0.0, "rect": [0.0, 0.0, 0.6, 0.55], "img": ART % "intro_sky", "src": [0, 300, 1100, 564],
			"push": [0.10, -0.03, 0.0], "cap": [0, 0.03, 0.06],
			"fx": [{"k": "glow", "at": Vector2(318, 606), "r": 46.0, "c": BURNER, "flick": 0.5},
				{"k": "dust", "at": Vector2(200, 660), "drift": Vector2(-180, -60), "r": 60.0, "n": 7, "c": DUST}]},
		{"t": 1.7, "rect": [0.6, 0.0, 0.4, 0.55], "img": ART % "intro_sky", "src": [736, 140, 800, 330],
			"push": [0.16, 0.0, 0.03]},
		{"t": 3.3, "rect": [0.0, 0.55, 0.3, 0.45], "img": KUPOL, "src": FACE, "push": [0.06, 0.0, -0.02],
			"say": [[1, 2], 0.2, 0.43, 0.36]},
		{"t": 6.6, "rect": [0.3, 0.55, 0.3, 0.45], "img": PANEL % "c08_throttle", "src": [500, 150, 900, 714],
			"push": [0.14, 0.04, 0.0], "fx": [{"k": "glow", "at": Vector2(1450, 120), "r": 50.0, "c": BURNER, "flick": 0.2}]},
		{"t": 8.2, "rect": [0.6, 0.55, 0.4, 0.45], "img": PANEL % "b01_runway", "src": FULL,
			"push": [0.08, 0.0, 0.02], "shake": true, "sfx": ["РРАУ!", 0.5, 0.08, 0.08, -7.0, YELLOW],
			"fx": [{"k": "dust", "at": Vector2(240, 700), "drift": Vector2(-200, -60), "r": 80.0, "n": 8, "c": DUST},
				{"k": "fly", "img": CUT % "jet_player_rear", "t0": 0.0, "t1": 3.2, "from": Vector2(0.5, 1.1),
				"to": Vector2(0.52, 0.45), "s0": 1.3, "s1": 0.16}]},
	]},
	"intro_forts": {"panels": [
		{"t": 0.0, "rect": [0.0, 0.0, 0.62, 0.52], "img": ART % "intro_forts", "src": FULL,
			"push": [0.08, -0.02, 0.02], "cap": [0, 0.03, 0.06],
			"fx": [{"k": "flak", "area": Rect2(200, 120, 1250, 300), "n": 4}]},
		{"t": 2.9, "rect": [0.62, 0.0, 0.38, 0.52], "img": PANEL % "c07_baron_cockpit", "src": FULL,
			"push": [0.12, 0.0, -0.03], "say": [[1], 0.5, 0.36, 0.34],
			"fx": [{"k": "glow", "at": Vector2(1330, 150), "r": 40.0, "c": Color(1.0, 0.95, 0.8), "flick": 0.15}]},
		{"t": 4.6, "rect": [0.0, 0.52, 0.7, 0.48], "img": PANEL % "b02_fort_sky", "src": [0, 100, 1536, 764],
			"push": [0.08, 0.0, 0.03], "shake": true, "sfx": ["ВЖЖ!", 0.06, 0.08, 0.08, -8.0, YELLOW],
			"fx": [{"k": "flak", "area": Rect2(300, 120, 950, 300), "n": 4},
				{"k": "tracer", "a": Vector2(330, 560), "b": Vector2(620, 200), "n": 3, "c": AMBER},
				{"k": "tracer", "a": Vector2(1260, 520), "b": Vector2(1000, 180), "n": 3, "c": AMBER},
				{"k": "fly", "img": CUT % "jet_baron_front", "t0": 0.2, "t1": 2.6, "from": Vector2(0.52, 0.3),
				"to": Vector2(0.46, 0.6), "s0": 0.1, "s1": 1.25}]},
		{"t": 6.4, "rect": [0.7, 0.52, 0.3, 0.48], "img": KUPOL, "src": FACE, "push": [0.06, 0.0, -0.02],
			"say": [[2], 0.71, 0.76, 0.28]},
	]},
	"intro_forts.recon": {"panels": [
		{"t": 0.0, "rect": [0.0, 0.0, 0.62, 0.52], "img": ART % "intro_forts", "src": FULL,
			"push": [0.12, 0.06, 0.04], "cap": [0, 0.03, 0.06],
			"fx": [{"k": "flak", "area": Rect2(200, 120, 1250, 300), "n": 4}, {"k": "ring", "at": Vector2(1380, 610), "r": 120.0}]},
		{"t": 2.9, "rect": [0.62, 0.0, 0.38, 0.52], "img": PANEL % "c07_baron_cockpit", "src": FULL,
			"push": [0.12, 0.0, -0.03], "say": [[1], 0.5, 0.36, 0.34],
			"fx": [{"k": "glow", "at": Vector2(1330, 150), "r": 40.0, "c": Color(1.0, 0.95, 0.8), "flick": 0.15}]},
		{"t": 4.6, "rect": [0.0, 0.52, 0.7, 0.48], "img": PANEL % "b02_fort_sky", "src": [0, 100, 1536, 764],
			"push": [0.08, 0.0, 0.03], "shake": true, "sfx": ["ВЖЖ!", 0.06, 0.08, 0.08, -8.0, YELLOW],
			"fx": [{"k": "flak", "area": Rect2(300, 120, 950, 300), "n": 4},
				{"k": "tracer", "a": Vector2(330, 560), "b": Vector2(620, 200), "n": 3, "c": AMBER},
				{"k": "tracer", "a": Vector2(1260, 520), "b": Vector2(1000, 180), "n": 3, "c": AMBER},
				{"k": "fly", "img": CUT % "jet_baron_front", "t0": 0.2, "t1": 2.6, "from": Vector2(0.52, 0.3),
				"to": Vector2(0.46, 0.6), "s0": 0.1, "s1": 1.25}]},
		{"t": 6.4, "rect": [0.7, 0.52, 0.3, 0.48], "img": KUPOL, "src": FACE, "push": [0.06, 0.0, -0.02],
			"say": [[2], 0.71, 0.76, 0.28]},
	]},
	"intro_riverbed": {"panels": [
		{"t": 0.0, "rect": [0.0, 0.0, 0.64, 0.55], "img": ART % "intro_riverbed", "src": FULL,
			"push": [0.08, 0.03, 0.02], "cap": [0, 0.03, 0.06],
			"fx": [{"k": "dust", "at": Vector2(1400, 760), "drift": Vector2(-200, -120), "r": 60.0, "n": 8, "c": DUST},
				{"k": "dust", "at": Vector2(820, 430), "drift": Vector2(120, -90), "r": 40.0, "n": 5, "c": DUST}]},
		{"t": 1.8, "rect": [0.64, 0.0, 0.36, 0.55], "img": PANEL % "c12_blueprint", "src": [300, 0, 1236, 864],
			"push": [0.16, 0.05, 0.0], "sfx": ["ЧИРК", 0.6, 0.72, 0.055, 5.0, YELLOW]},
		{"t": 3.5, "rect": [0.0, 0.55, 0.3, 0.45], "img": KUPOL, "src": FACE, "push": [0.06, 0.0, -0.02],
			"say": [[1], 0.22, 0.42, 0.4]},
		{"t": 6.2, "rect": [0.3, 0.55, 0.7, 0.45], "img": PANEL % "b06_cloud_shadow", "src": FULL,
			"push": [0.22, 0.0, 0.06]},
	]},
	"intro_pass": {"panels": [
		{"t": 0.0, "rect": [0.0, 0.0, 0.62, 0.52], "img": ART % "intro_pass", "src": FULL,
			"push": [0.10, -0.03, 0.01], "cap": [0, 0.03, 0.06],
			"fx": [{"k": "dust", "at": Vector2(1320, 820), "drift": Vector2(-120, -80), "r": 40.0, "n": 6, "c": DUST}]},
		{"t": 1.5, "rect": [0.62, 0.0, 0.38, 0.52], "img": ART % "intro_pass", "src": [1180, 480, 356, 384],
			"push": [0.14, -0.02, -0.03],
			"fx": [{"k": "glow", "at": Vector2(1350, 735), "r": 14.0, "c": AMBER, "flick": 0.2},
				{"k": "dust", "at": Vector2(1310, 840), "drift": Vector2(-80, -90), "r": 50.0, "n": 7, "c": DUST}]},
		{"t": 2.9, "rect": [0.0, 0.52, 0.29, 0.48], "img": KUPOL, "src": FACE, "push": [0.06, 0.0, -0.02],
			"say": [[1], 0.2, 0.4, 0.36]},
		{"t": 5.0, "rect": [0.29, 0.52, 0.71, 0.48], "img": PANEL % "b03_canyon", "src": [0, 150, 1536, 714],
			"push": [0.08, 0.03, -0.02], "shake": true, "sfx": ["ВВУУХ!", 0.6, 0.1, 0.1, -7.0, YELLOW],
			"fx": [{"k": "fly", "img": CUT % "jet_player_rear", "t0": 0.0, "t1": 3.0, "from": Vector2(0.22, 0.95),
				"to": Vector2(0.62, 0.35), "s0": 1.15, "s1": 0.2}]},
	]},
	"outro_sky": {"panels": [
		{"t": 0.0, "rect": [0.0, 0.0, 0.6, 0.55], "img": ART % "outro_sky", "src": FULL,
			"push": [0.08, 0.02, 0.02], "cap": [0, 0.03, 0.06],
			"fx": [{"k": "smoke", "at": Vector2(1300, 260), "drift": Vector2(-160, -230), "r": 50.0, "n": 8, "c": SMOKE}]},
		{"t": 1.8, "rect": [0.6, 0.0, 0.4, 0.55], "img": ART % "outro_sky", "src": [780, 150, 756, 420],
			"push": [0.14, 0.03, 0.0],
			"fx": [{"k": "glow", "at": Vector2(1250, 330), "r": 40.0, "c": FIRE, "flick": 0.7},
				{"k": "smoke", "at": Vector2(1250, 300), "drift": Vector2(-200, -260), "r": 60.0, "n": 10, "c": SMOKE}]},
		{"t": 3.0, "rect": [0.0, 0.55, 0.3, 0.45], "img": KUPOL, "src": FACE, "push": [0.06, 0.0, -0.02],
			"say": [[1], 0.2, 0.43, 0.4]},
		{"t": 7.6, "rect": [0.3, 0.55, 0.7, 0.45], "img": PANEL % "b04_sunset_road", "src": [0, 0, 1536, 700],
			"push": [0.10, 0.04, -0.02], "cap": [2, 0.5, 0.08],
			"fx": [{"k": "glow", "at": Vector2(950, 425), "r": 60.0, "c": Color(1.0, 0.8, 0.4), "flick": 0.1},
				{"k": "fly", "img": CUT % "jet_flight_rear", "t0": 0.2, "t1": 3.8, "from": Vector2(0.4, 0.75),
				"to": Vector2(0.62, 0.42), "s0": 0.55, "s1": 0.07}]},
	]},
	"outro_forts": {"panels": [
		{"t": 0.0, "rect": [0.0, 0.0, 1.0, 0.44], "img": ART % "outro_forts", "src": FULL,
			"push": [0.08, -0.03, -0.02], "cap": [0, 0.015, 0.08],
			"fx": [{"k": "glow", "at": Vector2(430, 362), "r": 26.0, "c": GREEN, "flick": 0.5},
				{"k": "smoke", "at": Vector2(440, 330), "drift": Vector2(110, -260), "r": 40.0, "n": 8, "c": Color(0.35, 0.8, 0.3)}]},
		{"t": 1.5, "rect": [0.0, 0.44, 0.42, 0.56], "img": PANEL % "c09_grom_flare", "src": [200, 0, 1100, 864],
			"push": [0.10, 0.02, -0.03], "cap": [-1, 0.05, 0.84], "sfx": ["ПШШ!", 0.62, 0.3, 0.08, 8.0, Color(0.55, 1.0, 0.42)],
			"fx": [{"k": "glow", "at": Vector2(816, 70), "r": 50.0, "c": GREEN, "flick": 0.6},
				{"k": "smoke", "at": Vector2(816, 40), "drift": Vector2(80, -200), "r": 50.0, "n": 8, "c": Color(0.35, 0.8, 0.3)}]},
		{"t": 3.0, "rect": [0.42, 0.44, 0.26, 0.56], "img": KUPOL, "src": FACE, "push": [0.06, 0.0, -0.02],
			"say": [[1], 0.3, 0.36, 0.3]},
		{"t": 4.6, "rect": [0.68, 0.44, 0.32, 0.56], "img": PANEL % "b05_fort_night", "src": [300, 0, 1236, 864],
			"push": [0.08, -0.03, 0.0], "sfx": ["ВЖЖ!", 0.55, 0.1, 0.06, 6.0, YELLOW],
			"fx": [{"k": "smoke", "at": Vector2(200, 520), "drift": Vector2(80, -360), "r": 40.0, "n": 7, "c": Color(0.35, 0.8, 0.3)},
				{"k": "fly", "img": CUT % "jet_night_side", "t0": 0.0, "t1": 3.2, "from": Vector2(1.1, 0.6),
				"to": Vector2(-0.1, 0.3), "s0": 0.22, "s1": 0.3}]},
	]},
	"outro_riverbed": {"panels": [
		{"t": 0.0, "rect": [0.0, 0.0, 0.6, 0.55], "img": ART % "outro_riverbed", "src": FULL,
			"push": [0.08, 0.02, 0.02], "cap": [0, 0.03, 0.06],
			"fx": [{"k": "glow", "at": Vector2(480, 512), "r": 30.0, "c": FIRE, "flick": 0.7},
				{"k": "glow", "at": Vector2(1056, 544), "r": 30.0, "c": FIRE, "flick": 0.7},
				{"k": "smoke", "at": Vector2(1250, 420), "drift": Vector2(-60, -320), "r": 50.0, "n": 8, "c": SMOKE}]},
		{"t": 1.8, "rect": [0.6, 0.0, 0.4, 0.55], "img": PANEL % "c10_fortress_wreck", "src": FULL,
			"push": [0.14, 0.0, 0.03], "sfx": ["ТРЕСК", 0.08, 0.72, 0.06, -6.0, YELLOW],
			"fx": [{"k": "glow", "at": Vector2(420, 560), "r": 40.0, "c": FIRE, "flick": 0.8},
				{"k": "glow", "at": Vector2(900, 480), "r": 40.0, "c": FIRE, "flick": 0.8},
				{"k": "smoke", "at": Vector2(500, 300), "drift": Vector2(-60, -280), "r": 60.0, "n": 9, "c": SMOKE}]},
		{"t": 3.0, "rect": [0.0, 0.55, 0.3, 0.45], "img": KUPOL, "src": FACE, "push": [0.06, 0.0, -0.02],
			"say": [[1], 0.2, 0.43, 0.38]},
		{"t": 5.2, "rect": [0.3, 0.55, 0.7, 0.45], "img": PANEL % "c11_radio_hands", "src": [480, 0, 1056, 864],
			"push": [0.14, 0.03, 0.0], "sfx": ["ШШШ…", 0.06, 0.1, 0.07, -4.0, Color(1.0, 0.45, 0.35)],
			"fx": [{"k": "glow", "at": Vector2(816, 245), "r": 40.0, "c": AMBER, "flick": 0.35},
				{"k": "glow", "at": Vector2(1350, 70), "r": 30.0, "c": Color(1.0, 0.3, 0.2), "flick": 0.5}]},
	]},
	"outro_pass": {"panels": [
		{"t": 0.0, "rect": [0.0, 0.0, 0.62, 0.55], "img": ART % "outro_pass", "src": FULL,
			"push": [0.10, -0.03, 0.0], "cap": [0, 0.03, 0.06]},
		{"t": 1.2, "rect": [0.62, 0.0, 0.38, 0.55], "img": ART % "outro_pass", "src": [960, 420, 576, 330],
			"push": [0.14, 0.02, 0.0],
			"fx": [{"k": "glow", "at": Vector2(1180, 580), "r": 12.0, "c": AMBER, "flick": 0.25},
				{"k": "glow", "at": Vector2(1330, 520), "r": 10.0, "c": AMBER, "flick": 0.25}]},
		{"t": 2.3, "rect": [0.0, 0.55, 0.3, 0.45], "img": KUPOL, "src": FACE, "push": [0.06, 0.0, -0.02],
			"say": [[1], 0.22, 0.44, 0.36]},
		{"t": 3.6, "rect": [0.3, 0.55, 0.7, 0.45], "img": PANEL % "b04_sunset_road", "src": [0, 0, 1536, 700],
			"push": [0.10, 0.04, -0.02],
			"fx": [{"k": "fly", "img": CUT % "jet_flight_rear", "t0": 0.0, "t1": 2.8, "from": Vector2(0.35, 0.8),
				"to": Vector2(0.62, 0.42), "s0": 0.5, "s1": 0.08}]},
	]},
	"epilogue_sky.south": {"panels": [
		{"t": 0.0, "rect": [0.0, 0.0, 1.0, 0.56], "img": ART % "epilogue_sky", "src": FULL,
			"push": [0.08, -0.02, 0.03], "fx": [{"k": "rain"}]},
		{"t": 0.7, "rect": [0.0, 0.56, 0.3, 0.44], "img": KUPOL, "src": FACE, "push": [0.06, 0.0, -0.02],
			"say": [[0], 0.24, 0.6, 0.4]},
		{"t": 1.4, "rect": [0.3, 0.56, 0.7, 0.44], "img": PANEL % "c11_radio_hands", "src": [480, 0, 1056, 864],
			"push": [0.14, 0.04, 0.02], "fx": [{"k": "glow", "at": Vector2(816, 245), "r": 40.0, "c": AMBER, "flick": 0.35}]},
	]},
	"epilogue_sky.later": {"panels": [
		{"t": 0.0, "rect": [0.0, 0.0, 1.0, 0.56], "img": ART % "epilogue_sky", "src": FULL,
			"push": [0.08, -0.02, 0.03], "fx": [{"k": "rain"}]},
		{"t": 0.7, "rect": [0.0, 0.56, 0.3, 0.44], "img": KUPOL, "src": FACE, "push": [0.06, 0.0, -0.02],
			"say": [[0], 0.24, 0.6, 0.4]},
		{"t": 1.4, "rect": [0.3, 0.56, 0.7, 0.44], "img": PANEL % "c11_radio_hands", "src": [480, 0, 1056, 864],
			"push": [0.14, 0.04, 0.02], "fx": [{"k": "glow", "at": Vector2(816, 245), "r": 40.0, "c": AMBER, "flick": 0.35}]},
	]},
}

## Every texture page `key` draws: panel pictures and cut-out sprites, each once.
static func images(key: String) -> Array:
	var out: Array = []
	for p in PAGES.get(key, {}).get("panels", []):
		var pd: Dictionary = p
		if not out.has(String(pd["img"])):
			out.append(String(pd["img"]))
		for f in pd.get("fx", []):
			if (f as Dictionary).has("img") and not out.has(String(f["img"])):
				out.append(String(f["img"]))
	return out


## Side-view cut-outs and the way their nose points on the picture (-1 left, 1 right): a jet flying across a panel
## must move nose first (Kanta 08.11: the night jet in outro_forts flew tail first). Rear and front views have no entry.
const NOSE_X := {"jet_night_side": -1.0}


## Caption text of a panel whose `cap` line index is -1 (no line of the scene): who is on the picture.
const NAME_CAPS := {"outro_forts": "«Гром»"}


## Page key of a playing scene: `scene_id` is the campaign flag ("intro_forts"), `scene` the definition being
## played, which tells a variant apart ("forts.recon", "sky.south"); the `--storyshots` replay names variants with
## "_" ("intro_forts_recon"), which matches too. "" when the scene has no page.
static func key_of(scene_id: String, scene: Dictionary) -> String:
	var parts := scene_id.split("_", true, 1)
	if parts.size() < 2:
		return ""
	var table := _table(parts[0])
	for k in table:
		var named := String(k).replace(".", "_") == parts[1] or String(k).get_slice(".", 0) == parts[1]
		if named and table[k] == scene and PAGES.has("%s_%s" % [parts[0], k]):
			return "%s_%s" % [parts[0], k]
	return ""


## The scene definition a page belongs to ({} when none): "intro_forts.recon" → `StoryScenes.INTRO["forts.recon"]`.
static func scene_of(page_key: String) -> Dictionary:
	var parts := page_key.split("_", true, 1)
	if parts.size() < 2:
		return {}
	return _table(parts[0]).get(parts[1], {})


static func _table(kind: String) -> Dictionary:
	match kind:
		"intro":
			return StoryScenes.INTRO
		"outro":
			return StoryScenes.OUTRO
		"epilogue":
			return StoryScenes.EPILOGUE
	return {}
