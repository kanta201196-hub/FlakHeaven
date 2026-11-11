extends SceneTree
## Unit tests for the two launch editions (Kanta 06.11, ED-02…ED-04, ED-08). Rules pinned here: every class has the
## five Standard paints, ten pack paints and the eight meme paints, every id resolves to a real paint, the first is the
## class default and no id repeats; the pack's fifty stickers have their own atlas cells inside the atlas, apart from
## the base set; and while the pack is not shown (no bench flag) the pack stickers stay locked.
## Run from the repository root: `tools/ci/unit.sh`.
## Working part — editions_test_run.gd (Livery needs the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/editions_test_run.gd").new())
