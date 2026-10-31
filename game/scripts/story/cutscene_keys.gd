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


## Caption shown at time `tt`: [speaker, text, alpha] or [] when none; fades LINE_FADE s at both ends.
static func line_at(scene: Dictionary, tt: float) -> Array:
	for l in scene.get("lines", []):
		var ll: Array = l
		if tt >= float(ll[0]) and tt <= float(ll[1]):
			var a := minf(1.0, minf(tt - float(ll[0]), float(ll[1]) - tt) / LINE_FADE)
			return [String(ll[2]), String(ll[3]), a]
	return []


## Black overlay alpha at time `tt` of a scene `dur` long: from black at the start, to black at the end.
static func fade_at(tt: float, dur: float) -> float:
	return clampf(1.0 - minf(tt, dur - tt) / FADE, 0.0, 1.0)
