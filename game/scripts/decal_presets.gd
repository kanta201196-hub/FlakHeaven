class_name DecalPresets
## Ready decal spots per plane (spec 2026-10-27-plane-decals-design.md §4): the places measured in the first proposal,
## where a ground crew would paint — the nose sides, the side number, the tally under the canopy, the fin, the top
## of the wing. A preset is not a fixed slot: it places an ordinary `DecalRecord` by a ray onto the hull, and the
## player can move it afterwards. Also the editor's symmetry helper (`mirrored`, «на другой борт»).
## Pure functions of a `PlaneHull`: unit-tested on boxes in tests/decals_cases.gd.

const NAMES := ["nose", "number", "tally", "fin", "wing"]
## Spots in model axes (nose +X, up +Y, left wing −Z, length 1). A side spot is [x, y, size], shot from the chosen
## side; the tally x is its front end; a wing spot is [x, |z|, size], shot from above onto the chosen wing.
const SPOTS := {
	"fighter_1": {"nose": [0.33, -0.032, 0.03], "tally": [0.255, -0.022, 0.011], "number": [0.03, -0.035, 0.026],
		"fin": [-0.407, 0.064, 0.035], "wing": [-0.24, 0.09, 0.045]},
	"fighter_2": {"nose": [0.405, -0.036, 0.026], "tally": [0.33, -0.008, 0.01], "number": [0.02, -0.052, 0.016],
		"fin": [-0.318, 0.058, 0.03], "wing": [-0.2, 0.16, 0.05]},
	"attacker_1": {"nose": [0.365, -0.067, 0.03], "tally": [0.285, -0.03, 0.012], "number": [-0.12, -0.034, 0.022],
		"fin": [-0.42, 0.07, 0.035], "wing": [-0.15, 0.17, 0.05]},
	"attacker_2": {"nose": [0.395, -0.064, 0.03], "tally": [0.29, -0.07, 0.012], "number": [-0.18, -0.027, 0.024],
		"fin": [-0.392, 0.08, 0.04], "wing": [-0.18, 0.18, 0.05]},
	"bomber_1": {"nose": [0.38, -0.066, 0.026], "tally": [0.33, -0.053, 0.01], "number": [-0.2, -0.058, 0.03],
		"fin": [-0.404, 0.087, 0.045], "wing": [0.0, 0.12, 0.05]},
	"bomber_2": {"nose": [0.405, -0.046, 0.024], "tally": [0.36, -0.025, 0.01], "number": [0.23, -0.026, 0.016],
		"fin": [-0.378, 0.08, 0.045], "wing": [-0.12, 0.2, 0.05]},
}
const NUMBER_TEXT := "01"   ## digits a number preset starts with
const SNAP := 0.03          ## how far off the skin the mirrored copy looks for the skin, model units


## A record of picture `id` at preset `spot` of plane `key` on `side` (−1 left, +1 right); null for an unknown
## plane or spot, or when the ray misses the skin. Directional pictures on the nose and the tally are mirrored on
## the right side so they face forward on both sides; a number is never mirrored.
static func record(hull: PlaneHull, key: String, spot: String, side: int, id: String) -> DecalRecord:
	var spots: Dictionary = SPOTS.get(key, {})
	if not spots.has(spot) or hull == null or not DecalCatalog.has_image(id):
		return null
	var s: Array = spots[spot]
	var sd := 1.0 if side >= 0 else -1.0
	var hit: Array
	if spot == "wing":
		hit = hull.raycast(Vector3(float(s[0]), 1.0, float(s[1]) * sd), Vector3.DOWN)
	else:
		hit = hull.raycast(Vector3(float(s[0]), float(s[1]), sd), Vector3(0.0, 0.0, -sd))
	if hit.size() != 2:
		return null
	var r := DecalRecord.new()
	r.id = id
	r.pos = hit[0]
	r.normal = hit[1]
	r.size = float(s[2])
	var number := DecalCatalog.kind(id) == "number"
	r.text = NUMBER_TEXT if number else ""
	r.mirror = sd > 0.0 and spot in ["nose", "tally"] and not number
	return r


## The copy of `r` on the other side of the plane (z → −z): the same picture, a mirror image of it, so a pair reads
## symmetric; snapped onto `hull` when one is given (the two sides of a model are not exactly alike). A number stays
## readable (never mirrored).
static func mirrored(r: DecalRecord, hull: PlaneHull) -> DecalRecord:
	var m := DecalRecord.from_dict(r.to_dict())
	if m == null:
		return null
	m.pos = Vector3(r.pos.x, r.pos.y, -r.pos.z)
	m.normal = Vector3(r.normal.x, r.normal.y, -r.normal.z)
	# a reflection turns rotations the other way; the basis's reference (up, or the nose) is unchanged by it
	m.angle = wrapf(-r.angle, -PI, PI)
	m.mirror = false if DecalCatalog.kind(r.id) == "number" else not r.mirror
	if hull != null:
		var hit := hull.raycast(m.pos + m.normal * SNAP, -m.normal, SNAP * 2.0)
		if hit.size() == 2:
			m.pos = hit[0]
			m.normal = hit[1]
	return m


const FIT_SHARE := 0.7   ## a decal fits where at least this share of its box lies on skin it can cover
const FIT_COS := 0.5     ## skin turned further than 60° from the decal does not count (the decal fades there)
const FIT_GRID := Vector2i(7, 5)


## Share of the decal `r` (with `tally` marks) that lies on skin it can cover: a grid over the rectangle of all its
## stamps, each point shot along the decal's normal at `hull`; a hit inside the box depth on skin turned less than
## 60° from the decal counts. Off the plane, over an edge or on a steep side it does not. 1 — the decal fits.
static func fit(hull: PlaneHull, r: DecalRecord, tally: int) -> float:
	var sts := DecalLoadout.stamps(r, maxi(tally, 1))
	if hull == null or sts.is_empty():
		return 1.0
	var b := r.basis_vectors()
	var n := r.normal.normalized()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for st in sts:
		var c := Vector2((st.center - r.pos).dot(b[0]), (st.center - r.pos).dot(b[1]))
		lo = lo.min(c - Vector2(st.half_w, st.half_h))
		hi = hi.max(c + Vector2(st.half_w, st.half_h))
	var depth := maxf(sts[0].half_w, sts[0].half_h) + DecalMesh.DEPTH_PAD
	var good := 0
	for j in FIT_GRID.y:
		for i in FIT_GRID.x:
			var k := Vector2((i + 0.5) / FIT_GRID.x, (j + 0.5) / FIT_GRID.y)
			var q := lo + (hi - lo) * k
			var p := r.pos + b[0] * q.x + b[1] * q.y
			var hit := hull.raycast(p + n * depth, -n, depth * 2.0)
			if hit.size() == 2 and (hit[1] as Vector3).dot(n) >= FIT_COS:
				good += 1
	return float(good) / float(FIT_GRID.x * FIT_GRID.y)


## The largest size up to `r.size` at which `r` fits (`fit` ≥ FIT_SHARE), stepping down by 15 %; SIZE_MIN when even
## that does not fit (a small decal on a thin edge still goes where the player put it)
static func fit_size(hull: PlaneHull, r: DecalRecord, tally: int) -> float:
	var t := DecalRecord.from_dict(r.to_dict())
	if t == null:
		return r.size
	while t.size > DecalRecord.SIZE_MIN and fit(hull, t, tally) < FIT_SHARE:
		t.size = maxf(DecalRecord.SIZE_MIN, t.size * 0.85)
	return t.size
