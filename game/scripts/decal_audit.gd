class_name DecalAudit
extends RefCounted
## Decal geometry audit (Kanta 27.10: «проверь геометрию, чтобы все наклейки корректно накладывались на все модели
## в разных местах и вариациях»). Places decals programmatically on a built plane model (the hangar model with its
## weapons, fairings and moving parts, or the battle model) and measures, per decal, what a player would see wrong:
## stretched or wrapped pieces, pieces printed on the back of a thin part, holes, z-fighting, floating, a decal hidden
## under a fairing or a turret, a decal over a flap that does not follow it, a mirrored copy that is not symmetric.
##
## How: every stamp of a decal gets an orthographic «camera» along its normal; the model's triangles (all of them,
## tagged skin / glass / moving part / add-on / insignia / well) and the decal's own triangles are rasterised into
## small depth grids in that frame. Comparing the two at each opaque pixel of the picture tells whether the decal is
## visible there, hidden under something, missing, too close to the skin or floating. Area statistics of the decal's
## triangles give the stretch, the wrap round an edge and the back-face leak. Pure functions of triangle sets, so the
## rules are unit-tested on boxes (tests/decals_cases.gd); the bench (`--decalaudit`, VisualBench) feeds it models.

const RES := 20              ## raster samples along each side of a stamp
const TOL := 0.0012          ## depth slack between a decal and the surface it lies on, model units
const OCC_REACH := 0.06      ## how far in front of a decal an add-on still counts as lying on it (a turret, a pod)
const ZFIGHT := 0.0001       ## decal nearer than this to the surface below (along the normal): z-fighting risk
const ZFIGHT_INS := 0.0001   ## a roundel has to lie at least this far over a decal (it stays on top, spec §2.4)
const CUT_COS := 0.55        ## skin turned further than ~57° from a decal may stay bare (the decal fades there)
const ZFIGHT_PAIR := 0.00002 ## two overlapping decals nearer than this to each other draw in no fixed order
const FLOAT := 0.003         ## farther than this: the decal floats
const STRETCH := 1.5         ## area stretch of a decal triangle (1 / facing) counted as stretched
const WRAP_COS := 0.5        ## a decal triangle turned more than 60° from the decal's normal wraps round an edge
const BACK_COS := 0.0        ## a decal triangle facing away from the decal (printed on the far side of a thin part)

## The decal hull of the model being audited (PlaneDecals.hull_of): digits and marks are seated on it, as DecalMesh does
static var seat_hull: PlaneHull = null

enum Tag {SKIN, GLASS, PART, ADDON, INSIGNIA, WELL}
## Problem categories in report order, with the share of a decal (opaque samples, or decal area for the area ones)
## above which a decal counts as having that problem
const LIMITS := {
	"stretch": 0.10, "wrap": 0.03, "back_leak": 0.005, "behind_skin": 0.03, "gap": 0.03, "part_missing": 0.03,
	"under_part": 0.03, "hidden_addon": 0.03, "zfight": 0.03, "zfight_insignia": 0.03, "hides_insignia": 0.03,
	"float": 0.03, "overhang": 0.15, "cursor_behind": 0.5, "asym": 0.5, "zfight_pair": 0.03,
}

static var _atlas: Image


## Triangles of a model in model axes with what they belong to; `hull` is a view on them for the grid lookups
class Tris:
	extends RefCounted
	var pos := PackedVector3Array()   ## 3 per triangle
	var nrm := PackedVector3Array()   ## smooth vertex normals, 3 per triangle
	var gn := PackedVector3Array()    ## geometric (winding) normal, 1 per triangle
	var tag := PackedInt32Array()     ## Tag per triangle
	var owner := PackedInt32Array()   ## index into `names` per triangle
	var paint := PackedFloat32Array() ## decals: primary paint index (UV2.x), tells overlapping decals apart
	var fade := PackedFloat32Array()  ## decals: vertex alpha (COLOR.a, DecalMesh's fade at a steep skin), 3 per triangle
	var names: Array[String] = []
	var hull: PlaneHull

	## Builds the grid view once all triangles are in
	func done() -> void:
		hull = PlaneHull.from_triangles(pos, nrm)

	func count() -> int:
		return gn.size()


