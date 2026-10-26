extends SceneTree
## Unit tests for `FortressBalance.dome_step`, the phase-1 dome missile clock (Kanta 2026-10-26, card «Пускать раз в
## 12 с»). Rules pinned here: an unblocked dome fires every FortressBalance.DOME_MSL_EVERY s after a lock of
## DOME_MSL_LOCK; four domes staggered by DOME_MSL_STAGGER never fire closer than that apart; a blocked dome (out
## of range or over the cap) waits instead of skipping its turn and locks as soon as it may.
## Run from the repository root: `tools/ci/unit.sh`.

const DT := 1.0 / 60.0

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_every()
	_test_stagger()
	_test_blocked_waits()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _dome(first: float) -> Dictionary:
	return {"dm": first, "lk": 0.0}


## Times (s) of "fire" events of one dome over `t` seconds; `may` decides by time whether it may lock.
func _fires(pt: Dictionary, t: float, may: Callable) -> Array:
	var out := []
	var now := 0.0
	while now < t:
		now += DT
		if FortressBalance.dome_step(pt, DT, may.call(now)) == "fire":
			out.append(now)
	return out


func _test_every() -> void:
	var f := _fires(_dome(FortressBalance.DOME_MSL_FIRST), 60.0, func(_n: float) -> bool: return true)
	_check(f.size() == 5, "4 s start, 12 s cadence: 5 launches in 60 s (got %d)" % f.size())
	_check(f.size() > 0 and absf(float(f[0]) - FortressBalance.DOME_MSL_FIRST - FortressBalance.DOME_MSL_LOCK) < 0.05,
		"first launch after the start delay plus the lock (got %s)" % str(f))
	for i in range(1, f.size()):
		_check(absf(float(f[i]) - float(f[i - 1]) - FortressBalance.DOME_MSL_EVERY) < 0.05,
			"launch to launch is DOME_MSL_EVERY (got %.2f)" % (float(f[i]) - float(f[i - 1])))


func _test_stagger() -> void:
	var all := []
	for i in 4:
		var pt := _dome(FortressBalance.DOME_MSL_FIRST + FortressBalance.DOME_MSL_STAGGER * i)
		all.append_array(_fires(pt, 40.0, func(_n: float) -> bool: return true))
	all.sort()
	var gap := INF
	for i in range(1, all.size()):
		gap = minf(gap, float(all[i]) - float(all[i - 1]))
	_check(gap > FortressBalance.DOME_MSL_STAGGER - 0.05, "staggered domes fire at least 3 s apart (got %.2f)" % gap)


func _test_blocked_waits() -> void:
	# blocked until 20 s: the dome holds its missile, then locks at once
	var f := _fires(_dome(FortressBalance.DOME_MSL_FIRST), 30.0, func(n: float) -> bool: return n >= 20.0)
	_check(f.size() == 1, "blocked dome does not fire while blocked (got %d)" % f.size())
	_check(f.size() > 0 and absf(float(f[0]) - 20.0 - FortressBalance.DOME_MSL_LOCK) < 0.05,
		"locks as soon as it may (got %s)" % str(f))
