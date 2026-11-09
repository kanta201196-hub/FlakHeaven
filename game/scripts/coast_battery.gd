class_name CoastBattery
extends AASite
## Activity «Береговая батарея» (B2-A01, Kanta 2026-11-08, plan docs/superpowers/plans/2026-11-08-coastal-battery.md).
## The Archipelago's ground target in the slot «Укрепрайон» takes in the Highlands (no forts at sea): four coastal
## guns stand apart on capes and islets along the strait, 300–600 px from each other. Closer than ACTIVATE_R — banner
## and timer; each gun turns its turret after the plane and fires slow heavy flak: the shell aims where the plane will
## be in RING_T s, a ring on the ground shows the spot, then the burst. At most RING_CAP rings at once for the whole
## battery. All four down within the timer — reward like the fort. A destroyed gun leaves the scenery's broken site.
## Built on AASite: the same targets list, `active`, timer and cleanup; GroundTarget "coast_gun" asks `fire`.

## Shells on the ground: {"p": burst point, "t": seconds left}
var shells: Array[Dictionary] = []
var _t := 0.0
static var _wreck_scene: PackedScene


## Up to GUNS spots from shore candidates `cands` (world px, already checked: land near the water, level, not in a
## village) round `center`: the first is the candidate nearest the centre, each next one at least GAP_MIN from every
## gun so far and within GAP_MAX of one of them, nearest the centre first. Several first guns are tried; none gives
## a full battery — empty (the spawner tries elsewhere or skips the slot).
static func pick(cands: PackedVector2Array, center: Vector2) -> PackedVector2Array:
	var order := Array(cands)
	order = order.filter(func(q: Vector2) -> bool: return q.distance_to(center) <= BatteryBalance.SEARCH_R)
	order.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(center) < b.distance_squared_to(center))
	for s in mini(order.size(), 8):
		var got := PackedVector2Array([order[s]])
		while got.size() < BatteryBalance.GUNS:
			var next := Vector2.INF
			for q: Vector2 in order:
				var near := INF
				for g in got:
					near = minf(near, q.distance_to(g))
				if near >= BatteryBalance.GAP_MIN and near <= BatteryBalance.GAP_MAX:
					next = q
					break   # order is nearest-the-centre first
			if next == Vector2.INF:
				break
			got.append(next)
		if got.size() == BatteryBalance.GUNS:
			return got
	return PackedVector2Array()


