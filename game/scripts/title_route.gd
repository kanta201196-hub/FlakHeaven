class_name TitleRoute
extends RefCounted
## S11-01: the menu camera's route, a river line sampled every `step` px of river in flight order, and
## its moving average over ±`win` px of river, which is where the camera flies. Pure math, so the
## smoothing is unit-tested (game/tests/title_route_test.gd); TitleFlight traces the river into it.
## Samples are kept relative to the first one: the prefix sums stay small, so the average does not
## lose float precision far from the world origin.

var step: float
var win: float
var pts := PackedVector2Array()                  # samples minus _origin
var _origin := Vector2.ZERO
var _cum := PackedVector2Array([Vector2.ZERO])   # _cum[i] = sum of pts[0 .. i-1]


## step_px: river distance between samples; win_px: half window of the average along the river
func _init(step_px: float, win_px: float) -> void:
	step = step_px
	win = win_px


## Adds the next river sample (world position)
func add(p: Vector2) -> void:
	if pts.is_empty():
		_origin = p
	pts.append(p - _origin)
	_cum.append(_cum[_cum.size() - 1] + p - _origin)


## Forgets the route (a new one starts with the next add)
func clear() -> void:
	pts.clear()
	_cum = PackedVector2Array([Vector2.ZERO])


## Number of samples traced so far
func size() -> int:
	return pts.size()


## Last traced sample, world position
func last() -> Vector2:
	return pts[pts.size() - 1] + _origin


## Route centre at s px of river, world position: the mean of the river line within ±win, clamped to
## the traced part (near the start the window is shorter). Each sample counts for the step after it
## and the window takes fractions of its end samples: a window of whole samples jumped by up to 40 px
## each time it slid one sample (zigzag contrails on the laptop)
func point(s: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var n := float(pts.size())
	var a := clampf((s - win) / step, 0.0, n)
	var b := clampf((s + win) / step, 0.0, n)
	if b - a < 1e-3:
		return pts[mini(int(a), pts.size() - 1)] + _origin
	return (_cum_at(b) - _cum_at(a)) / (b - a) + _origin


## Sum of the route over the first u samples, fractional u (prefix sum of a step function)
func _cum_at(u: float) -> Vector2:
	var i := mini(int(u), pts.size() - 1)
	return _cum[i] + pts[i] * (u - float(i))
