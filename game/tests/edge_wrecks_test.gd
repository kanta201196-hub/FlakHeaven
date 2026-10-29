extends SceneTree
## Regression test: a tree or bush near a chunk edge must not stand on a burnt-out road-column vehicle that
## belongs to the neighbouring chunk. BiomeProps._clear_wrecks once knew only its own chunk's road column, so an
## orchard tree could cover a neighbour's tank. Also checks that BiomeProps.road_wrecks, the cheap query plan()
## asks about its neighbours, gives exactly the wrecks a chunk places, and reports its cost per chunk.
## Runs from tools/ci/unit.sh. Working part: edge_wrecks_test_run.gd (needs the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/edge_wrecks_test_run.gd").new())