## One stamp's orthographic view: centre, right, up, normal (towards the viewer) and half sizes
class Frame:
	extends RefCounted
	var c := Vector3.ZERO
	var r := Vector3.RIGHT
	var u := Vector3.UP
	var n := Vector3.BACK
	var hw := 0.01
	var hh := 0.01

	static func of_stamp(st: DecalStamp) -> Frame:
		var f := Frame.new()
		f.c = st.center
		f.r = st.right
		f.u = st.up
		f.n = st.normal.normalized()
		f.hw = st.half_w
		f.hh = st.half_h
		return f

	## The same frame reflected through the plane's symmetry plane (z → −z)
	func reflected() -> Frame:
		var f := Frame.new()
		f.c = Vector3(c.x, c.y, -c.z)
		f.r = Vector3(r.x, r.y, -r.z)
		f.u = Vector3(u.x, u.y, -u.z)
		f.n = Vector3(n.x, n.y, -n.z)
		f.hw = hw
		f.hh = hh
		return f


## Depth grid of one raster: per sample the highest z (towards the viewer) and the triangle there, -1 none
class Grid:
	extends RefCounted
	var z := PackedFloat32Array()
	var tri := PackedInt32Array()

	func _init() -> void:
		z.resize(DecalAudit.RES * DecalAudit.RES)
		z.fill(-INF)
		tri.resize(DecalAudit.RES * DecalAudit.RES)
		tri.fill(-1)


# ---------- collecting triangles ----------

## Triangles of every shown mesh under `root` in the axes of `model` (a child of `root`, or `root` itself).
## `decals` true — only the decal meshes (nodes named «decals…»), false — everything but them and the editor preview;
## `insignia` — only the insignia (true) or everything but them (false); ignored for decals.
static func collect(root: Node3D, model: Node3D, decals: bool, insignia := false) -> Tris:
	var out := Tris.new()
	var body := PlaneHull.body(model)
	var to_model := PlaneHull.rel_transform(model, root).affine_inverse() if model != root else Transform3D.IDENTITY
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or not _shown(mi, root):
			continue
		var nm := String(mi.name)
		var is_decal := nm.begins_with("decals")
		if is_decal != decals or nm.begins_with("decal_preview"):
			continue
		if not decals and PlaneHull.under(mi, model, ["insignia"]) != insignia:
			continue
		var xf := to_model * PlaneHull.rel_transform(mi, root)
		var up: Node = mi
		while nm.begins_with("@") and up.get_parent() != null and up.get_parent() != root:   # weapon meshes: unnamed
			up = up.get_parent()
			nm = String(up.name)
		for si in mi.mesh.get_surface_count():
			var tg := Tag.SKIN if decals else _tag(mi, si, model, body)
			_append(out, mi.mesh, si, xf, tg, nm, decals)
	out.done()
	return out


## Tag of surface `si` of `mi`: what a decal pixel over it means
static func _tag(mi: MeshInstance3D, si: int, model: Node3D, body: MeshInstance3D) -> int:
	var m := mi.mesh.surface_get_material(si)
	var mname := String(m.resource_name) if m != null else ""
	if mname == "glass":
		return Tag.GLASS
	if PlaneHull.under(mi, model, ["insignia"]):
		return Tag.INSIGNIA
	if PlaneHull.under(mi, model, ["wing_mech", "bay_doors"]):
		return Tag.WELL if String(mi.name).begins_with("bay_well") else Tag.PART
	if mi == body:
		var bm := m as BaseMaterial3D
		return Tag.SKIN if bm != null and bm.albedo_texture != null else Tag.WELL
	if mi.has_meta(PlaneDecals.FAIRING) or PlaneHull.under(mi, model, ["detail", "tail_cabin"]):
		return Tag.SKIN   # decal skin since the audit (PlaneHull.statics_of)
	return Tag.ADDON


## True when `n` and every parent up to `root` are visible
static func _shown(n: Node, root: Node) -> bool:
	var p: Node = n
	while p != null:
		if p is Node3D and not (p as Node3D).visible:
			return false
		if p == root:
			return true
		p = p.get_parent()
	return true


static func _append(out: Tris, mesh: Mesh, si: int, xf: Transform3D, tg: int, nm: String, decals: bool) -> void:
	var arr := mesh.surface_get_arrays(si)
	var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nv: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var iv: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2] if arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var cv: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var n := iv.size() if iv.size() > 0 else vv.size()
	n -= n % 3
	var start := out.gn.size()
	var vote := 0.0   # winding convention of this surface: the cross product along or against the smooth normals
	var crosses: Array[Vector3] = []
	var oi := out.names.find(nm)
	if oi < 0:
		out.names.append(nm)
		oi = out.names.size() - 1
	for t in range(0, n, 3):
		var ps: Array[Vector3] = []
		var ns := Vector3.ZERO
		for k in 3:
			var vi := iv[t + k] if iv.size() > 0 else t + k
			var p := xf * vv[vi]
			var vn := (xf.basis * (nv[vi] if nv.size() > vi else Vector3.UP)).normalized()
			ps.append(p)
			ns += vn
			out.pos.append(p)
			out.nrm.append(vn)
			out.fade.append(cv[vi].a if decals and cv.size() > vi else 1.0)
		var cr := (ps[1] - ps[0]).cross(ps[2] - ps[0])
		vote += signf(cr.dot(ns))
		crosses.append(cr.normalized())
		out.tag.append(tg)
		out.owner.append(oi)
		var first := iv[t] if iv.size() > 0 else t
		out.paint.append(u2[first].x if decals and u2.size() > first else 0.0)
	var sgn := 1.0 if vote >= 0.0 else -1.0
	for cr in crosses:
		out.gn.append(cr * sgn)
	assert(out.gn.size() == start + crosses.size())


