extends Node
## Карта расстановки биома сверху (тред «Второй биом», 18.10.2026): зоны рельефа, объекты клеток,
## модели BiomeProps и сцены прошедших боёв — теми же функциями, что в игре.
## Рабочая часть biome_map.gd (грузится после автозагрузок Tuning/Settings). Запуск: godot --headless --path game -s res://tools/biome_map/biome_map.gd -- --cx=-6 --cz=-4 --w=12 --h=8 --out=/путь/map.json
## Картинку рисует tools/biome_map/render_map.py (Python + Pillow).

const STEP := 20.0
const ZONES := ["river", "road", "bank", "floor", "fan", "slope", "crest"]


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var cx0 := int(args.get("cx", "-6"))
	var cz0 := int(args.get("cz", "-4"))
	var cw := int(args.get("w", "12"))
	var ch := int(args.get("h", "8"))
	var out: String = args.get("out", "user://biome_map.json")
	var bg: Background = load("res://scripts/background.gd").new()
	add_child(bg)
	await get_tree().process_frame
	var t: Terrain3D = load("res://scripts/terrain3d.gd").new()
	add_child(t)
	t.setup(500.0, StandardMaterial3D.new(), bg)
	var props := BiomeProps.new(t)
	t.props = props
	var C := Terrain3D.CHUNK
	var x0 := cx0 * C
	var z0 := cz0 * C
	var W := int(cw * C / STEP)
	var H := int(ch * C / STEP)
	# зоны и высоты
	var zones := PackedByteArray()
	zones.resize(W * H)
	var hts := PackedByteArray()
	hts.resize(W * H)
	var objs := []
	var put_all := {}
	var scn := []
	for kz in ch:
		for kx in cw:
			var key := Vector2i(cx0 + kx, cz0 + kz)
			var ctx := t._ctx(key)
			for j in int(C / STEP):
				for i in int(C / STEP):
					var p := Vector2(key.x * C + (i + 0.5) * STEP, key.y * C + (j + 0.5) * STEP)
					var gi := (kz * int(C / STEP) + j) * W + kx * int(C / STEP) + i
					zones[gi] = ZONES.find(props._zone(p, ctx))
					hts[gi] = clampi(int(t.height(p.x, p.y, ctx) / maxf(t.ceiling, 1.0) * 255.0), 0, 255)
			var o := t._obj(key)
			var raw := bg._chunk_object_raw(key.x, key.y)
			if not raw.is_empty():
				objs.append({"name": raw["name"], "raw": [raw["pos"].x, raw["pos"].y], "size": raw["size"],
					"pos": [o["pos"].x, o["pos"].y] if not o.is_empty() else null,
					"zone": props._zone(o["pos"], ctx) if not o.is_empty() else "",
					"river": absf(t.river_field(o["pos"].x, o["pos"].y)) if not o.is_empty() else -1.0,
					"valley": absf(t.valley(o["pos"].x, o["pos"].y, ctx)) if not o.is_empty() else -1.0})
			var put := props.plan(key, ctx)
			for kind in put:
				if not put_all.has(kind):
					put_all[kind] = []
				for tr: Transform3D in put[kind]:
					put_all[kind].append([snappedf(tr.origin.x, 0.1), snappedf(tr.origin.z, 0.1), snappedf(tr.basis.get_scale().x, 0.1)])
			for it in t.scenes(key):
				scn.append({"k": it["k"], "p": [it["p"].x, it["p"].y], "r": it["r"]})
		print("ряд %d/%d" % [kz + 1, ch])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"x0": x0, "z0": z0, "W": W, "H": H, "step": STEP, "zones": ZONES,
		"zone": Marshalls.raw_to_base64(zones), "h": Marshalls.raw_to_base64(hts),
		"objs": objs, "props": put_all, "scenes": scn}))
	f.close()
	print("готово: ", out)
	get_tree().quit()
