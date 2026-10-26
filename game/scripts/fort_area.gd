class_name FortArea
extends AASite
## Activity «Укрепрайон» (FA-01, Kanta 2026-10-25, spec docs/superpowers/specs/2026-10-25-fortified-area-design.md).
## A real Highland fort of the map (`o_fort`) is an enemy base: a SAM launcher on each of the four
## towers and two machine-gun jeeps in the yard. Closer than ACTIVATE_R — banner «Обнаружена база
## противника» and an optional timer. The base is taken when the four launchers are down; the jeeps
## are extra targets. The base keeps at most FortBalance.MISSILE_CAP missiles in the air (locks count).
## Built on AASite: the same targets list, `active`, timer and cleanup; GroundTarget asks `can_launch`.
## FA-03: the fort is conditionally destructible — player blasts breach walls, blow the gate and burn the store,
## tower crowns follow their launcher's HP (FortDamage); the damage outlives this node for the whole sortie.

var fort: Dictionary = {}
var launchers: Array[GroundTarget] = []
var damage: FortDamage
var _key: Vector2i


## Nearest map fort to `want` within `reach` among chunk objects `objs` (Background.chunk_object
## dictionaries); `{}` when there is none.
static func pick_fort(objs: Array, want: Vector2, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := reach
	for o: Dictionary in objs:
		if o.get("name", "") != "o_fort":
			continue
		var d: float = (o["pos"] as Vector2).distance_to(want)
		if d <= best_d:
			best_d = d
			best = o
	return best


## Map forts around `want` (chunks that may hold one within `reach`), as Background places them.
## Positions match the 3D fort only once Render3D has set `bg.place_filter` (river push, Terrain3D.fix_object).
static func forts_near(bg: Background, want: Vector2, reach: float) -> Array:
	var out := []
	if bg == null:
		return out
	var ch := Background.CHUNK
	var r := int(ceil(reach / ch)) + 1
	var c := Vector2i(floori(want.x / ch), floori(want.y / ch))
	for cx in range(c.x - r, c.x + r + 1):
		for cy in range(c.y - r, c.y + r + 1):
			var o := bg.chunk_object(cx, cy)
			if not o.is_empty() and o["name"] == "o_fort":
				out.append(o)
	return out


## Unit-mesh point of the fort (FortBuild.mesh, gate in +z) to world px, the way Render3D draws it:
## scaled by size, turned by rot.
static func fort_point(f: Dictionary, unit: Vector2) -> Vector2:
	return (f["pos"] as Vector2) + unit.rotated(float(f["rot"])) * float(f["size"])


## World px point `p` to the fort's unit-mesh space: the inverse of fort_point.
static func to_unit(f: Dictionary, p: Vector2) -> Vector2:
	return (p - (f["pos"] as Vector2)).rotated(-float(f["rot"])) / float(f["size"])


## The four tower pads (round corner towers of FortBuild): (-,-), (+,-), (-,+), (+,+) in unit-mesh order.
static func tower_points(f: Dictionary) -> PackedVector2Array:
	var k := FortBuild.TOWER_C
	var out := PackedVector2Array()
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		out.append(fort_point(f, s * k))
	return out


## Two jeep spots in the yard (FortBuild.YARD): by the citadel's door and by the gate road.
static func yard_points(f: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q: Vector2 in FortBuild.YARD:
		out.append(fort_point(f, q))
	return out


## A launcher may start a lock while missiles in the air plus locks in progress stay under the cap.
static func can_lock(in_air: int, locking: int, cap: int) -> bool:
	return in_air + locking < cap


## Builds the base on map fort `f`: four fixed launchers on the towers, two jeeps in the yard.
func setup_fort(f: Dictionary, hp_mult: float, dps := 0.0) -> void:
	fort = f
	anchor = f["pos"]
	global_position = anchor
	timer = FortBalance.LIMIT
	_key = FortView.key_of(f["pos"])
	var bg: Background = Main.I.background if Main.I != null else null
	damage = bg.forts_hit.get(_key) if bg != null else null
	if damage == null:
		damage = FortDamage.new()
		if bg != null:
			bg.forts_hit[_key] = damage
	Events.player_blast.connect(_on_blast)
	var tops := tower_points(f)
	for i in tops.size():
		var g := GroundTarget.new()
		g.fixed = true
		g.mount_h = float(f["size"]) * FortBuild.TOWER_TOP
		g.setup("sam", self, hp_mult, dps)
		g.position = tops[i]
		launchers.append(g)
		targets.append(g)
	for q in yard_points(f):
		var j := GroundTarget.new()
		j.fixed = true
		j.setup("jeep", self, hp_mult, dps)
		j.position = q
		targets.append(j)


## Missile `who` of the base's launchers.
func who() -> String:
	return FortBalance.WHO


## The base-wide cap (Kanta 2026-10-25): own missiles in the air + launchers locking now.
func can_launch(_g: GroundTarget) -> bool:
	var in_air := 0
	if Main.I != null and Main.I.projectiles != null:
		for m: Dictionary in Main.I.projectiles.missiles:
			if m.get("who", "") == FortBalance.WHO:
				in_air += 1
	var locking := 0
	for g in launchers:
		if is_instance_valid(g) and g.hp > 0.0 and g.locking():
			locking += 1
	return can_lock(in_air, locking, FortBalance.MISSILE_CAP)


## Launchers still up.
func launchers_left() -> int:
	var n := 0
	for g in launchers:
		if is_instance_valid(g) and g.hp > 0.0:
			n += 1
	return n


func on_target_destroyed(g: GroundTarget) -> void:
	_log("%s down, launchers left %d, %.0f s on the timer" % [g.variant, launchers_left(), timer])
	if g.variant == "sam" and not done and launchers_left() == 0:   # g is already at 0 hp here
		done = true
		if damage.take():   # FA-04: the citadel goes up, trucks burn
			Events.fort_changed.emit(_key)
		for t in targets:
			if is_instance_valid(t) and t != g:
				(t as GroundTarget).leaderless = true   # the yard jeeps stop shooting
		if not failed:
			Events.activity_succeeded.emit(&"fort")
		if Main.I.spawner != null and Main.I.spawner.activity_node == self:
			Main.I.spawner.activity_node = null
		return
	_check_done.call_deferred()


func _process(delta: float) -> void:
	global_position = GroundTarget.air_pos(anchor)
	_track_towers()
	var p := Main.I.player
	if p == null:
		return
	if not active and p.global_position.distance_to(global_position) < FortBalance.ACTIVATE_R:
		active = true
		_log("alarm at %.0f px" % p.global_position.distance_to(global_position))
		Events.banner.emit(Loc.t("Обнаружена база противника! %d с на пусковые") % int(FortBalance.LIMIT), 3.5)
		Main.I.sfx.play("aa_alert", -2.0, 0.6)
	if active and not failed and not done:
		timer -= delta
		if timer <= 0.0:
			failed = true
			_log("failed, launchers left %d" % launchers_left())
			Events.banner.emit(Loc.t("База противника устояла — награды не будет"), 3.0)
	if (failed or done) and p.global_position.distance_to(global_position) > FortBalance.CLEAR_R:
		for g in targets:
			if is_instance_valid(g):
				g.queue_free()
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if not active and not done:
		draw_arc(Vector2.ZERO, FortBalance.ACTIVATE_R, 0.0, TAU, 96, Color(1.0, 0.85, 0.3, 0.12), 2.0)


## A player blast near the fort: to ground, to unit space, into FortDamage; broken pieces get dust and smoke.
## `r` — the blast's real radius (reach), `r_base` — before the player's radius upgrades (hit weight).
func _on_blast(pos: Vector2, r: float, r_base: float) -> void:
	var c: Vector2 = fort["pos"]
	var size := float(fort["size"])
	var g := GroundTarget.ground_of(pos, c)
	if g.distance_to(c) > size * 0.75 + r:
		return
	var gr := GroundTarget.ground_of(pos + Vector2(r, 0.0), c).distance_to(g)
	var got := damage.apply_blast(to_unit(fort, g), gr / size, FortDamage.hit_weight(r_base))
	for id in got:
		break_fx(id)
	if not got.is_empty():
		Events.fort_changed.emit(_key)


## Tower crowns follow their launchers: half HP — damaged, destroyed (or gone) — collapsed.
func _track_towers() -> void:
	var changed := false
	for i in launchers.size():
		var g := launchers[i]
		var frac := g.hp / g.max_hp if is_instance_valid(g) and g.hp > 0.0 else 0.0
		if damage.set_tower(i, frac):
			break_fx("t%d" % i)
			changed = true
	if changed:
		Events.fort_changed.emit(_key)


## Unit-mesh centre and effect height (preview units) of a breakable piece (FortDamage ids).
static func piece_spot(id: String) -> Vector3:
	var k := FortBuild.K
	if id.begins_with("t"):
		var t: Vector2 = FortBuild.TOWERS[int(id.substr(1))] * FortBuild.S * k
		return Vector3(t.x, FortBuild.TOWER_H * 0.7, t.y)
	if id == "gate":
		return Vector3(FortBuild.GATE_C.x * k, 10.0, FortBuild.GATE_C.y * k)
	if id == "store":
		return Vector3(FortBuild.STORE_C.x * k, 3.0, FortBuild.STORE_C.y * k)
	if id == "citadel":
		return Vector3(-8.0 * k, 12.0, -16.0 * k)
	for w: Array in FortBuild.WALLS:
		if w[0] == id:
			var m: Vector2 = ((w[1] as Vector2) + (w[2] as Vector2)) * 0.5 * k
			return Vector3(m.x, FortBuild.WH * 0.6, m.y)
	return Vector3.ZERO


## Dust and debris burst with a scorch where a piece broke, then black smoke rising off it.
func break_fx(id: String) -> void:
	_log("%s -> %d" % [id, int(damage.state[id])])
	if Main.I == null or Main.I.fx == null:
		return
	var sp := piece_spot(id)
	var size := float(fort["size"])
	var at := GroundTarget.air_pos(fort_point(fort, Vector2(sp.x, sp.z)), sp.y * FortBuild.K * size)
	var big: bool = id.begins_with("t") and damage.state[id] == FortDamage.BROKEN
	Main.I.fx.explosion(at, size * (0.07 if big else 0.05), false, true, "ground")
	if Boom3D.active():
		for i in (4 if big else 2):
			Boom3D.ensure().black_smoke(at + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * size * 0.03, size * 0.05)


## Autotest trace of the activity (tools/ci, `--autotest --fort`).
func _log(what: String) -> void:
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: fort ", what)
