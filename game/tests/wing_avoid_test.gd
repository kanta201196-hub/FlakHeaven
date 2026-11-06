extends SceneTree
## Unit tests for the S16-24 nose rule (`WingFollow.step` with `avoid`, F1 `wing_avoid`): Kanta saw the wingman
## «nose-poke» into the leader again in s16. The leader flies the manoeuvres that made it happen (a hard turn towards
## the wingman, the 0.35 s combat turn, a throttle cut, the wingman coming up from straight behind) and the test
## counts «poke» frames: the wingman closer than 2 clear radii with its nose line crossing the leader's clear disc.
## Pinned here: with the rule on there are no poke frames and the wingman still settles on its slot; the old path
## (rule off) is printed for comparison. Run from the repository root: `tools/ci/unit.sh`.

const DT := 1.0 / 60.0
const PS := 390.0
const CLEAR := 100.5            # Wingman.clear_r for the fighter (size 1)
const FORM_TURN := 75.0         # Wingman.FORM_TURN, °/s

var _failed := 0
var _checks := 0


func _init() -> void:
	var lat := CLEAR + 40.0
	# [what, wingman side, start offset from the slot (leader frame), leader programme [secs, turn °/s, speed ×]]
	var cases := [
		["hard turn towards the wingman", 1.0, Vector2.ZERO, [[1.0, 0.0, 1.0], [2.5, 210.0, 1.0], [5.0, 0.0, 1.0]]],
		["hard turn away from the wingman", 1.0, Vector2.ZERO, [[1.0, 0.0, 1.0], [2.5, -210.0, 1.0], [5.0, 0.0, 1.0]]],
		["combat turn towards", 1.0, Vector2.ZERO, [[1.0, 0.0, 1.0], [0.35, 514.0, 1.0], [7.0, 0.0, 1.0]]],
		["combat turn away", -1.0, Vector2.ZERO, [[1.0, 0.0, 1.0], [0.35, 514.0, 1.0], [7.0, 0.0, 1.0]]],
		["throttle cut", 1.0, Vector2.ZERO, [[1.0, 0.0, 1.0], [3.0, 0.0, 0.6], [5.0, 0.0, 1.0]]],
		["circling towards", 1.0, Vector2.ZERO, [[6.0, 120.0, 1.0], [7.0, 0.0, 1.0]]],
		["coming up from behind", 1.0, Vector2(-600.0, -lat), [[9.0, 0.0, 1.0]]],
		["behind, leader slows", -1.0, Vector2(-400.0, lat), [[2.0, 0.0, 0.6], [7.0, 0.0, 1.0]]],
		# «Сомкнуть строй»: the slot is only 10 px out of the clear radius
		["close formation, turn towards", 1.0, Vector2.ZERO, [[1.0, 0.0, 1.0], [1.5, 160.0, 1.0], [6.0, 0.0, 1.0]], CLEAR + 10.0],
		["close formation, straight", -1.0, Vector2.ZERO, [[6.0, 0.0, 1.0]], CLEAR + 10.0],
	]
	for c in cases:
		var l: float = c[4] if c.size() > 4 else lat
		var old := _fly(c[1], l, c[2], c[3], false)
		var new := _fly(c[1], l, c[2], c[3], true)
		print("  %s: poke frames %d → %d, closest %.0f → %.0f px, end off slot %.0f px" % [c[0], old.pokes, new.pokes,
			old.min_d, new.min_d, new.end_d])
		_check(new.pokes == 0, "%s: no nose-poke frames (%d)" % [c[0], new.pokes])
		_check(new.min_d >= CLEAR * 0.95, "%s: never inside the clear radius (closest %.0f)" % [c[0], new.min_d])
		_check(new.end_d < 20.0, "%s: back on the slot at the end (%.0f px off)" % [c[0], new.end_d])
	_heading_cases()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


## `avoid_heading` alone: untouched when the leader is far or off the nose; a heading on the leader is moved just
## far enough to be safe, on the side the nose already leans to; inside the disc it turns away.
func _heading_cases() -> void:
	var pv := Vector2(PS, 0.0)
	_check(WingFollow.avoid_heading(0.0, 0.0, PS, Vector2(1000.0, 0.0), pv, CLEAR) == 0.0, "far leader: heading kept")
	_check(WingFollow.avoid_heading(PI / 2.0, PI / 2.0, PS, Vector2(200.0, 0.0), pv, CLEAR) == PI / 2.0,
		"leader off the nose: heading kept")
	var slow := Vector2(200.0, 0.0)
	var h := WingFollow.avoid_heading(0.0, 0.01, PS, Vector2(200.0, 0.0), slow, CLEAR)
	_check(h > 0.0 and h < deg_to_rad(45.0), "nose on a slower leader ahead: turns aside, not far (%.0f°)" % rad_to_deg(h))
	_check(absf(h) >= asin(CLEAR / 200.0), "  and the nose line misses the leader")
	h = WingFollow.avoid_heading(0.0, -0.2, PS, Vector2(200.0, 0.0), slow, CLEAR)
	_check(h < 0.0, "nose already left of the leader: dodges left, never swings across")
	h = WingFollow.avoid_heading(0.0, 0.3, PS, Vector2(50.0, 0.0), pv, CLEAR)
	_check(absf(wrapf(h, -PI, PI)) > PI / 2.0 - 0.01, "inside the disc: turns away from the leader (%.0f°)" % rad_to_deg(h))


func _fly(side: float, lat: float, start: Vector2, prog: Array, avoid: bool) -> Dictionary:
	var slot_off := Vector2(-20.0, side * lat)
	var lp := Vector2.ZERO
	var lh := 0.0
	var fh := 0.0
	var wp := slot_off + start
	var st := {"heading": 0.0, "spd": PS, "turn_v": 0.0}
	var out := {"pokes": 0, "min_d": INF, "end_d": 0.0}
	var slot := wp
	var k := 1.0
	for seg in prog:
		for i in int(float(seg[0]) / DT):
			lh += deg_to_rad(float(seg[1])) * DT
			k = move_toward(k, float(seg[2]), 2.0 * DT)
			fh = rotate_toward(fh, lh, deg_to_rad(FORM_TURN) * DT)
			var pv := Vector2.from_angle(lh) * PS * k
			lp += pv * DT
			slot = lp + slot_off.rotated(fh)
			wp = WingFollow.step(st, wp, slot, lp, pv, CLEAR, side, DT, avoid)
			var lead := lp - wp
			var d := lead.length()
			out.min_d = minf(out.min_d, d)
			if d < CLEAR * 2.0:
				var off := absf(wrapf(float(st.heading) - lead.angle(), -PI, PI))
				if off < asin(minf(1.0, CLEAR / d)) * 0.9:
					out.pokes += 1
	out.end_d = wp.distance_to(slot)
	return out


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
