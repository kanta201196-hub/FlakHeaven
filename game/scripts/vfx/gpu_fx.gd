class_name GpuFx
extends Node3D
## GPU effect particles (VFX-01, plan docs/superpowers/plans/2026-10-24-combat-vfx.md). Boom3D keeps building
## explosions with the same recipes; every particle of a GPU layer goes here instead of the CPU arrays, so the
## per-frame CPU work of smoke, fire, sparks, flashes and shells disappears. Debris, burning spots and lights
## stay on the CPU for now (few, and they need the terrain height). Forward+ only: `emit_particle` does not
## exist in Compatibility, where Boom3D keeps its CPU path.

## Boom3D layers simulated on the GPU (L_SMOKE, L_FIRE, L_CORE, L_SPARK, L_SHOCK, L_FLASH)
const LAYERS := [0, 1, 2, 4, 5, 6]

## Slots per GPU layer = Boom3D.CAP x SLOTS. A full GPU layer drops the newest particle (emits only take free
## slots), while the CPU path drops the oldest; spare slots keep a fresh explosion whole in a crowded fight.
const SLOTS := 2

var _layers := {}
## Same layers as a typed list, so per-frame loops do not build an Array from the dictionary
var _list: Array[FxLayer] = []


## True when the GPU path can run: Forward+ renderer and no `--oldfx` (CPU path forced for comparisons)
static func active() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus" \
		and not OS.get_cmdline_user_args().has("--oldfx")


## Creates one FxLayer per GPU layer with Boom3D's meshes, draw materials and slot counts
func build(meshes: Array, mats: Array, caps: Array) -> void:
	for L in LAYERS:
		var fl := FxLayer.new()
		fl.setup(L, caps[L] * SLOTS, meshes[L], mats[L])
		add_child(fl)
		_layers[L] = fl
		_list.append(fl)


## True if this Boom3D layer is drawn on the GPU
func has_layer(L: int) -> bool:
	return _layers.has(L)


## Emits one Boom3D particle record into its GPU layer
func emit(L: int, q: Dictionary) -> void:
	(_layers[L] as FxLayer).emit(q)


## Per frame: game time step (0 when paused) and camera forward for velocity-aligned sparks
func tick(dt: float, cam_f: Vector3) -> void:
	for fl in _list:
		fl.tick(dt, cam_f)


## Estimated GPU particles alive, all layers
func alive() -> int:
	var n := 0
	for fl in _list:
		n += fl.alive()
	return n


## Estimated particles alive per Boom3D layer (0 for CPU layers), for the perf log
func counts() -> Array:
	var pc := [0, 0, 0, 0, 0, 0, 0]
	for fl in _list:
		pc[fl.layer] = fl.alive()
	return pc
