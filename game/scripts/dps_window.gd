class_name DpsWindow
extends RefCounted
## Damage per second of each source over the last minute of the sortie, for the pause
## screen block «Урон за последнюю минуту» (combat UI v2). Main feeds it from `add_stat`
## ("dealt") with sortie time; the pause screen reads `top()`. One-second buckets in a ring,
## so adding costs a dictionary write and nothing grows during the sortie.
## Unit tests: game/tests/dps_window_test.gd.

## Window length, seconds
const WINDOW := 60.0
## One bucket per second of the window plus the current second
const BUCKETS := 61

## Second (floor of sortie time) each bucket holds, -1 when empty
var _sec: PackedInt32Array
## Damage by source id in each bucket
var _dmg: Array[Dictionary] = []


func _init() -> void:
	reset()


## Forgets all damage (new sortie).
func reset() -> void:
	_sec = PackedInt32Array()
	_sec.resize(BUCKETS)
	_sec.fill(-1)
	_dmg.clear()
	for i in BUCKETS:
		_dmg.append({})


## Adds `v` damage of `source` dealt at sortie time `t` (seconds).
func add(source: StringName, v: float, t: float) -> void:
	var s := int(floorf(t))
	var i := posmod(s, BUCKETS)
	if _sec[i] != s:
		_sec[i] = s
		_dmg[i].clear()
	_dmg[i][source] = float(_dmg[i].get(source, 0.0)) + v


## Damage per second of `source` over the last minute at sortie time `now`; in the first
## minute it divides by the time flown so early numbers are not understated.
func rate(source: StringName, now: float) -> float:
	var sum := 0.0
	for i in BUCKETS:
		if _live(i, now):
			sum += float(_dmg[i].get(source, 0.0))
	return sum / _span(now)


## Up to `n` sources with the highest rate at `now`: [[source, rate], …], highest first.
func top(n: int, now: float) -> Array:
	var sums := {}
	for i in BUCKETS:
		if not _live(i, now):
			continue
		for k: StringName in _dmg[i]:
			sums[k] = float(sums.get(k, 0.0)) + float(_dmg[i][k])
	var out: Array = []
	var span := _span(now)
	for k: StringName in sums:
		if float(sums[k]) > 0.0:
			out.append([k, float(sums[k]) / span])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	return out.slice(0, n)


func _live(i: int, now: float) -> bool:
	var s := _sec[i]
	return s >= 0 and float(s) >= now - WINDOW and float(s) <= now


func _span(now: float) -> float:
	return clampf(now, 1.0, WINDOW)
