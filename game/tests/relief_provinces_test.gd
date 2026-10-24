extends SceneTree
## Unit tests for `ReliefProvinces` (RV-01): landform regions of the Нагорье relief.
## They pin the rules Kanta chose on 2026-10-24 (varied regions, valley floor untouched,
## no walls at region borders, mountains under the combat plane), not the exact look.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0
var _p := ReliefProvinces.new()
## Valley floor edge used by Terrain3D (D_FAN − 40): below it the relief must stay flat.
const FLOOR := 440.0


func _init() -> void:
	_test_deterministic()
	_test_ranges()
	_test_floor_untouched()
	_test_area_shares()
	_test_regional_contrast()
	_test_no_border_walls()
	_test_mesa_ledges_not_flat()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## Synthetic valley field for tests: distance to a river along z = 0 every 9 km, with sign.
func _v(x: float, z: float) -> float:
	var m := fposmod(z, 9000.0) - 4500.0
	return 4500.0 - absf(m) if m < 0.0 else -(4500.0 - absf(m))


## Same point gives the same weights and height, also on a second instance (world is seeded).
func _test_deterministic() -> void:
	var q := ReliefProvinces.new()
	for i in 20:
		var x := -30000.0 + i * 3100.0
		var z := 12000.0 - i * 1700.0
		var v := _v(x, z)
		_check(_p.weights(x, z, v) == q.weights(x, z, v), "weights deterministic at %d" % i)
		_check(_p.relief(x, z, absf(v), v) == q.relief(x, z, absf(v), v), "relief deterministic at %d" % i)


## Weights and outputs stay in their ranges everywhere.
func _test_ranges() -> void:
	var ok_w := true
	var ok_h := true
	for j in 60:
		for i in 60:
			var x := -40000.0 + i * 1333.0
			var z := -40000.0 + j * 1333.0
			var v := _v(x, z)
			var w := _p.weights(x, z, v)
			ok_w = ok_w and w.x >= 0.0 and w.x <= 1.0 and w.y >= 0.0 and w.y <= 1.0 and w.w >= 0.0 and w.w <= 1.0
			ok_w = ok_w and w.z >= ReliefBalance.ASYM_MIN - 1e-4 and w.z <= ReliefBalance.ASYM_MAX + 1e-4
			var r := _p.relief(x, z, absf(v), v)
			ok_h = ok_h and r.x >= -0.03 and r.x <= 1.0 and r.y >= 0.0 and r.y <= 1.0 and r.z >= 0.0 and r.z <= 1.0
	_check(ok_w, "weights in range")
	_check(ok_h, "relief share, rock and scree in range (mountains under the combat plane)")


## River, road, fields and settlements sit on the valley floor: no mountain part there.
func _test_floor_untouched() -> void:
	var worst := 0.0
	for i in 400:
		var x := -20000.0 + i * 97.0
		var z := 3000.0 + i * 53.0
		for a in [0.0, 40.0, 85.0, 200.0, 300.0]:
			worst = maxf(worst, _p.relief(x, z, a, a).x - ReliefBalance.FLOOR_MAX)
	_check(worst <= 1e-4, "valley floor flat below the fan (excess %.4f)" % worst)


## Share of each landform over a 60 × 60 km area (classified by weights).
func _shares() -> Dictionary:
	var n := {"hills": 0, "mid": 0, "high": 0, "mesa": 0}
	var tot := 0
	for j in 150:
		for i in 150:
			var x := -30000.0 + i * 400.0
			var z := -30000.0 + j * 400.0
			n[ReliefProvinces.kind(_p.weights(x, z, 1000.0))] += 1
			tot += 1
	for k in n:
		n[k] = float(n[k]) / float(tot)
	return n


func _test_area_shares() -> void:
	var s := _shares()
	print("UNIT: landform shares ", s)
	_check(s["hills"] >= 0.15 and s["hills"] <= 0.45, "hills 15–45 %% (%.2f)" % s["hills"])
	_check(s["high"] >= 0.12 and s["high"] <= 0.45, "high ranges 12–45 %% (%.2f)" % s["high"])
	_check(s["mesa"] >= 0.06 and s["mesa"] <= 0.3, "mesas 6–30 %% (%.2f)" % s["mesa"])
	_check(s["mid"] >= 0.08, "mid mountains at least 8 %% (%.2f)" % s["mid"])


## Peaks differ between regions: std of 4 × 4 km window maxima at least 0.08 of the ceiling
## (the old relief: 0.04, every massif nearly the same height).
func _test_regional_contrast() -> void:
	var peaks: Array[float] = []
	for wj in 8:
		for wi in 8:
			var mx := 0.0
			for j in 20:
				for i in 20:
					var x := -16000.0 + wi * 4000.0 + i * 200.0
					var z := -16000.0 + wj * 4000.0 + j * 200.0
					mx = maxf(mx, _p.relief(x, z, 1600.0, 1600.0).x)
			peaks.append(mx)
	var mean := 0.0
	for p in peaks:
		mean += p / peaks.size()
	var sd := 0.0
	for p in peaks:
		sd += (p - mean) * (p - mean) / peaks.size()
	sd = sqrt(sd)
	_check(sd >= 0.08, "regional peak contrast std ≥ 0.08 (%.3f)" % sd)


## Region borders blend smoothly: where the elevation class is between two regions (and no
## mesa cliff is near), neighbours 20 px apart differ by less than 0.12 of the ceiling — a sheer
## wall there would read as a seam. Sharp ledges inside a high range are allowed.
func _test_no_border_walls() -> void:
	var worst := 0.0
	for j in 120:
		for i in 120:
			var x := -24000.0 + i * 400.0
			var z := -24000.0 + j * 400.0
			var w := _p.weights(x, z, 1500.0)
			if w.y > 0.05 or w.x < 0.15 or w.x > 0.85:
				continue
			var h0 := _p.relief(x, z, 1500.0, 1500.0).x
			var h1 := _p.relief(x + 20.0, z, 1500.0, 1500.0).x
			worst = maxf(worst, absf(h1 - h0))
	_check(worst <= 0.12, "no walls at region borders (worst step %.3f)" % worst)


## Kanta 24.10 («резкие перепады высот и идеально ровное место, так не бывает»): mesa ledges and
## gorge floors roll and dip; dead-flat ground (under 1.5° at a 470 px ceiling) stays under 4 %
## of mesa land off the valley floor (it was 10–15 % with flat-stepped ledges).
func _test_mesa_ledges_not_flat() -> void:
	var n := 0
	var flat := 0
	for j in 160:
		for i in 160:
			var x := -24000.0 + i * 300.0 + 0.37
			var z := -24000.0 + j * 300.0 + 0.61
			var v := _v(x, z)
			if absf(v) < 600.0 or _p.weights(x, z, v).y < 0.8:
				continue
			var h := _p.relief(x, z, absf(v), v).x
			var hx := _p.relief(x + 8.0, z, absf(_v(x + 8.0, z)), _v(x + 8.0, z)).x
			var hz := _p.relief(x, z + 8.0, absf(_v(x, z + 8.0)), _v(x, z + 8.0)).x
			var g := Vector2(hx - h, hz - h).length() * 470.0 / 8.0
			n += 1
			if rad_to_deg(atan(g)) < 1.5:
				flat += 1
	var share := float(flat) / maxf(n, 1.0)
	_check(n > 200, "enough mesa samples (%d)" % n)
	_check(share < 0.04, "dead-flat mesa ground under 4 %% (%.3f of %d)" % [share, n])
