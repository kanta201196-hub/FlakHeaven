class_name FortView
extends Node3D
## 3D look of one map fort's damage (FA-03). Render3D adds it under every o_fort MeshInstance3D; it does nothing
## (no _process) until FortArea reports a change of that fort through Events.fort_changed. Then the parent
## draws only FortBuild.base() and this node holds one MeshInstance3D per breakable piece in its current
## state. Damage lives in Background.forts_hit, so a fort rebuilt after scrolling back in shows it again.

var key: Vector2i
var _parts := {}   # piece id → MeshInstance3D
var _ver := -1


func _init(pos: Vector2) -> void:
	key = key_of(pos)


## Registry key of a map fort (its chunk_object position, rounded).
static func key_of(pos: Vector2) -> Vector2i:
	return Vector2i(pos.round())


## This sortie's damage of the fort at `k`, or null when it was never hit.
static func record(k: Vector2i) -> FortDamage:
	if Main.I == null or Main.I.background == null:
		return null
	return Main.I.background.forts_hit.get(k)


func _ready() -> void:
	Events.fort_changed.connect(_on_changed)
	_on_changed(key)


## Rebuilds the pieces when this fort's damage moved on since the last look.
func _on_changed(k: Vector2i) -> void:
	if k != key:
		return
	var d := record(key)
	var mi := get_parent() as MeshInstance3D
	if d == null or not d.any() or d.ver == _ver or mi == null:
		return
	if _ver < 0:
		Main.I.background.tree_exiting.connect(_reset, CONNECT_ONE_SHOT)   # next sortie: a whole fort again
	_ver = d.ver
	mi.mesh = FortBuild.base()
	for id: String in d.state:
		var part: MeshInstance3D = _parts.get(id)
		if part == null:
			part = MeshInstance3D.new()
			add_child(part)
			_parts[id] = part
		var want := FortBuild.piece(id, int(d.state[id]))
		if part.mesh != want:
			part.mesh = want


## The sortie that broke this fort ended (its Background leaves): back to the whole fort, as Render3D keeps
## its fort nodes across sorties.
func _reset() -> void:
	for id: String in _parts:
		(_parts[id] as Node).queue_free()
	_parts.clear()
	_ver = -1
	var mi := get_parent() as MeshInstance3D
	if mi != null:
		mi.mesh = FortBuild.mesh()
