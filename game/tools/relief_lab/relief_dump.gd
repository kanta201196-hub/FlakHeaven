extends SceneTree
## Relief lab: dumps terrain heights (float32) and rock/zone masks over an area for offline before/after maps.
## Why: biome_map stores 8-bit heights, too coarse for hillshade comparisons of relief variants.
## Run: godot --headless --path game -s res://tools/relief_lab/relief_dump.gd -- --cx=-8 --cz=-6 --w=16 --h=12 --step=20 --out=/path/h.bin
## Output: <out> raw float32 W*H (px above valley floor), <out>.json with size, ceiling and rock mask (base64 bytes).


func _initialize() -> void:
	call_deferred("_run")


## Builds the terrain like the game does (same seed and functions) and samples it on a regular grid.
func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var cx0 := int(args.get("cx", "-8"))
	var cz0 := int(args.get("cz", "-6"))
	var cw := int(args.get("w", "16"))
	var ch := int(args.get("h", "12"))
	var step := float(args.get("step", "20"))
	var out: String = args.get("out", "user://relief.bin")
	var bg: Background = load("res://scripts/background.gd").new()
	root.add_child(bg)
	await process_frame
	var t: Terrain3D = load("res://scripts/terrain3d.gd").new()
	root.add_child(t)
	t.setup(float(args.get("depth", "500")), StandardMaterial3D.new(), bg)
	var C := Terrain3D.CHUNK
	var per := int(C / step)
	var W := cw * per
	var H := ch * per
	var hs := PackedFloat32Array()
	hs.resize(W * H)
	var rock := PackedByteArray()
	rock.resize(W * H)
	var pe := PackedByteArray()   # province elevation class 0…255 (only when the terrain has provinces)
	pe.resize(W * H)
	var pm := PackedByteArray()   # province mesa share 0…255
	pm.resize(W * H)
	var prov := t.has_method("province")
	var t0 := Time.get_ticks_msec()
	for kz in ch:
		for kx in cw:
			var key := Vector2i(cx0 + kx, cz0 + kz)
			var ctx := t._ctx(key)
			for j in per:
				for i in per:
					var x := key.x * C + (i + 0.5) * step
					var z := key.y * C + (j + 0.5) * step
					var v := t.valley(x, z, ctx)
					var r := t._relief(x, z, v, ctx)
					var gi := (kz * per + j) * W + kx * per + i
					hs[gi] = r.x
					rock[gi] = clampi(int(r.y * 255.0), 0, 255)
					if prov:
						var pv: Vector4 = t.call("province", x, z, v)
						pe[gi] = clampi(int(pv.x * 255.0), 0, 255)
						pm[gi] = clampi(int(pv.y * 255.0), 0, 255)
	var ms := Time.get_ticks_msec() - t0
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_buffer(hs.to_byte_array())
	f.close()
	var j := FileAccess.open(out + ".json", FileAccess.WRITE)
	j.store_string(JSON.stringify({"W": W, "H": H, "step": step, "x0": cx0 * C, "z0": cz0 * C,
		"ceiling": t.ceiling, "ms": ms, "us_per_sample": 1000.0 * ms / float(W * H),
		"rock": Marshalls.raw_to_base64(rock), "pe": Marshalls.raw_to_base64(pe), "pm": Marshalls.raw_to_base64(pm)}))
	j.close()
	print("relief_dump: %dx%d in %d ms -> %s" % [W, H, ms, out])
	quit()
