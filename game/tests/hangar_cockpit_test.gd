extends SceneTree
## Unit tests for the hangar glazed cockpit (HangarCockpit) and the hangar detail switch. Rules pinned here: every
## player hangar model has a canopy that HangarCockpit turns into clear glass; the GLB glass is hidden; the planes
## with a built cockpit get an interior that stays under the glass (no headrest through the canopy) and inside the
## canopy's length; «Оса» 1 keeps its own cockpit (no interior); the frame bows land on the glass; the showcase light
## is off by default (R-22) and the detail layer on. Run from the repository root: `tools/ci/unit.sh`.
## Working part — hangar_cockpit_test_run.gd (Livery and Tuning need the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/hangar_cockpit_test_run.gd").new())
