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


# ---------- «Кит» patrol columns (GD-18, Kanta 12.11.2026) ----------
## Kanta 12.11: «надо менять количество наземки, а не урон бомб». Bot run 11–12.11: in a focused bomb build the
## cluster bombs dealt 0.44k damage/min, the same as in «Кит»'s gun build — they had too few ground targets. One
## cause was a bug: a column the bomber flew past without touching never ended, so no new column came for the rest
## of the sortie (4–7 per sortie instead of ~25). F1 `kit_patrols` (default 1); 0 — the s18 rules below.
const PATROL_EVERY_OLD := 35.0
const PATROL_EVERY := 20.0
const PATROL_MAX := 2
## A column must live this long before it may be dropped, so one that spawns ahead is not dropped while it
## drives into the bomber's path.
const PATROL_GRACE := 20.0
## Every live vehicle farther than this from the player, px: the column was left behind (same as the convoy's
## clean-up distance after it ends).
const PATROL_DROP_R := 2600.0
const PATROL_ORDER_OLD := ["technical", "truck", "light"]
## Five soft vehicles: two trucks carry cargo like a convoy's; no armour or MANPADS, so the column stays a
## bombing target rather than a fight.
const PATROL_ORDER := ["technical", "truck", "light", "truck", "technical"]


## Seconds between patrol columns.
static func patrol_every(on: bool) -> float:
	return PATROL_EVERY if on else PATROL_EVERY_OLD


## How many patrol columns may be on the map at once.
static func patrol_max(on: bool) -> int:
	return PATROL_MAX if on else 1


## Vehicle kinds of a patrol column, head first.
static func patrol_order(on: bool) -> Array:
	return (PATROL_ORDER if on else PATROL_ORDER_OLD).duplicate()


## True when an untouched patrol column was left behind and should be removed: toggle on, no alarm, older than
## PATROL_GRACE, and every live vehicle (`dists`, px from the player) beyond PATROL_DROP_R.
static func patrol_gone(on: bool, alarmed: bool, age: float, dists: Array) -> bool:
	if not on or alarmed or age < PATROL_GRACE or dists.is_empty():
		return false
	for d in dists:
		if float(d) < PATROL_DROP_R:
			return false
	return true