# ---------- rasterising ----------

## Rasterises the triangles of `t` facing the viewer of `f` (only tag `only`, -1 all; only paint `paint`, -1 all)
## with depth in [zlo, zhi] into a depth grid
static func raster(t: Tris, f: Frame, zlo: float, zhi: float, only := -1, paint := -1.0) -> Grid:
	var g := Grid.new()
	var reach := maxf(absf(zlo), absf(zhi))
	var ext := f.r.abs() * f.hw + f.u.abs() * f.hh + f.n.abs() * reach
	var k := RES * 0.5
	for ti in t.hull.near(f.c - ext, f.c + ext):
		if only >= 0 and t.tag[ti] != only:
			continue
		if paint >= 0.0 and absf(t.paint[ti] - paint) > 0.25:
			continue
		if t.gn[ti].dot(f.n) <= 0.0:
			continue
		var s: Array[Vector3] = []
		var zmin := INF
		var zmax := -INF
		for i in 3:
			var rel := t.pos[ti * 3 + i] - f.c
			var z := rel.dot(f.n)
			zmin = minf(zmin, z)
			zmax = maxf(zmax, z)
			# sample space: column i at x = -1 + (i + 0.5) / k, row j at y = 1 - (j + 0.5) / k
			s.append(Vector3((rel.dot(f.r) / f.hw + 1.0) * k - 0.5, (1.0 - rel.dot(f.u) / f.hh) * k - 0.5, z))
		if zmax < zlo or zmin > zhi:
			continue
		var i0 := maxi(0, ceili(minf(s[0].x, minf(s[1].x, s[2].x))))
		var i1 := mini(RES - 1, floori(maxf(s[0].x, maxf(s[1].x, s[2].x))))
		var j0 := maxi(0, ceili(minf(s[0].y, minf(s[1].y, s[2].y))))
		var j1 := mini(RES - 1, floori(maxf(s[0].y, maxf(s[1].y, s[2].y))))
		if i0 > i1 or j0 > j1:
			continue
		var den := (s[1].y - s[2].y) * (s[0].x - s[2].x) + (s[2].x - s[1].x) * (s[0].y - s[2].y)
		if absf(den) < 1e-12:
			continue
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var w0 := ((s[1].y - s[2].y) * (i - s[2].x) + (s[2].x - s[1].x) * (j - s[2].y)) / den
				var w1 := ((s[2].y - s[0].y) * (i - s[2].x) + (s[0].x - s[2].x) * (j - s[2].y)) / den
				var w2 := 1.0 - w0 - w1
				if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6:
					continue
				var z := w0 * s[0].z + w1 * s[1].z + w2 * s[2].z
				if z < zlo or z > zhi:
					continue
				if t.fade[ti * 3] < 0.999 or t.fade[ti * 3 + 1] < 0.999 or t.fade[ti * 3 + 2] < 0.999:
					# the alpha scissor cuts a faded decal at 0.5
					if w0 * t.fade[ti * 3] + w1 * t.fade[ti * 3 + 1] + w2 * t.fade[ti * 3 + 2] < 0.5:
						continue
				var q := j * RES + i
				if z > g.z[q]:
					g.z[q] = z
					g.tri[q] = ti
	return g


## Coverage of the picture at sample `q` of stamp `st`: atlas alpha ≥ 0.5 (always true without an atlas)
static func opaque(st: DecalStamp, q: int) -> bool:
	if _atlas == null:
		var tex := load(DecalCatalog.ATLAS_PATH) as Texture2D
		_atlas = tex.get_image() if tex != null else Image.create(8, 4, false, Image.FORMAT_RGBA8)
		if _atlas.is_compressed():
			_atlas.decompress()
	var i := q % RES
	var j := floori(q / float(RES))
	var u := (i + 0.5) / RES
	if st.mirror:
		u = 1.0 - u
	var v := (j + 0.5) / RES
	var px := st.uv.position + Vector2(u, v) * st.uv.size
	var x := clampi(int(px.x * _atlas.get_width()), 0, _atlas.get_width() - 1)
	var y := clampi(int(px.y * _atlas.get_height()), 0, _atlas.get_height() - 1)
	return _atlas.get_pixel(x, y).a >= 0.5


