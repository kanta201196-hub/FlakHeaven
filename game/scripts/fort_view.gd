class_name FortView
extends Node3D
## 3D look of one map fort beyond its mesh (FA-03, FA-04). Render3D adds it under every o_fort MeshInstance3D.
## It dresses the yard with game models (two convoy trucks by the gate road, a stack of crates) and otherwise
## does nothing (no _process) until FortArea reports a change of that fort through Events.fort_changed. Then
## the parent draws only FortBuild.base() and this node holds one MeshInstance3D per breakable piece in its
## current state, plus fire-and-smoke columns over what burns (store, collapsed towers, blown gate, the
## citadel and the trucks once the fort is taken). Damage lives in Background.forts_hit, so a fort rebuilt
## after scrolling back in shows it again.

const TRUCK := "res://models/battle/fh_battle_e_convoy_truck.glb"
const CRATE := "res://models/battle/fh_battle_e_convoy_crate.glb"
## Trucks by the gate road (preview props): [x, z, yaw], preview units; length 9.
const TRUCKS := [[16.0, 30.0, 1.6], [24.0, 26.0, 1.75]]

var key: Vector2i
var _parts := {}   # piece id → MeshInstance3D
var _fires := {}   # fire spot id → CPUParticles3D
var _trucks: Array[Node3D] = []
var _crates: Array[Node3D] = []
var _burnt := false
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


## Fire spots of a damage state, preview units: spot id → position. A spot burns while its piece is broken;
## the trucks and the citadel burn once the fort is taken.
static func fire_spots(d: FortDamage) -> Dictionary:
	var out := {}
	if d == null:
		return out
	var s := FortBuild.S
	for i in 4:
		if d.state["t%d" % i] == FortDamage.BROKEN:
			var t: Vector2 = FortBuild.TOWERS[i] * s
			out["t%d" % i] = Vector3(t.x, 7.0, t.y)
	if d.state["gate"] == FortDamage.BROKEN:
		out["gate"] = Vector3(1.0, 0.5, s + 9.0)
	if d.state["store"] == FortDamage.BROKEN:
		out["store0"] = Vector3(29.0, 2.0, -8.0)
		out["store1"] = Vector3(31.0, 2.0, 1.0)
	if d.state["citadel"] == FortDamage.BROKEN:
		out["citadel0"] = Vector3(-10.0, 17.5, -18.0)
		out["citadel1"] = Vector3(-14.0, 12.5, -10.0)
		for i in TRUCKS.size():
			out["truck%d" % i] = Vector3(TRUCKS[i][0], 2.5, TRUCKS[i][1])
	return out


func _ready() -> void:
	_dress_yard()
	Events.fort_changed.connect(_on_changed)
	_on_changed(key)


## Yard props from the game's own convoy models, in the fort's unit space (this node sits under the scaled fort).
func _dress_yard() -> void:
	var k := FortBuild.K
	for t: Array in TRUCKS:
		var n := _prop(TRUCK, 9.0)
		if n != null:
			n.position = Vector3(t[0], 0.0, t[1]) * k
			n.rotate_y(t[2])
			_trucks.append(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 9:
		var n := _prop(CRATE, 2.6)
		if n != null:
			n.position = Vector3(-34.0 + (i % 3) * 2.9, floorf(i / 6.0) * 1.6, 18.0 + (floori(i / 3.0) % 2) * 2.2) * k
			n.rotate_y(rng.randf_range(-0.15, 0.15))
			_crates.append(n)


## One model scaled so its longer side is `len` preview units; null when the model is missing.
func _prop(path: String, len: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != n:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b := xf * (mi as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var side := maxf(box.size.x, box.size.z)
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(n)
	n.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	if side > 0.0:
		holder.scale = Vector3.ONE * (len * FortBuild.K / side)
	return holder


## Rebuilds the pieces and fires when this fort's damage moved on since the last look.
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
	_set_fires(fire_spots(d))
	if d.state["citadel"] == FortDamage.BROKEN and not _burnt:
		_burn_yard()


## Starts a fire-and-smoke column on every new spot (Render3D's wreck smoke: flames at the base, dark smoke).
func _set_fires(spots: Dictionary) -> void:
	if Render3D.I == null:
		return
	for id: String in spots:
		if _fires.has(id):
			continue
		var sm: CPUParticles3D = Render3D.I._make_smoke()
		sm.get_parent().remove_child(sm)
		sm.top_level = true
		add_child(sm)
		sm.global_position = global_transform * ((spots[id] as Vector3) * FortBuild.K)
		# a burning building is a bigger fire than a vehicle wreck: wider, denser and taller column
		var big := id.begins_with("citadel") or id.begins_with("store")
		var f := 1.8 if big else 1.3
		sm.scale_amount_min *= f
		sm.scale_amount_max *= f
		sm.amount = int(sm.amount * (1.6 if big else 1.2))
		sm.lifetime *= 1.5 if big else 1.2
		sm.initial_velocity_max *= f
		sm.emitting = true
		_fires[id] = sm


## The fort is taken: trucks and crates burn out — soot-black, trucks settled on a flat tyre, crates knocked about.
func _burn_yard() -> void:
	_burnt = true
	var mat: Material = Render3D.I._wreck_mat if Render3D.I != null else null
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for n in _trucks + _crates:
		for g in n.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).material_overlay = mat
	for t in _trucks:
		t.rotate_object_local(Vector3.BACK, 0.04)
	for c in _crates:
		c.position = Vector3(c.position.x + rng.randf_range(-3.0, 3.0) * FortBuild.K, 0.0, c.position.z + rng.randf_range(-2.0, 3.0) * FortBuild.K)
		c.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * 6.0, rng.randf_range(-0.4, 0.4))


## The sortie that broke this fort ended (its Background leaves): back to the whole fort and a quiet yard, as
## Render3D keeps its fort nodes across sorties.
func _reset() -> void:
	for id: String in _parts:
		(_parts[id] as Node).queue_free()
	_parts.clear()
	for id: String in _fires:
		(_fires[id] as Node).queue_free()
	_fires.clear()
	for n in _trucks + _crates:
		n.queue_free()
	_trucks.clear()
	_crates.clear()
	_burnt = false
	_dress_yard()
	_ver = -1
	var mi := get_parent() as MeshInstance3D
	if mi != null:
		mi.mesh = FortBuild.mesh()
