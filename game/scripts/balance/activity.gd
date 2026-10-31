class_name ActivityBalance
extends RefCounted
## Where map activities with ground sites (AA site «ПВО», «Укрепрайон» fort) may appear, S14-04.
## Kanta 31.10 (build s14): sites still showed up next to the player; they must never appear in view and
## stand at least two screens away. The pure checks below are unit-tested (activity_place_test.gd).

## Kanta 31.10: a site stands at least this many screens (the longer side of the visible screen, world px)
## from the player.
const SCREENS := 2.0
## The AA site is searched this much farther than the minimum: its level-ground search moves the bunker up
## to ~900 px and the vehicles stand ~400 px round it, so most first tries pass.
const EXTRA := 900.0
## Directions tried round the heading, rad, nearest to the heading first; then the same once more EXTRA farther.
const TURNS := [0.0, 0.6, -0.6, 1.2, -1.2]
## At most this many AA site placements per activity (AASite.place costs ~25 ms on the main thread).
const TRIES := 6


## Minimum distance from the player for a site, px, for the screen rect `screen` (world px).
static func min_dist(screen: Rect2) -> float:
	return SCREENS * maxf(screen.size.x, screen.size.y)


## True when every point of a site is at least `min_d` from `from` and outside `view` (what the camera shows,
## with margins; an empty rect is not checked).
static func far_ok(spots: PackedVector2Array, from: Vector2, min_d: float, view := Rect2()) -> bool:
	for q in spots:
		if q.distance_to(from) < min_d:
			return false
		if view.has_area() and view.has_point(q):
			return false
	return true


## Nearest distance from `from` to any point of a site (to keep the best try when none passes).
static func near_dist(spots: PackedVector2Array, from: Vector2) -> float:
	var d := INF
	for q in spots:
		d = minf(d, q.distance_to(from))
	return d


## Centres to try for a site, in order: ahead along `heading`, then turned by TURNS, at min_d + EXTRA,
## then the same EXTRA farther; at most TRIES of them.
static func wants(from: Vector2, heading: float, min_d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for ring in 2:
		for t: float in TURNS:
			if out.size() >= TRIES:
				return out
			out.append(from + Vector2.from_angle(heading + t) * (min_d + EXTRA * (ring + 1)))
	return out
