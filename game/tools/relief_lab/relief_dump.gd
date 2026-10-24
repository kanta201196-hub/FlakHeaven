extends SceneTree
## Relief lab (RV-01): float heights, rock mask and landform weights over an area, for
## before/after maps of the Нагорье relief. Run from the repository root:
##   godot --headless --path game -s res://tools/relief_lab/relief_dump.gd -- --cx=-8 --cz=-6 --w=16 --h=12 --step=20 --out=/path/h.bin [--relief0]
##   python3 game/tools/relief_lab/shade.py /path/h.bin /path/map.png "title"   (hillshade map + stats)
##   python3 game/tools/relief_lab/prov.py /path/h.bin /path/regions.png        (which landform where)
## Game frames at fixed points: --visual --pts=name:x:z:zoom,... (--relief0 for "before").
## Working part — relief_dump_run.gd: loaded here when autoloads (Tuning, Settings) exist.


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/relief_lab/relief_dump_run.gd").new())
