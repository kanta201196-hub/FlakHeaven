class_name ComicKeys
extends RefCounted
## Pure maths of the comic-page cutscenes (plan `docs/superpowers/plans/2026-11-07-comic-cutscenes.md`, ST-12):
## when a panel slides in, how its picture pushes in, how balloons and sound words pop, the landing shake and
## deterministic particles for the in-panel effects. No engine state, so `game/tests/comic_keys_test.gd` runs it in a
## bare SceneTree; `HudComic` draws with the results. Everything is a function of scene time, so a frame is the same
## on every machine and the `--cutshot` review frames match what players see.

const SLIDE := 0.45        # s a panel takes to slide in
const POP := 0.32          # s a balloon or sound word takes to pop
const SHAKE_TIME := 0.35   # s of screen shake after a panel with `shake` lands
const SHAKE_PX := 9.0      # strongest shake, px at 1080p (HudComic scales it)


## Slide-in progress of a panel that appears at `t0`: 0 before, eases out with a small overshoot, 1 after SLIDE s.
static func panel_in(t: float, t0: float) -> float:
	if t < t0:
		return 0.0
	var u := clampf((t - t0) / SLIDE, 0.0, 1.0)
	return _back_out(u, 1.2)


## The part of `src` (px of the texture) that fills a panel of aspect `aspect` (w / h) without stretching: the
## largest centred rect of that aspect inside `src` (like «cover»).
static func cover(src: Rect2, aspect: float) -> Rect2:
	if src.size.x <= 0.0 or src.size.y <= 0.0 or aspect <= 0.0:
		return src
	var w := src.size.x
	var h := w / aspect
	if h > src.size.y:
		h = src.size.y
		w = h * aspect
	return Rect2(src.position + (src.size - Vector2(w, h)) * 0.5, Vector2(w, h))


## Slow push-in of a panel picture: the crop `src` narrows by `push[0]` (share of scale gained) and drifts by
## `push[1]`, `push[2]` (share of the crop) over `dur` s of the panel's `life`, smooth-step; always inside `src`.
static func push_src(src: Rect2, push: Array, life: float, dur: float) -> Rect2:
	var gain := float(push[0]) if push.size() > 0 else 0.0
	var dx := float(push[1]) if push.size() > 1 else 0.0
	var dy := float(push[2]) if push.size() > 2 else 0.0
	var u := 0.0 if dur <= 0.0 else clampf(life / dur, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var size := src.size / (1.0 + gain * u)
	var centre := src.get_center() + Vector2(dx * src.size.x, dy * src.size.y) * u
	var pos := centre - size * 0.5
	pos.x = clampf(pos.x, src.position.x, src.end.x - size.x)
	pos.y = clampf(pos.y, src.position.y, src.end.y - size.y)
	return Rect2(pos, size)


## Pop scale of a balloon or sound word whose panel came in at `t0`, shown `delay` s later: 0, overshoot, 1.
static func pop(t: float, t0: float, delay: float) -> float:
	var s := t - t0 - delay
	if s <= 0.0:
		return 0.0
	return _back_out(clampf(s / POP, 0.0, 1.0), 1.7)


## Screen shake offset (px at 1080p) after a panel lands at `t_land`: a fast decaying wobble, zero outside it.
static func shake(t: float, t_land: float) -> Vector2:
	var s := t - t_land
	if s <= 0.0 or s > SHAKE_TIME:
		return Vector2.ZERO
	var k := SHAKE_PX * (1.0 - s / SHAKE_TIME)
	return Vector2(sin(s * 71.0), cos(s * 53.0)) * k


## Deterministic pseudo-random number in [0, 1) for particle `i` of effect `seed` (no RNG state between frames).
static func rand01(seed: int, i: int) -> float:
	var h := (seed * 73856093) ^ (i * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)


## Particle `i` of a rising or drifting stream (smoke, dust, sparks) from `origin` moving by `drift` over its
## `life` s, at scene time `t`: [position (panel share), size factor 0.4..1.6, alpha 0..1]. Particles are spread
## evenly over the life so the stream never pulses; each wobbles sideways a little.
static func puff(origin: Vector2, drift: Vector2, i: int, t: float, life: float) -> Array:
	var phase := fposmod(t / life + rand01(i, 1) , 1.0)
	var wob := (rand01(i, 2) - 0.5) * 0.08 + sin(t * 1.3 + float(i)) * 0.01
	var pos := origin + drift * phase + Vector2(wob, 0.0) * (0.3 + phase)
	var size := lerpf(0.4, 1.6, phase) * lerpf(0.8, 1.2, rand01(i, 3))
	var alpha := clampf(minf(phase / 0.15, (1.0 - phase) / 0.5), 0.0, 1.0)
	return [pos, size, alpha]


## A cut-out jet crossing a panel (fx "fly"): at `life` s of the panel, moving from `from` to `to` (panel share)
## between `t0` and `t1`, its height growing from `s0` to `s1` (share of the panel height), ease-in-out so it
## enters and leaves smoothly. [centre, height share, alpha]; alpha 0 before `t0` and fading out over the last 15 %.
static func fly(life: float, t0: float, t1: float, from: Vector2, to: Vector2, s0: float, s1: float) -> Array:
	if life < t0 or t1 <= t0:
		return [from, s0, 0.0]
	var u := clampf((life - t0) / (t1 - t0), 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var alpha := clampf(minf(u / 0.08, (1.0 - u) / 0.15), 0.0, 1.0) if u < 1.0 else 0.0
	return [from.lerp(to, e), lerpf(s0, s1, e * e), alpha]


## The part of a sprite drawn at `dst` that falls inside `clip`, as [visible dst, matching src of a `tex_size`
## texture]; empty when nothing shows. Panels have no engine clipping, so a jet entering from outside is cut here.
static func clip_sprite(dst: Rect2, clip: Rect2, tex_size: Vector2) -> Array:
	var vis := dst.intersection(clip)
	if vis.size.x <= 0.0 or vis.size.y <= 0.0 or dst.size.x <= 0.0 or dst.size.y <= 0.0:
		return []
	var k := tex_size / dst.size
	return [vis, Rect2((vis.position - dst.position) * k, vis.size * k)]


static func _back_out(u: float, s: float) -> float:
	var v := u - 1.0
	return 1.0 + v * v * ((s + 1.0) * v + s)
