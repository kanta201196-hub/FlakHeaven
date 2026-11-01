class_name HangarHall
extends RefCounted
## Aircraft hangar behind the weapon store view (S14-12, Kanta 31.10: "a beautiful background for the weapon
## view: the plane hangar"), in place of the old room of shelves and boxes. Hangar3D builds it once (build()) and
## shows it on the «ОРУЖИЕ» tab. An arched steel hall: sealed concrete floor with joints, stains, tyre tracks
## and a hatched loading bay round the weapon, corrugated walls on steel columns, an arched roof on ribs with
## hanging lamps and clerestory windows, wide open doors onto a sunlit apron, two of the squadron's planes up on
## maintenance jacks, and the kit of a working hangar (tow tractor, tool cabinets, work stand, drums, bottles,
## extinguishers). The big surfaces use shaders/hangar_hall.gdshader, the kit the weapons' service paint
## (WeaponPaint), so the hall wears like the weapons. Nothing in it casts a shadow: the store's key light lights
## the weapon, and the hall gets soft contact shadows painted into the floor instead.
## Units: the store view's (weapon about 0.6 long ≈ 3 m), floor at FLOOR_Y.

## Floor of the store view (Hangar3D.FLOOR_Y)
const FLOOR_Y := -0.2
## Metres per view unit (the store's weapons are about 0.6 units for ~3 m)
const M_PER_UNIT := 4.8
## Hall in its own axes (the doors at +Z): x from -HALF_W to HALF_W, z from BACK_Z to DOOR_Z
const HALF_W := 7.0
const BACK_Z := -6.0
const DOOR_Z := 9.0
const DOOR_HALF := 5.4
const DOOR_TOP := 1.75   ## door opening height over the floor
const WALL_H := 1.55     ## side wall height over the floor; the arched roof rises from it
const APEX_H := 3.3      ## roof apex over the floor
const RIB_STEP := 2.0    ## steel ribs along the hall
## The hall turns so its doors lie behind the weapon in the store's default view (Hangar3D.YAW0): the camera
## looks along (-cos YAW0, -sin YAW0) in x-z
const TURN := 0.73
## Parked planes: battle model, centre (x, z) in hall axes, heading (rad, 0 = nose to the doors), length (units),
## jack points under the nose and the wings in model axes (length 1; measured under each model's skin)
const PLANES := [
	["res://models/battle/fh_battle_fighter_1.glb", Vector2(0.9, 3.7), 2.85, 3.1,
		[Vector2(0.3, 0.0), Vector2(-0.15, 0.13), Vector2(-0.15, -0.13)]],
	["res://models/battle/fh_battle_attacker_1.glb", Vector2(-3.4, 6.6), -0.35, 3.5,
		[Vector2(0.3, 0.0), Vector2(-0.05, 0.16), Vector2(-0.05, -0.16)]],
]
## The yellow taxi line runs to the doors along this x (hall axes), off the store's centre
const TAXI_X := -1.7
## Jack height under a parked plane's lowest point (units)
const JACK_LIFT := 0.12

static var _blobs: Array[Vector4] = []


## Builds the hall as one node tree (its own axes turned by TURN round the store's centre).
static func build() -> Node3D:
	_blobs.clear()
	var root := Node3D.new()
	root.name = "hangar_hall"
	root.rotation.y = TURN
	var floor_m := _surface(0)
	var wall_m := _surface(1)
	var roof_m := _surface(2)
	var apron_m := _surface(0)
	apron_m.set_shader_parameter("outside", true)
	_planes(root)
	_kit(root)
	_shell(root, wall_m, roof_m)
	# floor inside, then the apron out of the doors (the floor shader knows which by `outside`)
	_add(root, _plane_mesh(Vector2(HALF_W * 2.0, DOOR_Z - BACK_Z)), floor_m,
		Vector3(0.0, FLOOR_Y, (DOOR_Z + BACK_Z) * 0.5))
	_add(root, _plane_mesh(Vector2(70.0, 15.0)), apron_m, Vector3(0.0, FLOOR_Y - 0.002, DOOR_Z + 7.5))
	_outside(root)
	var blobs := PackedVector4Array()
	for i in 12:
		blobs.append(_blobs[i] if i < _blobs.size() else Vector4.ZERO)
	for sm: ShaderMaterial in [floor_m, apron_m]:
		sm.set_shader_parameter("blobs", blobs)
	return root