## Shore candidates round `center` on terrain `tr`: land SHORE_MIN–SHORE_MAX px from the water, a level pad, not in a
## chunk whose scenery composition fills the shore (harbour houses, lighthouse cape, scenery battery, beach defences).
static func candidates(tr: Terrain3D, center: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r := BatteryBalance.SEARCH_R
	var n := int(r / BatteryBalance.GRID)
	for ix in range(-n, n + 1):
		for iy in range(-n, n + 1):
			var q := center + Vector2(ix, iy) * BatteryBalance.GRID
			if q.distance_to(center) > r:
				continue
			var s := absf(tr.river_field(q.x, q.y)) - Terrain3D.SEA_W
			if s < BatteryBalance.SHORE_MIN or s > BatteryBalance.SHORE_MAX:
				continue
			var key := Vector2i(floori(q.x / Terrain3D.CHUNK), floori(q.y / Terrain3D.CHUNK))
			if SeaProps.comp_of(key) not in ["", "reef"]:
				continue
			if level(tr, q):
				out.append(q)
	return out


## The gun's pad is level: four points PAD_R round `q` within PAD_TOL px of its height.
static func level(tr: Terrain3D, q: Vector2) -> bool:
	var h := tr.height_drawn(q.x, q.y)
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var e := q + d * BatteryBalance.PAD_R
		if absf(tr.height_drawn(e.x, e.y) - h) > BatteryBalance.PAD_TOL:
			return false
	return true


## Direction from `q` to the nearest water among 12 (the gun faces the sea, the pit's rear entrance inland).
static func sea_dir(tr: Terrain3D, q: Vector2) -> Vector2:
	var best := INF
	var face := Vector2.RIGHT
	for i in 12:
		var d := Vector2.from_angle(TAU * i / 12.0)
		for k in range(1, 12):
			var p := q + d * k * 30.0
			if absf(tr.river_field(p.x, p.y)) < Terrain3D.SEA_W:
				if k < best:
					best = k
					face = d
				break
	return face


## May the battery put one more ring on the ground (`rings` are there now)?
static func can_fire(rings: int) -> bool:
	return rings < BatteryBalance.RING_CAP


## Where a plane at `pos` flying `vel` will be after `t` s (the shell's aim).
static func lead(pos: Vector2, vel: Vector2, t: float) -> Vector2:
	return pos + vel * t


## A burst at `at` hits a plane at `pos` with hitbox `radius`.
static func hits(at: Vector2, pos: Vector2, radius: float) -> bool:
	return at.distance_to(pos) < BatteryBalance.BURST_R + radius


## Builds the battery on `spots` (from `pick`): one fixed "coast_gun" each, facing the sea from its spot.
func setup_guns(spots: PackedVector2Array, hp_mult: float, dps := 0.0) -> void:
	var c := Vector2.ZERO
	for q in spots:
		c += q
	anchor = c / float(spots.size())
	global_position = anchor
	timer = BatteryBalance.LIMIT
	var tr := Terrain3D.active()
	for q in spots:
		var g := GroundTarget.new()
		g.fixed = true
		g.setup("coast_gun", self, hp_mult, dps)
		g.position = q
		g.face = (sea_dir(tr, q) if tr != null else (q - anchor).normalized()).angle()
		targets.append(g)


func _ready() -> void:
	super()
	z_index = 2   # the rings lie over the 3D ground and its props (AASite's -3 hid them)


func who() -> String:
	return BatteryBalance.WHO


## Gun `g` fires if the battery has a free ring: the shell lands where the plane will be in RING_T s.
func fire(g: GroundTarget) -> bool:
	var p := Main.I.player
	if p == null or not can_fire(shells.size()):
		return false
	shells.append({"p": lead(p.global_position, p.velocity, BatteryBalance.RING_T), "t": BatteryBalance.RING_T})
	Main.I.sfx.play("explode_big", -12.0, 0.55, g.global_position)
	_log("%s fired, %d rings" % [g.name, shells.size()])
	return true


## Guns still up.
func guns_left() -> int:
	return left()


## Live gun nearest to `p` (the HUD arrow leads to it once the alarm is on); null when none.
func nearest_gun(p: Vector2) -> GroundTarget:
	var best: GroundTarget = null
	var bd := INF
	for g in targets:
		if is_instance_valid(g) and g.hp > 0.0 and (g as Node2D).global_position.distance_to(p) < bd:
			bd = (g as Node2D).global_position.distance_to(p)
			best = g
	return best


func on_target_destroyed(g: GroundTarget) -> void:
	_wreck(g)
	var n := 0
	for t in targets:
		if is_instance_valid(t) and t != g and t.hp > 0.0:
			n += 1
	_log("gun down, guns left %d, %.0f s on the timer" % [n, timer])
	if n == 0 and not done:
		done = true
		if not failed:
			Events.activity_succeeded.emit(&"battery")
		if Main.I.spawner != null and Main.I.spawner.activity_node == self:
			Main.I.spawner.activity_node = null


## The broken site stands where gun `g` fell, at its 3D unit's transform, for the rest of the sortie.
func _wreck(g: GroundTarget) -> void:
	var r := Render3D.I
	if r == null or not Render3D.enabled:
		return
	var u := r.debug_unit(g.get_instance_id())
	if u == null or u.node == null:
		return
	if _wreck_scene == null:
		_wreck_scene = load(BatteryBalance.WRECK)
	var root := Node3D.new()
	var inst := _wreck_scene.instantiate() as Node3D
	var inner := (u.node as Node3D).get_child(0) as Node3D
	inst.transform = inner.transform
	root.add_child(inst)
	r.add_child(root)
	root.global_transform = (u.node as Node3D).global_transform


func _process(delta: float) -> void:
	_t += delta
	global_position = GroundTarget.air_pos(anchor)
	var p := Main.I.player
	_tick_shells(delta, p)
	if p == null:
		return
	if not active and p.global_position.distance_to(global_position) < BatteryBalance.ACTIVATE_R:
		active = true
		_log("alarm at %.0f px" % p.global_position.distance_to(global_position))
		Events.banner.emit(Loc.t("Береговая батарея открыла огонь! %d с на четыре орудия") % int(BatteryBalance.LIMIT), 3.5)
		Main.I.sfx.play("aa_alert", -2.0, 0.6)
	if active and not failed and not done:
		timer -= delta
		if timer <= 0.0:
			failed = true
			_log("failed, guns left %d" % left())
			Events.banner.emit(Loc.t("Батарея устояла — награды не будет"), 3.0)
	if (failed or done) and shells.is_empty() and p.global_position.distance_to(global_position) > BatteryBalance.CLEAR_R:
		for g in targets:
			if is_instance_valid(g):
				g.queue_free()
		queue_free()
		return
	queue_redraw()


## Rings count down; at zero the shell bursts in the air over the ring and hurts the plane inside it.
func _tick_shells(delta: float, p: Player) -> void:
	for i in range(shells.size() - 1, -1, -1):
		var sh: Dictionary = shells[i]
		sh["t"] = float(sh["t"]) - delta
		if float(sh["t"]) > 0.0:
			continue
		var q: Vector2 = sh["p"]
		if Main.I.fx != null:
			Main.I.fx.explosion(q, BatteryBalance.BURST_R * 0.45, true, true, "flak")
		Main.I.sfx.play("explode_big", -7.0, 0.9, q)
		if p != null and p.hp > 0.0 and hits(q, p.global_position, p.radius):
			Main.I.projectiles._hit_player(p, BatteryBalance.SHELL_DMG, "пули", kind_name(), "береговое орудие")
			Main.I.add_shake(5.0)
		shells.remove_at(i)


## Name of the battery for the damage stats (who hit the player).
func kind_name() -> String:
	return BatteryBalance.WHO


func _draw() -> void:
	if not active and not done:
		draw_arc(Vector2.ZERO, BatteryBalance.ACTIVATE_R, 0.0, TAU, 96, Color(1.0, 0.85, 0.3, 0.12), 2.0)
	# rings in world space: the node follows the camera projection of the centre
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	var r := BatteryBalance.BURST_R
	for sh in shells:
		var k := clampf(1.0 - float(sh["t"]) / BatteryBalance.RING_T, 0.0, 1.0)
		var q: Vector2 = sh["p"]
		draw_circle(q, r, Color(1.0, 0.3, 0.1, 0.05 + 0.13 * k))
		draw_arc(q, r, 0.0, TAU, 40, Color(1.0, 0.4, 0.15, 0.7), 3.0)
		draw_arc(q, r * k, 0.0, TAU, 40, Color(1.0, 0.65, 0.2, 0.85), 2.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Autotest trace of the activity (tools/ci, `--autotest --battery`).
func _log(what: String) -> void:
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: battery ", what)