# ---------- one decal ----------

## Problems of one decal (record `r` with `tally` marks) given the model's triangles `scene` (without insignia), the
## shown insignia `ins` (collected after the decal was built: a decal over the fin badge hides it) and the decal's own
## triangles `dec` (only this decal): {category: share, "opaque": samples, "visible": samples, "by": {owner: samples}};
## shares as in LIMITS; "by" — which meshes hide the decal or leave it missing
static func audit(scene: Tris, ins: Tris, dec: Tris, r: DecalRecord, tally: int) -> Dictionary:
	var cnt := {}
	var by := {}
	var opaque_n := 0
	var visible_n := 0
	for st in DecalLoadout.stamps(r, tally, seat_hull):
		var f := Frame.of_stamp(st)
		var depth := maxf(st.half_w, st.half_h) + 0.004
		var zs := raster(scene, f, -depth - 0.01, OCC_REACH)
		var zi := raster(ins, f, -depth - 0.01, depth + 0.01) if ins != null else Grid.new()
		var zk := raster(scene, f, -depth - 0.01, depth + 0.01, Tag.SKIN)
		var zd := raster(dec, f, -depth - 0.01, depth + 0.01)
		for q in RES * RES:
			if not opaque(st, q):
				continue
			opaque_n += 1
			var cat := classify(scene, dec, f, zs.z[q], zs.tri[q], zi.z[q], zk.z[q], zk.tri[q], zd.z[q], zd.tri[q], depth)
			if cat in ["ok", "zfight", "zfight_insignia", "float", "hides_insignia"]:
				visible_n += 1
			if cat != "ok":
				cnt[cat] = int(cnt.get(cat, 0)) + 1
				if cat in ["hidden_addon", "under_part", "part_missing", "behind_skin", "gap"] and zs.tri[q] >= 0:
					var nm := scene.names[scene.owner[zs.tri[q]]]
					by[nm] = int(by.get(nm, 0)) + 1
	var out := {"opaque": opaque_n, "visible": visible_n, "by": by}
	for k: String in cnt:
		out[k] = float(cnt[k]) / maxf(1.0, float(opaque_n))
	var area := area_stats(dec, r.normal.normalized())
	for k: String in area:
		if float(area[k]) > 0.0:
			out[k] = area[k]
	return out


## What one opaque decal pixel shows: «ok», or the problem there. `zs`/`ts` — the nearest surface of the model and
## its triangle, `zi` — the nearest insignia, `zk`/`tk` — the nearest skin, `zd`/`td` — the nearest decal piece;
## −INF / -1 when there is none.
static func classify(scene: Tris, dec: Tris, f: Frame, zs: float, ts: int, zi: float, zk: float, tk: int, zd: float,
		td: int, depth: float) -> String:
	var has_d := td >= 0
	if has_d and zi > -INF and absf(zi - zd) < FLOAT and (ts < 0 or zs <= maxf(zi, zd) + TOL):
		# a decal over a roundel (spec §2.4): it may overlap it but never hides it, and the two must not z-fight
		var d := (zi - zd) * maxf(0.05, dec.gn[td].dot(f.n))
		if d < -ZFIGHT_INS:
			return "hides_insignia"
		return "zfight_insignia" if d < ZFIGHT_INS else "ok"
	if ts < 0 and not has_d:
		return "overhang"   # off the plane: the decal is larger than the part under it
	if has_d and (ts < 0 or zs <= zd + TOL):
		# the decal is what the viewer sees: check how far it sits off the surface under it (skin, fairing, part)
		if ts < 0:
			return "float"   # nothing under it at all
		var off := (zd - zs) * maxf(0.05, dec.gn[td].dot(f.n))
		if off < ZFIGHT:
			return "zfight"
		if off > FLOAT:
			return "float"
		return "ok"
	var tg := scene.tag[ts]
	if has_d:   # something lies in front of the decal
		match tg:
			Tag.PART:
				return "under_part"
			Tag.ADDON, Tag.GLASS:
				return "hidden_addon"
			Tag.WELL:
				return "gap"
		return "behind_skin"
	match tg:
		Tag.SKIN:
			return "gap" if scene.gn[ts].dot(f.n) >= CUT_COS and zs > -depth else "cut"
		Tag.PART:
			return "part_missing"
		Tag.ADDON:
			return "hidden_addon"
		Tag.GLASS:
			return "glass"
	return "well"