## Material of a big hall surface (hangar_hall.gdshader): 0 floor, 1 wall, 2 roof
static func _surface(part: int) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/hangar_hall.gdshader")
	sm.set_shader_parameter("part", part)
	sm.set_shader_parameter("m_per_unit", M_PER_UNIT)
	sm.set_shader_parameter("door", Vector3(0.0, DOOR_Z, DOOR_HALF))
	sm.set_shader_parameter("bay", Vector4(0.0, 0.0, 0.62, 0.46))
	sm.set_shader_parameter("taxi_x", TAXI_X)
	sm.set_shader_parameter("hall_turn", TURN)
	return sm


static func _plane_mesh(size: Vector2) -> PlaneMesh:
	var pm := PlaneMesh.new()
	pm.size = size
	return pm


## A mesh instance under `root` at `pos` (turned `rot` round Y), never casting a shadow
static func _add(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


static func _box(root: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := 0.0) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _add(root, bm, mat, pos, rot)


static func _cyl(root: Node3D, r: float, h: float, pos: Vector3, mat: Material, basis := Basis()) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 20
	var mi := _add(root, cm, mat, pos)
	mi.basis = basis
	return mi


## Weathered paint (WeaponPaint) for the hall's kit: colour `c`, an object about `size` units
static func _kit_mat(c: Color, size: float, rough := 0.8, metal := 0.1) -> Material:
	return WeaponPaint.plain(c, rough, metal, size)


## Glowing material: lamps, windows, the bright outside
static func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Remembers a soft contact shadow on the floor (hall axes: centre, radius along x and z)
static func _shadow(c: Vector2, rx: float, rz: float) -> void:
	if _blobs.size() < 12:
		_blobs.append(Vector4(c.x, c.y, rx, rz))


## Height of the roof over the floor at `x` across the hall: vertical walls up to WALL_H, then an elliptic arch
static func roof_h(x: float) -> float:
	var u := clampf(absf(x) / HALF_W, 0.0, 1.0)
	return WALL_H + (APEX_H - WALL_H) * sqrt(maxf(1.0 - u * u, 0.0))


## Walls, arched roof, ribs, lamps, windows and the door frame
static func _shell(root: Node3D, wall_m: Material, roof_m: Material) -> void:
	var len_z := DOOR_Z - BACK_Z
	var cz := (DOOR_Z + BACK_Z) * 0.5
	for sx: float in [-1.0, 1.0]:   # side walls, facing in
		var w := _box(root, Vector3(0.04, WALL_H, len_z), Vector3(sx * (HALF_W + 0.02), FLOOR_Y + WALL_H * 0.5, cz), wall_m)
		w.name = "side_wall"
	# arched roof: strips along the hall, each a flat panel between two points of the arch
	var n := 18
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var x0 := -HALF_W + HALF_W * 2.0 * i / n
		var x1 := -HALF_W + HALF_W * 2.0 * (i + 1) / n
		var y0 := FLOOR_Y + roof_h(x0)
		var y1 := FLOOR_Y + roof_h(x1)
		var a := Vector3(x0, y0, BACK_Z)
		var b := Vector3(x1, y1, BACK_Z)
		var c := Vector3(x1, y1, DOOR_Z)
		var d := Vector3(x0, y0, DOOR_Z)
		var nrm := Vector3(y1 - y0, -(x1 - x0), 0.0).normalized() * -1.0   # down and in: the underside
		if nrm.y > 0.0:
			nrm = -nrm
		st.set_normal(nrm)
		for v: Vector3 in [a, c, b, a, d, c]:
			st.add_vertex(v)
	_add(root, st.commit(), roof_m, Vector3.ZERO).name = "roof"
	# end walls: the back one closed up to the arch, the door one round the opening
	_end_wall(root, wall_m, BACK_Z, false)
	_end_wall(root, wall_m, DOOR_Z, true)
	# steel ribs: columns on the side walls and the arch over the hall
	var steel := _kit_mat(Color(0.36, 0.39, 0.4), 3.0, 0.72, 0.35)
	var z := BACK_Z + RIB_STEP * 0.5
	while z < DOOR_Z:
		for sx: float in [-1.0, 1.0]:
			_box(root, Vector3(0.09, WALL_H, 0.07), Vector3(sx * (HALF_W - 0.05), FLOOR_Y + WALL_H * 0.5, z), steel)
		for i in n:
			var x0 := -HALF_W + HALF_W * 2.0 * i / n
			var x1 := -HALF_W + HALF_W * 2.0 * (i + 1) / n
			var p0 := Vector3(x0, FLOOR_Y + roof_h(x0) - 0.06, z)
			var p1 := Vector3(x1, FLOOR_Y + roof_h(x1) - 0.06, z)
			var seg := _box(root, Vector3(p0.distance_to(p1) + 0.02, 0.1, 0.06), (p0 + p1) * 0.5, steel)
			seg.rotation.z = atan2(p1.y - p0.y, p1.x - p0.x)
		z += RIB_STEP
	# a tie beam and hanging lamps over each rib bay
	var lamp := _glow(Color(1.0, 0.93, 0.8), 2.4)
	var shade := _kit_mat(Color(0.2, 0.21, 0.22), 0.3, 0.6, 0.4)
	z = BACK_Z + RIB_STEP
	while z < DOOR_Z - 0.5:
		for lx: float in [-3.2, 0.0, 3.2]:
			var top := FLOOR_Y + roof_h(lx) - 0.05
			var y := FLOOR_Y + 2.15
			_cyl(root, 0.006, top - y, Vector3(lx, (top + y) * 0.5, z), shade)
			var cone := CylinderMesh.new()
			cone.top_radius = 0.04
			cone.bottom_radius = 0.13
			cone.height = 0.08
			cone.radial_segments = 20
			_add(root, cone, shade, Vector3(lx, y, z))
			_cyl(root, 0.11, 0.01, Vector3(lx, y - 0.042, z), lamp)
		z += RIB_STEP
	# clerestory windows along both side walls, high up between the ribs
	var glass := _glow(Color(0.78, 0.84, 0.9), 1.25)
	var frame := _kit_mat(Color(0.25, 0.27, 0.27), 1.0, 0.7, 0.3)
	z = BACK_Z + RIB_STEP
	while z < DOOR_Z - 0.5:
		for sx: float in [-1.0, 1.0]:
			_box(root, Vector3(0.01, 0.26, 1.5), Vector3(sx * (HALF_W - 0.005), FLOOR_Y + 1.18, z), glass)
			for k in 4:
				_box(root, Vector3(0.02, 0.28, 0.025), Vector3(sx * (HALF_W - 0.012), FLOOR_Y + 1.18, z - 0.75 + k * 0.5), frame)
			_box(root, Vector3(0.02, 0.025, 1.52), Vector3(sx * (HALF_W - 0.012), FLOOR_Y + 1.18, z), frame)
		z += RIB_STEP


## End wall at `z`: closed (back) or round the door opening, with the door leaves slid aside
static func _end_wall(root: Node3D, wall_m: Material, z: float, doors: bool) -> void:
	var face := -1.0 if doors else 1.0   # which side of the wall the hall is on
	var thick := 0.04
	if not doors:
		# the back wall in vertical strips up to the arch
		var n := 14
		for i in n:
			var x0 := -HALF_W + HALF_W * 2.0 * i / n
			var x1 := x0 + HALF_W * 2.0 / n
			var h := roof_h((x0 + x1) * 0.5)
			_box(root, Vector3(x1 - x0 + 0.01, h, thick), Vector3((x0 + x1) * 0.5, FLOOR_Y + h * 0.5, z - face * thick * 0.5), wall_m)
		_back_wall_kit(root, z)
		return
	# beside the opening and above it
	for sx: float in [-1.0, 1.0]:
		var w := HALF_W - DOOR_HALF
		_box(root, Vector3(w, WALL_H, thick), Vector3(sx * (DOOR_HALF + w * 0.5), FLOOR_Y + WALL_H * 0.5, z + thick * 0.5), wall_m)
	var n := 14
	for i in n:
		var x0 := -HALF_W + HALF_W * 2.0 * i / n
		var x1 := x0 + HALF_W * 2.0 / n
		var h := roof_h((x0 + x1) * 0.5)
		var y0 := DOOR_TOP if absf((x0 + x1) * 0.5) < DOOR_HALF else WALL_H
		if h > y0:
			_box(root, Vector3(x1 - x0 + 0.01, h - y0, thick), Vector3((x0 + x1) * 0.5, FLOOR_Y + (y0 + h) * 0.5, z + thick * 0.5), wall_m)
	# door header beam and the leaves stacked open at both sides, just inside the opening
	var steel := _kit_mat(Color(0.33, 0.35, 0.34), 6.0, 0.75, 0.3)
	_box(root, Vector3(DOOR_HALF * 2.0 + 0.2, 0.12, 0.12), Vector3(0.0, FLOOR_Y + DOOR_TOP + 0.06, z - 0.06), steel)
	var leaf := _kit_mat(Color(0.42, 0.45, 0.42), 1.8, 0.8, 0.25)
	for sx: float in [-1.0, 1.0]:
		for k in 2:
			var lx := sx * (DOOR_HALF + 0.05 - 0.9 - k * 0.15)
			_box(root, Vector3(1.8, DOOR_TOP - 0.02, 0.05), Vector3(lx, FLOOR_Y + DOOR_TOP * 0.5, z - 0.12 - k * 0.07), leaf)
	# the door track in the floor
	_box(root, Vector3(DOOR_HALF * 2.0 + 2.0, 0.006, 0.05), Vector3(0.0, FLOOR_Y + 0.003, z - 0.15), steel)


## Mezzanine offices with lit windows and shelving along the back wall
static func _back_wall_kit(root: Node3D, z: float) -> void:
	var block := _kit_mat(Color(0.55, 0.55, 0.5), 3.0, 0.88, 0.0)
	var rail := _kit_mat(Color(0.62, 0.5, 0.12), 3.0, 0.7, 0.2)
	var warm := _glow(Color(1.0, 0.86, 0.62), 1.1)
	var dark := _kit_mat(Color(0.16, 0.17, 0.17), 1.0, 0.7, 0.2)
	# two-storey office block in the middle of the back wall, lit windows, a railing on its roof
	_box(root, Vector3(4.2, 0.95, 0.9), Vector3(0.0, FLOOR_Y + 0.475, z + 0.45), block)
	for i in 5:
		for row in 2:
			_box(root, Vector3(0.5, 0.18, 0.01), Vector3(-1.6 + i * 0.8, FLOOR_Y + 0.25 + row * 0.42, z + 0.905), warm if (i + row) % 3 != 1 else dark)
	_box(root, Vector3(0.36, 0.38, 0.01), Vector3(1.9, FLOOR_Y + 0.19, z + 0.905), dark)   # door
	for i in 9:
		_box(root, Vector3(0.012, 0.16, 0.012), Vector3(-2.05 + i * 0.51, FLOOR_Y + 1.03, z + 0.88), rail)
	_box(root, Vector3(4.2, 0.012, 0.012), Vector3(0.0, FLOOR_Y + 1.11, z + 0.88), rail)
	# shelving with crates either side
	var shelf := _kit_mat(Color(0.3, 0.33, 0.36), 1.6, 0.6, 0.45)
	var olive := _kit_mat(Color(0.3, 0.33, 0.24), 0.4, 0.85, 0.0)
	var wood := _kit_mat(Color(0.45, 0.34, 0.21), 0.4, 0.9, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	for sx: float in [-1.0, 1.0]:
		for k in 2:
			var cx := sx * (3.6 + k * 1.7)
			for py: float in [0.0, 0.35, 0.7]:
				_box(root, Vector3(1.6, 0.03, 0.5), Vector3(cx, FLOOR_Y + py + 0.02, z + 0.3), shelf)
				var x := -0.7
				while x < 0.6:
					var w := rng.randf_range(0.2, 0.4)
					var h := rng.randf_range(0.12, 0.26)
					_box(root, Vector3(w, h, 0.4), Vector3(cx + x + w * 0.5, FLOOR_Y + py + 0.035 + h * 0.5, z + 0.3), olive if rng.randf() < 0.7 else wood)
					x += w + rng.randf_range(0.04, 0.1)
			for ex: float in [-0.78, 0.78]:
				_box(root, Vector3(0.04, 1.05, 0.5), Vector3(cx + ex, FLOOR_Y + 0.525, z + 0.3), shelf)


## Two of the squadron's planes on maintenance jacks, with contact shadows under them
static func _planes(root: Node3D) -> void:
	var jack := _kit_mat(Color(0.62, 0.5, 0.1), 0.3, 0.7, 0.2)
	for p: Array in PLANES:
		var path: String = p[0]
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		var at: Vector2 = p[1]
		var head: float = p[2]
		var ln: float = p[3]
		var inst := scene.instantiate() as Node3D
		for c in inst.find_children("*", "GeometryInstance3D", true, false):
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the model's nose is +X, length 1: turn it so heading 0 points at the doors (+Z)
		var bas := Basis(Vector3.UP, head - PI / 2.0)
		var low := WeaponModels.surface_low(scene, 0.0, 0.0)
		if is_nan(low):
			low = -0.11
		var cy := FLOOR_Y + JACK_LIFT - low * ln
		inst.transform = Transform3D(bas.scaled(Vector3.ONE * ln), Vector3(at.x, cy, at.y))
		root.add_child(inst)
		# jacks: under the nose and under each wing, a post from a tripod to the skin above
		for q: Vector2 in p[4]:
			var y := WeaponModels.surface_low(scene, q.x, q.y)
			if is_nan(y):
				continue
			var top := cy + y * ln
			var wp := Vector3(at.x, 0.0, at.y) + bas * Vector3(q.x * ln, 0.0, q.y * ln)
			_cyl(root, 0.012, top - FLOOR_Y - 0.03, Vector3(wp.x, (top + FLOOR_Y + 0.03) * 0.5, wp.z), jack)
			for k in 3:
				var a := TAU * k / 3.0
				var foot := Vector3(cos(a), 0.0, sin(a)) * 0.07
				var leg := _cyl(root, 0.006, 0.09, wp + foot * 0.5 + Vector3(0.0, FLOOR_Y + 0.035, 0.0), jack)
				leg.basis = Basis(Vector3(-sin(a), 0.0, cos(a)), 0.95)
		var fwd := bas * Vector3(1.0, 0.0, 0.0)
		_shadow(at + Vector2(fwd.x, fwd.z) * 0.05 * ln, 0.32 * ln, 0.32 * ln)


## Hangar kit on the floor: tow tractor, work stand, tool cabinets, drums, gas bottles, extinguishers, a wheel
## chock row; each with its contact shadow
static func _kit(root: Node3D) -> void:
	var yellow := _kit_mat(Color(0.66, 0.52, 0.12), 0.6, 0.78, 0.1)
	var dark := _kit_mat(Color(0.12, 0.12, 0.12), 0.2, 0.9, 0.0)
	var red := _kit_mat(Color(0.55, 0.12, 0.08), 0.3, 0.7, 0.1)
	var green := _kit_mat(Color(0.25, 0.32, 0.26), 0.5, 0.75, 0.15)
	var blue := _kit_mat(Color(0.2, 0.26, 0.34), 0.5, 0.7, 0.2)
	var steel := _kit_mat(Color(0.5, 0.52, 0.52), 0.5, 0.5, 0.6)
	# tow tractor by the fighter, low and wide, with its tow bar
	var tt := Node3D.new()
	tt.position = Vector3(3.6, FLOOR_Y, 6.0)
	tt.rotation.y = 0.5
	root.add_child(tt)
	_box(tt, Vector3(0.55, 0.12, 0.3), Vector3(0.0, 0.1, 0.0), yellow)
	_box(tt, Vector3(0.2, 0.14, 0.26), Vector3(-0.12, 0.23, 0.0), yellow)
	_box(tt, Vector3(0.12, 0.015, 0.2), Vector3(0.04, 0.2, 0.0), dark)   # seat
	for wx: float in [-0.18, 0.18]:
		for wz: float in [-0.16, 0.16]:
			_cyl(tt, 0.055, 0.05, Vector3(wx, 0.055, wz), dark, Basis(Vector3.RIGHT, PI / 2.0))
	_box(tt, Vector3(0.6, 0.02, 0.02), Vector3(0.55, 0.06, 0.0), steel)
	_shadow(Vector2(3.6, 6.0), 0.4, 0.3)
	# work stand with steps by the attacker's nose
	var ws := Node3D.new()
	ws.position = Vector3(-1.9, FLOOR_Y, 5.2)
	ws.rotation.y = -0.3
	root.add_child(ws)
	for k in 4:
		_box(ws, Vector3(0.22, 0.012, 0.09), Vector3(0.0, 0.06 + k * 0.08, -0.12 + k * 0.08), yellow)
	_box(ws, Vector3(0.24, 0.015, 0.3), Vector3(0.0, 0.36, 0.3), yellow)
	for px: float in [-0.11, 0.11]:
		_box(ws, Vector3(0.015, 0.36, 0.015), Vector3(px, 0.18, 0.43), yellow)
		_box(ws, Vector3(0.015, 0.5, 0.015), Vector3(px, 0.25, -0.15), yellow)
		_box(ws, Vector3(0.012, 0.012, 0.5), Vector3(px, 0.5, 0.2), yellow)   # hand rail
	_shadow(Vector2(-1.9, 5.3), 0.25, 0.35)
	# tool cabinets along the left wall, drums and gas bottles along the right one
	for i in 4:
		var c := green if i % 2 == 0 else blue
		var cz := -1.5 + i * 0.5
		_box(root, Vector3(0.28, 0.42, 0.42), Vector3(-HALF_W + 0.2, FLOOR_Y + 0.21, cz), c)
		for d in 4:
			_box(root, Vector3(0.005, 0.012, 0.3), Vector3(-HALF_W + 0.343, FLOOR_Y + 0.08 + d * 0.09, cz), steel)
	_shadow(Vector2(-HALF_W + 0.2, -0.75), 0.3, 1.1)
	for i in 5:
		var dz := 1.0 + i * 0.27 + (0.04 if i % 2 == 0 else 0.0)
		_cyl(root, 0.12, 0.36, Vector3(HALF_W - 0.25, FLOOR_Y + 0.18, dz), blue if i != 2 else red)
	_shadow(Vector2(HALF_W - 0.25, 1.55), 0.3, 0.8)
	for i in 3:
		_cyl(root, 0.045, 0.34, Vector3(HALF_W - 0.22, FLOOR_Y + 0.17, -1.4 + i * 0.11), green)
		_cyl(root, 0.02, 0.03, Vector3(HALF_W - 0.22, FLOOR_Y + 0.355, -1.4 + i * 0.11), steel)
	# extinguishers at the column feet, on their stands
	for e: Vector2 in [Vector2(-HALF_W + 0.18, 3.0), Vector2(HALF_W - 0.18, 5.0), Vector2(-HALF_W + 0.18, -3.0)]:
		_cyl(root, 0.035, 0.16, Vector3(e.x, FLOOR_Y + 0.1, e.y), red)
		_box(root, Vector3(0.1, 0.02, 0.1), Vector3(e.x, FLOOR_Y + 0.01, e.y), dark)
	# wheel chocks in a row by the door
	for i in 6:
		_box(root, Vector3(0.1, 0.05, 0.06), Vector3(-4.6 + i * 0.14, FLOOR_Y + 0.025, DOOR_Z - 0.6), yellow)


## Daylight beyond the doors: a distant tree line and hazy sky on a backdrop far out on the apron
static func _outside(root: Node3D) -> void:
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = OUTSIDE_SHADER
	sm.shader = sh
	var q := QuadMesh.new()
	q.size = Vector2(80.0, 14.0)
	var mi := _add(root, q, sm, Vector3(0.0, FLOOR_Y + 7.0 - 0.4, DOOR_Z + 14.0))   # inside the camera's far 30
	mi.rotation.y = PI   # the quad faces -Z, into the hall


## Sky and tree line of the backdrop: haze at the horizon to soft blue above, a low dark-green tree line with
## a ragged top; bright (HDR) so it reads as daylight through the doors, no fog
const OUTSIDE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
#include "res://shaders/srgb.gdshaderinc"
float h1(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h1(i), h1(i + 1.0), f); }
void fragment() {
	vec2 p = UV;
	float y = 1.0 - p.y;   // 0 bottom, 1 top
	vec3 haze = SRGB(vec3(0.86, 0.88, 0.88));
	vec3 sky = SRGB(vec3(0.52, 0.66, 0.82));
	vec3 c = mix(haze, sky, smoothstep(0.08, 0.7, y));
	float x = p.x * 80.0;
	float tree = 0.035 + 0.025 * n1(x * 0.35) + 0.012 * n1(x * 2.1) + 0.006 * n1(x * 7.0);
	float t = 1.0 - smoothstep(tree - 0.002, tree + 0.002, y);
	vec3 tc = mix(SRGB(vec3(0.42, 0.47, 0.44)), SRGB(vec3(0.55, 0.6, 0.6)), 0.5 + 0.5 * n1(x * 0.8));
	c = mix(c, tc, t);
	ALBEDO = c * 1.9;
}
"""
