extends SceneTree
## Unit tests for `UserDirMigration` (rename to «Flak Heaven», review item 7): the old folder's profile, settings,
## logs and subfolders are copied into an empty new folder, the old folder stays, shader caches are skipped, and a
## new folder that already has a profile is never overwritten. Works in a scratch folder under user://.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	var root := OS.get_user_data_dir().path_join("udm_test")
	_rm(root)
	var old := root.path_join("old")
	var new := root.path_join("new")
	_write(old.path_join("profile.json"), "{\"parts\": 7}")
	_write(old.path_join("settings.json"), "{}")
	_write(old.path_join("logs/godot.log"), "log")
	_write(old.path_join("shader_cache/x.bin"), "cache")
	var n := UserDirMigration.migrate(old, new)
	_check(n == 3, "three files copied (profile, settings, log), got %d" % n)
	_check(_read(new.path_join("profile.json")) == "{\"parts\": 7}", "profile copied as is")
	_check(FileAccess.file_exists(new.path_join("logs/godot.log")), "subfolders copied")
	_check(not FileAccess.file_exists(new.path_join("shader_cache/x.bin")), "shader cache skipped")
	_check(FileAccess.file_exists(old.path_join("profile.json")), "old folder left in place")
	_check(FileAccess.file_exists(new.path_join(UserDirMigration.NOTE)), "note of the source written")
	# second start: the new folder has a profile — nothing is copied, a newer profile is not overwritten
	_write(new.path_join("profile.json"), "{\"parts\": 99}")
	_check(UserDirMigration.migrate(old, new) == 0, "second run copies nothing")
	_check(_read(new.path_join("profile.json")) == "{\"parts\": 99}", "new profile kept")
	# fresh install: no old folder
	_check(UserDirMigration.migrate(root.path_join("none"), root.path_join("fresh")) == 0, "no old folder — nothing to do")
	_rm(root)
	print("UNIT: user_dir_migration %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _write(path: String, s: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(s)
	f.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _rm(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
