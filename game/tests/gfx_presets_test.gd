extends SceneTree
## Unit tests for `GfxPresets` (UI-01 step 3): the quality presets and per-option graphics
## settings. Rules pinned here: every preset holds a valid value for every option, the presets
## reproduce the look of the old single «Качество графики» switch, changing any option after a
## preset reads as «Своё», saved options are cleaned up on load, and Forward+-only values fall
## back to something the Compatibility renderer can draw.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_presets_valid()
	_test_presets_match_old_switch()
	_test_custom()
	_test_sanitize()
	_test_fallback()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_presets_valid() -> void:
	_check(GfxPresets.PRESETS.size() == 4, "four presets: low, medium, high, max")
	for i in GfxPresets.PRESETS.size():
		var p := GfxPresets.preset(i)
		for id: String in GfxPresets.IDS:
			_check(p.has(id), "preset %d has %s" % [i, id])
			_check(p.get(id, -1) >= 0 and p.get(id, 99) < GfxPresets.count(id), "preset %d %s in range" % [i, id])
	_check(GfxPresets.preset_of(GfxPresets.preset(2)) == 2, "a preset reads back as itself")


## Old `Render3D.apply_gfx`: scale 60/80/100/100 %, shadow atlas 1024/2048/4096/4096, MSAA 2× only on max.
## Under the Compatibility fallback presets 0–2 still draw exactly that; Forward+ adds on top.
func _test_presets_match_old_switch() -> void:
	var scale := [60, 80, 100, 100]
	var atlas := [1024, 2048, 4096, 4096]
	for i in 4:
		var p := GfxPresets.preset(i)
		var c := GfxPresets.effective(p, false)
		_check(GfxPresets.SCALES[p["scale"]] == scale[i], "preset %d render scale as before" % i)
		_check(GfxPresets.SHADOW_RES[p["shadow_res"]] == atlas[i], "preset %d shadow atlas as before" % i)
		_check(p["terrain"] == i and p["props"] == i and p["effects"] == i, "preset %d world detail and effects follow the level" % i)
		if i < 3:
			_check(c["aa"] == GfxPresets.AA_OFF, "preset %d: no antialiasing in Compatibility, as before" % i)
			_check(c["shadows"] == GfxPresets.SHADOWS_HIGH, "preset %d keeps the default soft shadows" % i)
			_check(c["ssao"] == 0 and c["ssil"] == 0 and c["upscale"] == 0, "preset %d: nothing Forward+-only left in Compatibility" % i)
	_check(GfxPresets.preset(0)["upscale"] > 0 and GfxPresets.preset(1)["upscale"] > 0, "low and medium upscale with FSR in Forward+")
	_check(GfxPresets.preset(2)["ssao"] > 0 and GfxPresets.preset(3)["ssao"] > GfxPresets.preset(2)["ssao"], "ambient occlusion grows with the preset")
	_check(GfxPresets.preset(3)["aa"] == GfxPresets.AA_MSAA4, "max: MSAA 4×")


func _test_custom() -> void:
	var p := GfxPresets.preset(2)
	p["shadow_res"] = 3
	_check(GfxPresets.preset_of(p) == -1, "a changed option reads as custom")
	p["shadow_res"] = GfxPresets.preset(2)["shadow_res"]
	_check(GfxPresets.preset_of(p) == 2, "changing it back returns to the preset")


func _test_sanitize() -> void:
	var s := GfxPresets.sanitize({"scale": 99, "aa": -3, "junk": 1, "terrain": 1.0}, 1)
	var base := GfxPresets.preset(1)
	_check(s["scale"] == base["scale"], "out-of-range value falls back to the preset")
	_check(s["aa"] == base["aa"], "negative value falls back to the preset")
	_check(not s.has("junk"), "unknown keys dropped")
	_check(s["terrain"] == 1 and typeof(s["terrain"]) == TYPE_INT, "JSON floats become ints")
	_check(s.size() == GfxPresets.IDS.size(), "every option present after load")


func _test_fallback() -> void:
	var p := GfxPresets.preset(3)
	p["aa"] = GfxPresets.AA_TAA
	p["shadows"] = GfxPresets.SHADOWS_OFF
	p["ssao"] = 2
	p["upscale"] = 2
	var c := GfxPresets.effective(p, false)
	_check(c["aa"] == GfxPresets.AA_OFF, "TAA falls back to off in Compatibility")
	_check(c["shadows"] == GfxPresets.SHADOWS_LOW, "shadows off falls back to low (Compatibility frame darkens without sun shadows)")
	_check(c["ssao"] == 0 and c["upscale"] == 0, "Forward+-only effects off in Compatibility")
	_check(GfxPresets.effective(p, true)["aa"] == GfxPresets.AA_TAA, "Forward+ keeps TAA")
	p["aa"] = GfxPresets.AA_FXAA
	_check(GfxPresets.effective(p, false)["aa"] == GfxPresets.AA_OFF, "FXAA falls back to off in Compatibility (4.4.1 draws no FXAA there)")
	_check(not GfxPresets.supported("ssao", 1, false) and GfxPresets.supported("ssao", 0, false), "SSAO levels need Forward+")
	_check(GfxPresets.supported("aa", GfxPresets.AA_MSAA4, false), "MSAA works in Compatibility")
