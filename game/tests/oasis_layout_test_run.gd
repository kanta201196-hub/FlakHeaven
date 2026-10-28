extends Node
## Working part of oasis_layout_test.gd: the old layout (houses and gardens: centre x, z and size x, z on the
## plot, 5 decimals; the generator's next draw after them) against OasisBuild.plan, then the new build's
## determinism and placement.

## Printed by the box oasis (AdobeBuild.oasis on main, fc86d7b) for variants 0–3
const OLD := {
	0: {"houses": [[0.13163, -0.04618, 0.06648, 0.05396], [0.12855, 0.00480, 0.05935, 0.06172],
			[0.07371, -0.13813, 0.06633, 0.05101], [0.13390, -0.04689, 0.07236, 0.04928]],
		"gardens": [[0.02807, 0.17752, 0.09036, 0.08112], [-0.08754, -0.16542, 0.09056, 0.10788],
			[-0.14495, 0.21404, 0.11253, 0.08473], [0.20682, -0.09398, 0.09705, 0.09338]],
		"next": 1192536414},
	1: {"houses": [[0.16013, -0.09075, 0.06658, 0.05205], [0.08849, 0.05463, 0.06002, 0.05269],
			[0.10795, -0.08763, 0.06445, 0.05673], [-0.00728, -0.12919, 0.07411, 0.04762]],
		"gardens": [[0.16997, -0.16720, 0.10175, 0.08902], [-0.17750, -0.06767, 0.10518, 0.07321],
			[0.23397, -0.00586, 0.10230, 0.07177], [-0.19640, -0.05826, 0.12292, 0.09637]],
		"next": 2750588763},
	2: {"houses": [[0.11508, -0.02108, 0.05028, 0.05825], [0.15689, -0.00476, 0.07480, 0.05469],
			[0.03458, -0.11911, 0.05221, 0.06053], [0.15648, -0.05179, 0.06801, 0.05799]],
		"gardens": [[-0.08032, 0.12521, 0.09229, 0.09779], [0.10254, 0.19684, 0.08818, 0.09393],
			[-0.23278, -0.04493, 0.09996, 0.09198], [-0.20059, -0.05455, 0.10591, 0.08007],
			[-0.17834, 0.07259, 0.12097, 0.07451], [0.19278, 0.00150, 0.09917, 0.09852],
			[0.14376, -0.03990, 0.09219, 0.10127]],
		"next": 1069283659},
	3: {"houses": [[-0.00193, -0.07327, 0.07194, 0.05604], [0.08233, 0.05162, 0.06394, 0.04598],
			[0.13242, -0.12490, 0.06289, 0.05176]],
		"gardens": [[0.06470, 0.17878, 0.09623, 0.08579], [0.21086, -0.09509, 0.10091, 0.10971],
			[0.22650, 0.06851, 0.08834, 0.07453], [-0.12404, -0.11269, 0.08121, 0.09688],
			[0.05069, -0.16641, 0.08064, 0.07699]],
		"next": 2781480773},
}


func _ready() -> void:
	var ok := true
	for v in 4:
		var p := OasisBuild.plan(v)
		var old: Dictionary = OLD[v]
		var same := _rows(p["houses"]) == _rows_old(old["houses"]) and _rows(p["gardens"]) == _rows_old(old["gardens"]) \
			and int(p["next"]) == int(old["next"])
		var hm := OasisBuild.homes(v)
		var mesh := OasisBuild.mesh(v)
		OasisBuild._built.erase(v)
		var again := OasisBuild.homes(v)
		var tris := mesh.surface_get_array_len(0) / 3
		var kinds := {}
		var off := 0
		for h: Array in hm:
			kinds[int(h[0])] = true
			var c: Vector2 = (h[1] as Vector2) * OasisBuild.K
			if c.length() > 0.5:
				off += 1
			var k := int(h[0])
			if (k == VillageHouses.CISTERN or k == VillageHouses.PERGOLA) and AdobeBuild.ground_mask("o_oasis", v, c).x < OasisBuild.YARD_MASK:
				off += 1
		print("UNIT: oasis%d layout rng same: %s, models %d, kinds %d, mesh tris %d" % [v, same, hm.size(), kinds.size(), tris])
		if not same:
			print("FAIL oasis_layout: oasis%d plan differs from the old layout:\n%s\n%s" % [v, _rows(p["houses"]), _rows(p["gardens"])])
			ok = false
		if str(hm) != str(again):
			print("FAIL oasis_layout: oasis%d models differ between two builds" % v)
			ok = false
		if off > 0:
			print("FAIL oasis_layout: oasis%d has %d models off the plot or courtyard pieces out of the palm-free yard" % [v, off])
			ok = false
		if hm.is_empty() or tris < 1000:
			print("FAIL oasis_layout: oasis%d built nothing (%d models, %d tris)" % [v, hm.size(), tris])
			ok = false
	get_tree().quit(0 if ok else 1)


func _rows(recs: Array) -> String:
	var out := []
	for r: Dictionary in recs:
		var c: Vector2 = r["c"]
		var s: Vector2 = r["s"]
		out.append("%.5f %.5f %.5f %.5f" % [c.x, c.y, s.x, s.y])
	return "\n".join(out)


func _rows_old(rows: Array) -> String:
	var out := []
	for r: Array in rows:
		out.append("%.5f %.5f %.5f %.5f" % [r[0], r[1], r[2], r[3]])
	return "\n".join(out)
