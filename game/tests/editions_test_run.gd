extends Node
## Working part of editions_test.gd: Livery compiles against the Profile autoload, which exists only after the
## SceneTree starts.

var _failed := 0
var _checks := 0


func _ready() -> void:
	for cls in ["fighter", "attacker", "bomber"]:
		var l: Array = Livery.edition_list(cls)
		var want: int = (Livery.EDITION_BASE[cls] as Array).size() + (Livery.EDITION_PACK[cls] as Array).size() \
				+ Livery.EDITION_MEMES.size()
		_check((Livery.EDITION_BASE[cls] as Array).size() == 5, "%s: five Standard paints" % cls)
		_check((Livery.EDITION_PACK[cls] as Array).size() == 10, "%s: ten pack paints" % cls)
		_check(l.size() == want, "%s: every edition id resolves (%d of %d)" % [cls, l.size(), want])
		_check(String(l[0][0]) == String(Livery.VARIANTS[cls][0][0]), "%s: the class default comes first" % cls)
		var seen := {}
		for v: Array in l:
			_check(not seen.has(v[0]), "%s: %s listed once" % [cls, v[0]])
			seen[v[0]] = true
	_check(Livery.EDITION_MEMES.size() == 8, "eight meme paints")
	for v: Array in Livery.EDITION_NEW:
		_check(v.size() == 11 and int(v[7]) == 7, "%s is a pattern-7 paint with params" % v[0])
	_check(DecalCatalog.PACK_IMAGES.size() == 50, "fifty pack stickers")
	var cells := {}
	for id: String in DecalCatalog.IMAGES:
		cells[int(DecalCatalog.IMAGES[id][0])] = id
	for id: String in DecalCatalog.PACK_IMAGES:
		var c := int(DecalCatalog.PACK_IMAGES[id][0])
		_check(not DecalCatalog.IMAGES.has(id), "%s is not in the base set" % id)
		_check(not cells.has(c), "%s has its own cell %d" % [id, c])
		_check(c < DecalCatalog.ATLAS_COLS * DecalCatalog.ATLAS_ROWS, "%s lies inside the atlas" % id)
		_check(DecalCatalog.has_image(id) and DecalCatalog.aspect(id) == 1.0, "%s resolves" % id)
		cells[c] = id
	_check(not DecalCatalog.pack_shown(), "the pack is hidden without the bench flag")
	_check(not DecalUnlocks.is_open("capybara", "fighter", {}, 99), "a pack sticker is locked while the pack is hidden")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
