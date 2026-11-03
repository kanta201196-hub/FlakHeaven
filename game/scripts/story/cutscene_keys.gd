class_name CutsceneKeys
extends RefCounted
## Pure maths of a story scene (plan step 2): camera keys, captions and fades over scene time. No engine state and
## no autoload references, so `game/tests/cutscene_test.gd` runs it in a bare SceneTree; `Cutscene` applies the results.

const FADE := 0.4   # s of black at both ends of a scene
const LINE_FADE := 0.3


## Camera offset and zoom at time `tt` from the keys of `scene` ([[t, offset, zoom], …]): smooth-step between
## neighbouring keys, clamped at both ends. Returns [Vector2 offset, zoom].
static func cam_at(scene: Dictionary, tt: float) -> Array:
	var keys: Array = scene.get("cam", [])
	if keys.is_empty():
		return [Vector2.ZERO, 1.0]
	var a: Array = keys[0]
	for k in keys:
		var kk: Array = k
		if float(kk[0]) <= tt:
			a = kk
		else:
			var span := float(kk[0]) - float(a[0])
			var u := 0.0 if span <= 0.0 else clampf((tt - float(a[0])) / span, 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			return [(a[1] as Vector2).lerp(kk[1] as Vector2, u), lerpf(float(a[2]), float(kk[2]), u)]
	return [a[1], float(a[2])]


## Caption shown at time `tt`: [speaker, text, alpha, enemy] or [] when none; fades LINE_FADE s at both ends.
## `enemy` is the optional fifth element of the line (true: red plate).
static func line_at(scene: Dictionary, tt: float) -> Array:
	for l in scene.get("lines", []):
		var ll: Array = l
		if tt >= float(ll[0]) and tt <= float(ll[1]):
			var a := minf(1.0, minf(tt - float(ll[0]), float(ll[1]) - tt) / LINE_FADE)
			return [String(ll[2]), String(ll[3]), a, ll.size() > 4 and bool(ll[4])]
	return []


## Black overlay alpha at time `tt` of a scene `dur` long: from black at the start, to black at the end.
static func fade_at(tt: float, dur: float) -> float:
	return clampf(1.0 - minf(tt, dur - tt) / FADE, 0.0, 1.0)


const ART_PUSH := 0.07   # share of extra scale the picture gains over a scene (a slow push-in)
const ART_DRIFT := 0.02  # share of the screen width the picture drifts sideways over a scene


## Where the story picture (`tex_size` px) is drawn on a `size` screen at time `tt` of a scene `dur` long:
## scaled to cover the screen, then pushed in by ART_PUSH and drifted left by ART_DRIFT over the scene (smooth-step),
## kept inside the picture so no edge shows. Empty when there is no picture.
static func art_rect(size: Vector2, tex_size: Vector2, tt: float, dur: float) -> Rect2:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	var u := 0.0 if dur <= 0.0 else clampf(tt / dur, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var cover := maxf(size.x / tex_size.x, size.y / tex_size.y)
	var k := cover * (1.0 + ART_PUSH * u)
	var drawn := tex_size * k
	var pos := (size - drawn) * 0.5
	pos.x -= size.x * ART_DRIFT * (u - 0.5)
	pos.x = clampf(pos.x, size.x - drawn.x, 0.0)
	pos.y = clampf(pos.y, size.y - drawn.y, 0.0)
	return Rect2(pos, drawn)
