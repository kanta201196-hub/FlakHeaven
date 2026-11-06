class_name UserDirMigration
extends Node
## One-time move of player data after the rename «Flak Heaven - Prototype 3 (3D)» → «Flak Heaven» (Kanta 06.11,
## sortie review item 7). Godot keeps user:// in a folder named after the project, so the rename alone would start
## every tester on an empty profile. First autoload: before Tuning, Settings and Profile read anything, it copies the
## old folder into the new one when the new one has no profile yet. The old folder is left as it was (a backup;
## the project never deletes files on a player's machine). Shader caches are skipped: the engine rebuilds them.

const OLD_NAME := "Flak Heaven - Prototype 3 (3D)"
const MARK := "profile.json"            # the new folder counts as in use once this exists
const NOTE := "migrated_from.txt"       # written after a copy, says where the data came from
const SKIP_DIRS := ["shader_cache", "vulkan"]


func _init() -> void:
	var cur := OS.get_user_data_dir()
	var n := migrate(cur.get_base_dir().path_join(OLD_NAME), cur)
	if n > 0:
		print("UserDirMigration: copied %d files from «%s»" % [n, OLD_NAME])


## Copies `old_dir` into `new_dir` when `old_dir` has a profile and `new_dir` has none; returns the number of files
## copied (0 — nothing to do). Files already in `new_dir` are kept.
static func migrate(old_dir: String, new_dir: String) -> int:
	if old_dir == new_dir or not FileAccess.file_exists(old_dir.path_join(MARK)) or FileAccess.file_exists(new_dir.path_join(MARK)):
		return 0
	var n := _copy_tree(old_dir, new_dir)
	var f := FileAccess.open(new_dir.path_join(NOTE), FileAccess.WRITE)
	if f != null:
		f.store_string(old_dir + "\n")
		f.close()
	return n


static func _copy_tree(src: String, dst: String) -> int:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	if d == null:
		return 0
	var n := 0
	for f in d.get_files():
		var to := dst.path_join(f)
		if not FileAccess.file_exists(to) and DirAccess.copy_absolute(src.path_join(f), to) == OK:
			n += 1
	for sub in d.get_directories():
		if not SKIP_DIRS.has(sub):
			n += _copy_tree(src.path_join(sub), dst.path_join(sub))
	return n
