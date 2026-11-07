extends SceneTree
## Unit tests for `ComicKeys` (the pure maths of the comic-page cutscenes, plan 2026-11-07, ST-12) and the
## `StoryComic` page table. Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	# slide-in: hidden before its time, settled after SLIDE seconds
	_check(ComicKeys.panel_in(0.9, 1.0) == 0.0, "panel hidden before its time")
	_check(is_equal_approx(ComicKeys.panel_in(1.0 + ComicKeys.SLIDE, 1.0), 1.0), "panel settled after SLIDE")
	var mid := ComicKeys.panel_in(1.0 + ComicKeys.SLIDE * 0.5, 1.0)
	_check(mid > 0.0 and mid < 1.2, "panel half way in")
	# cover crop: the source keeps the panel aspect and stays inside the source rect
	var src := Rect2(0, 0, 1536, 864)
	var c := ComicKeys.cover(src, 1.0)
	_check(is_equal_approx(c.size.x, c.size.y) and src.encloses(c), "square panel gets a centred square crop")
	var tall := ComicKeys.cover(Rect2(100, 0, 400, 800), 2.0)
	_check(is_equal_approx(tall.size.x / tall.size.y, 2.0) and Rect2(100, 0, 400, 800).encloses(tall), "wide panel from a tall crop")
	# push-in: the crop shrinks over the panel's life, never leaves the source
	var p0 := ComicKeys.push_src(src, [0.12, 0.03, -0.02], 0.0, 8.0)
	var p1 := ComicKeys.push_src(src, [0.12, 0.03, -0.02], 8.0, 8.0)
	_check(p0.is_equal_approx(src) or src.encloses(p0), "push starts at the full crop")
	_check(p1.size.x < p0.size.x and src.encloses(p1), "push ends closer and inside the crop")
	var big := ComicKeys.push_src(src, [0.1, 5.0, 5.0], 8.0, 8.0)
	_check(src.encloses(big), "a huge drift is clamped inside the crop")
	# pop: zero before the delay, overshoot, then rest at 1
	_check(ComicKeys.pop(0.1, 0.0, 0.4) == 0.0, "balloon not shown before its delay")
	_check(is_equal_approx(ComicKeys.pop(5.0, 0.0, 0.4), 1.0), "balloon rests at full size")
	var peak := 0.0
	for i in 40:
		peak = maxf(peak, ComicKeys.pop(0.4 + i * 0.01, 0.0, 0.4))
	_check(peak > 1.0 and peak < 1.3, "balloon overshoots a little")
	# shake: zero before landing, decays to zero
	_check(ComicKeys.shake(0.5, 1.0) == Vector2.ZERO, "no shake before the panel lands")
	_check(ComicKeys.shake(1.05, 1.0).length() > 0.0, "shake right after landing")
	_check(ComicKeys.shake(1.0 + ComicKeys.SHAKE_TIME + 0.01, 1.0) == Vector2.ZERO, "shake gone after SHAKE_TIME")
	# particles: deterministic and in 0..1
	_check(ComicKeys.rand01(7, 3) == ComicKeys.rand01(7, 3), "random is deterministic")
	var inside := true
	for i in 50:
		var r := ComicKeys.rand01(i, i * 3 + 1)
		inside = inside and r >= 0.0 and r < 1.0
	_check(inside, "random stays in 0..1")
	var puff := ComicKeys.puff(Vector2(0.5, 0.8), Vector2(0.0, -0.4), 2, 3.3, 3.0)
	_check(puff.size() == 3 and float(puff[2]) >= 0.0 and float(puff[2]) <= 1.0, "puff gives position, size, alpha")
	# fly: hidden before its start, moves and grows, gone at the end
	_check(float(ComicKeys.fly(0.5, 1.0, 3.0, Vector2.ZERO, Vector2.ONE, 0.2, 1.0)[2]) == 0.0, "jet hidden before it starts")
	var fm: Array = ComicKeys.fly(2.0, 1.0, 3.0, Vector2.ZERO, Vector2.ONE, 0.2, 1.0)
	_check(float(fm[2]) > 0.9 and (fm[0] as Vector2).x > 0.4 and (fm[0] as Vector2).x < 0.6 and float(fm[1]) > 0.2, "jet halfway, visible, growing")
	_check(float(ComicKeys.fly(3.5, 1.0, 3.0, Vector2.ZERO, Vector2.ONE, 0.2, 1.0)[2]) == 0.0, "jet gone after its end")
	# clip_sprite: the part inside the panel, with the matching texture part
	var cl := ComicKeys.clip_sprite(Rect2(-50, 0, 100, 50), Rect2(0, 0, 200, 200), Vector2(200, 100))
	_check((cl[0] as Rect2).is_equal_approx(Rect2(0, 0, 50, 50)) and (cl[1] as Rect2).is_equal_approx(Rect2(100, 0, 100, 100)), "sprite cut at the panel edge")
	_check(ComicKeys.clip_sprite(Rect2(500, 0, 10, 10), Rect2(0, 0, 200, 200), Vector2(10, 10)).is_empty(), "sprite outside: nothing")
	# every page: panels inside the page, `say` lines exist in the scene, the pictures exist
	for id in StoryComic.PAGES:
		var page: Dictionary = StoryComic.PAGES[id]
		var scene := StoryComic.scene_of(id)
		_check(not scene.is_empty(), "page %s has a scene" % id)
		var lines: Array = scene.get("lines", [])
		for p in page["panels"]:
			var pd: Dictionary = p
			var r: Array = pd["rect"]
			_check(float(r[0]) >= 0.0 and float(r[1]) >= 0.0 and float(r[0]) + float(r[2]) <= 1.001 and float(r[1]) + float(r[3]) <= 1.001, "%s: panel inside the page" % id)
			_check(float(pd["t"]) < float(scene.get("dur", 0.0)), "%s: panel comes in before the scene ends" % id)
			if pd.has("say"):
				for li in ((pd["say"] as Array)[0] as Array):
					_check(int(li) < lines.size(), "%s: balloon line exists" % id)
			_check(ResourceLoader.exists(String(pd["img"])), "%s: picture %s exists" % [id, pd["img"]])
			for f in pd.get("fx", []):
				if (f as Dictionary).has("img"):
					_check(ResourceLoader.exists(String(f["img"])), "%s: cut-out %s exists" % [id, f["img"]])
	# page keys of playing scenes: the variant is told apart by its definition; the shots replay ids match too
	_check(StoryComic.key_of("intro_forts", StoryScenes.INTRO["forts.recon"]) == "intro_forts.recon", "recon variant finds its page")
	_check(StoryComic.key_of("intro_forts", StoryScenes.INTRO["forts"]) == "intro_forts", "plain scene finds its page")
	_check(StoryComic.key_of("intro_forts_recon", StoryScenes.INTRO["forts.recon"]) == "intro_forts.recon", "shots replay id finds the page")
	_check(StoryComic.key_of("epilogue_sky", StoryScenes.EPILOGUE["sky.later"]) == "epilogue_sky.later", "epilogue variant finds its page")
	_check(StoryComic.key_of("test", StoryScenes.TEST) == "", "the test scene has no page")
	for kind in [["intro", StoryScenes.INTRO], ["outro", StoryScenes.OUTRO], ["epilogue", StoryScenes.EPILOGUE]]:
		for k in (kind[1] as Dictionary):
			_check(StoryComic.PAGES.has("%s_%s" % [kind[0], k]), "every story scene has a page: %s_%s" % [kind[0], k])
	print("UNIT: comic_keys %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
