extends Node
## Working part of model_tables_test.gd: the per-model tables compile against the autoloads (Tuning, Profile through
## Livery), which exist only after the SceneTree starts.

## Files every plane model needs: battle and hangar GLB, top-down sprite, wing mechanisation, insignia stickers
const FILES := ["res://models/battle/fh_battle_%s.glb", "res://models/hangar/fh_hangar_%s.glb",
	"res://art/planes/%s.png", "res://models/mech/fh_mech_%s.glb", "res://models/mech/fh_ins_%s.glb"]

var _failed := 0
var _checks := 0


func _ready() -> void:
	var keys := PlaneTiers.model_keys()
	_check(keys.size() >= 1 and keys.has(PlaneTiers.model(1)), "model keys cover tier 1")
	for t in range(1, PlaneTiers.MODEL.size() + 1):
		_check(keys.has(PlaneTiers.model(t)), "tier %d model is listed" % t)
	for cls: String in PlaneClasses.LIST:
		for mk in keys:
			_test_plane(cls, PlaneTiers.art_key(cls, mk))
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## One plane model: its files, and a row in every table that the hangar, battle and benches look it up in
func _test_plane(cls: String, key: String) -> void:
	for f: String in FILES:
		_check(ResourceLoader.exists(f % key), "%s: %s" % [key, f % key])
	var tables := {
		"SkinPatch.FLARE_ROWS": SkinPatch.FLARE_ROWS, "PlaneDetail.SHAPE": PlaneDetail.SHAPE,
		"DecalPresets.SPOTS": DecalPresets.SPOTS, "HangarCockpit.FRAMES": HangarCockpit.FRAMES,
		"Livery.NOSE": Livery.NOSE, "Livery.SRC": Livery.SRC, "PlaneFx.SPEC": PlaneFx.SPEC,
		"VisualBench._MECHCLOSE": VisualBench._MECHCLOSE,
	}
	for name: String in tables:
		_check((tables[name] as Dictionary).has(key), "%s has %s" % [name, key])
	var spec: Dictionary = PlaneFx.SPEC.get(key, {})
	_check(spec.has("jet") or spec.has("prop"), "%s: engines in PlaneFx.SPEC" % key)
	if spec.has("jet"):
		_check(NozzleFlame.NOZZLES.has(key), "NozzleFlame.NOZZLES has jet %s" % key)
	if spec.has("prop"):
		# propellers either come as their own spinning nodes or are baked into the model and get hub blur discs
		_check(ResourceLoader.exists("res://models/mech/fh_prop_%s.glb" % key) or spec.has("hub_y"),
			"%s: propellers have nodes or hub discs" % key)
	_check((DecalPresets.SPOTS.get(key, {}) as Dictionary).size() == DecalPresets.NAMES.size(), "%s: every decal spot" % key)
	if cls == "fighter":
		# the wing-tip group of the fighter hangs its pylon stores at the measured outer station
		_check(PlaneArt.WING_PAIR.has(key) and PlaneArt.OUTER_PAIR.has(key), "%s: inner and outer wing stations" % key)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
