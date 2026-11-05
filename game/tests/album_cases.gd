extends RefCounted
## Build album (PG-11 B5): entries add once, survive save and load, a broken or old save is migrated, the first
## finds of a sortie give parts on top of the reward. The profile is a fresh instance writing to a test file,
## so a player's real profile is never touched. Loaded by `album_test.gd` after the first frame.

const TEST_PATH := "user://test_profile_album.json"

var _failed := 0
var _checks := 0
var _profile_script: GDScript = load("res://scripts/profile.gd")


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_pure()
	_test_round_trip()
	_test_old_save()
	_test_award()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	return [_checks, _failed]


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _fresh_profile() -> Node:
	var p: Node = _profile_script.new()
	p.path = TEST_PATH
	p.reset_data()
	return p


func _test_pure() -> void:
	var a := {}
	_check(AlbumBook.add(a, "syn:carousel", "fighter", 100), "first find is new")
	_check(not AlbumBook.add(a, "syn:carousel", "bomber", 200), "second find is not new")
	_check(a["syn:carousel"]["cls"] == "fighter" and int(a["syn:carousel"]["t"]) == 100, "first class and date kept")
	_check(AlbumBook.parse(null).is_empty() and AlbumBook.parse([1, 2]).is_empty(), "missing or broken album — empty")
	var bad := AlbumBook.parse({"syn:x": {"t": 5, "cls": "bomber"}, "junk": 3, "evo:y": "z"})
	_check(bad.size() == 1 and bad.has("syn:x"), "only well-formed entries survive parse")
	var all := AlbumBook.ids(["carousel", "salvo"], ["s_wheel"], ["aam"], {"aam": {"pair": {}, "reach": {}}})
	_check(all.size() == 6 and all.has("prof:aam:reach") and all.has("evo:aam") and all.has("syn:s_wheel"), "ids cover every kind (got %s)" % str(all))
	_check(AlbumBook.found(a, all) == 1, "found counts only listed ids")
	_check(AlbumBook.kind("prof:aam:reach") == "prof", "kind of an id")
	_check(AlbumBook.parts_for(3) == 3 * AlbumBook.PARTS_FIRST and AlbumBook.parts_for(-1) == 0, "parts per first find")
	var full := Modernizations.all().size()
	_check(_profile_script.new().album_ids().size() >= Cards.SYNERGIES.size() - 1 + full, "the game's album lists every synergy and modernization")


func _test_round_trip() -> void:
	var p := _fresh_profile()
	_check(p.album_add("syn:salvo", "attacker"), "profile: first find")
	_check(not p.album_add("syn:salvo", "attacker"), "profile: repeat find")
	p.album_add("evo:aam", "fighter")
	p.save()
	var q := _fresh_profile()
	q.load_profile()
	_check(q.album_has("syn:salvo") and q.album_has("evo:aam"), "album survives save and load")
	_check(String(q.data["album"]["syn:salvo"]["cls"]) == "attacker", "class survives save and load")


func _test_old_save() -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "parts": 10, "medals": {"c": {}, "cards": [], "syn": ["carousel", "chain"]}}))
	f.close()
	var p := _fresh_profile()
	p.load_profile()
	_check(p.album_has("syn:carousel") and p.album_has("syn:chain"), "old save: medal synergies migrate into the album")
	_check(int(p.data["album"]["syn:chain"]["t"]) == 0, "migrated entries carry no date")
	_check(p.parts() == 10, "migration gives no parts")


func _test_award() -> void:
	var p := _fresh_profile()
	var base := {"cls": "fighter", "outcome": "evac", "run_time": 300.0, "level": 5, "bosses": 0, "activities": 0, "parts_kept": 100}
	var a: Dictionary = p.award_run(base)
	var b2 := base.duplicate()
	b2["album_new"] = ["syn:carousel", "evo:aam"]
	var q := _fresh_profile()
	var a2: Dictionary = q.award_run(b2)
	_check(int(a2["parts_add"]) == int(a["parts_add"]) + 2 * AlbumBook.PARTS_FIRST, "two first finds add 2 × %d parts (%d vs %d)" % [AlbumBook.PARTS_FIRST, int(a2["parts_add"]), int(a["parts_add"])])
	_check(int(a2["album_parts"]) == 2 * AlbumBook.PARTS_FIRST and (a2["album_new"] as Array).size() == 2, "result screen gets the finds")
	_check(q.album_has("syn:carousel") and q.album_has("evo:aam"), "the award writes the finds into the album")
	var a3: Dictionary = q.award_run(b2)
	_check(int(a3["album_parts"]) == 0 and int(a3["parts_add"]) == int(a["parts_add"]), "the same finds next sortie give no parts")
	var b4 := b2.duplicate()
	b4["run_time"] = 10.0
	var r := _fresh_profile()
	r.award_run(b4)
	_check(not r.album_has("syn:carousel"), "a sortie with no award records nothing")