## Area shares of the decal's triangles that are stretched (1 / facing > STRETCH), wrap round an edge (facing
## < WRAP_COS) or face away from the decal (`back_leak`: printed on the far side of a thin part)
static func area_stats(dec: Tris, n: Vector3) -> Dictionary:
	var total := 0.0
	var st := 0.0
	var wr := 0.0
	var bk := 0.0
	for t in dec.count():
		var a := (dec.pos[t * 3 + 1] - dec.pos[t * 3]).cross(dec.pos[t * 3 + 2] - dec.pos[t * 3]).length() * 0.5
		if dec.fade[t * 3] + dec.fade[t * 3 + 1] + dec.fade[t * 3 + 2] < 1.5:
			continue   # faded out: not drawn
		var c := dec.gn[t].dot(n)
		total += a
		if c <= BACK_COS:
			bk += a
		elif c < WRAP_COS:
			wr += a
			st += a
		elif c < 1.0 / STRETCH:
			st += a
	if total <= 0.0:
		return {}
	return {"stretch": st / total, "wrap": wr / total, "back_leak": bk / total}


## Symmetry of a decal and its mirrored copy: [IoU of their visible coverage (the copy seen in the reflected frame of
## the original), distance of the copy's centre from the reflected centre, angle between the copy's up and the
## reflected up (radians)]. `dec` holds both decals' triangles; `a` and `b` must have different primary paints.
static func symmetry(scene: Tris, dec: Tris, a: DecalRecord, b: DecalRecord, tally: int) -> Array:
	var pa := float(DecalCatalog.paint_index(a.c1))
	var pb := float(DecalCatalog.paint_index(b.c1))
	var inter := 0
	var uni := 0
	for st in DecalLoadout.stamps(a, tally, seat_hull):
		var f := Frame.of_stamp(st)
		var depth := maxf(st.half_w, st.half_h) + 0.004
		var fr := f.reflected()
		var ga := raster(dec, f, -depth - 0.01, depth + 0.01, -1, pa)
		var gsa := raster(scene, f, -depth - 0.01, OCC_REACH)
		var gb := raster(dec, fr, -depth - 0.01, depth + 0.01, -1, pb)
		var gsb := raster(scene, fr, -depth - 0.01, OCC_REACH)
		for q in RES * RES:
			var va := ga.tri[q] >= 0 and (gsa.tri[q] < 0 or gsa.z[q] <= ga.z[q] + TOL)
			var vb := gb.tri[q] >= 0 and (gsb.tri[q] < 0 or gsb.z[q] <= gb.z[q] + TOL)
			if va or vb:
				uni += 1
			if va and vb:
				inter += 1
	var ref := Vector3(a.pos.x, a.pos.y, -a.pos.z)
	var ua := a.basis_vectors()[1]
	var ub := b.basis_vectors()[1]
	var iou := float(inter) / float(uni) if uni > 0 else 1.0
	return [iou, b.pos.distance_to(ref), Vector3(ua.x, ua.y, -ua.z).angle_to(ub)]


## Problem names of an audit result over their limits
static func problems(res: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k: String in LIMITS:
		if float(res.get(k, 0.0)) > float(LIMITS[k]):
			out.append(k)
	return out


## Share of the opaque samples of `a` where `a` and `b` (different primary paints, both in `dec`) are both drawn
## closer than ZFIGHT to each other: overlapping decals that z-fight instead of drawing in list order
static func overlap_zfight(dec: Tris, a: DecalRecord, b: DecalRecord, tally: int) -> float:
	var pa := float(DecalCatalog.paint_index(a.c1))
	var pb := float(DecalCatalog.paint_index(b.c1))
	var both := 0
	var bad := 0
	for st in DecalLoadout.stamps(a, tally, seat_hull):
		var f := Frame.of_stamp(st)
		var depth := maxf(st.half_w, st.half_h) + 0.004
		var ga := raster(dec, f, -depth - 0.01, depth + 0.01, -1, pa)
		var gb := raster(dec, f, -depth - 0.01, depth + 0.01, -1, pb)
		for q in RES * RES:
			if ga.tri[q] < 0 or gb.tri[q] < 0:
				continue
			both += 1
			var face := maxf(0.05, dec.gn[ga.tri[q]].dot(f.n))
			if absf(ga.z[q] - gb.z[q]) * face < ZFIGHT_PAIR:
				bad += 1
	return float(bad) / float(both) if both > 0 else 0.0
