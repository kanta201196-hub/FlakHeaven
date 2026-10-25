class_name FortArea
extends AASite
## Activity «Укрепрайон» (FA-01, Kanta 2026-10-25, spec docs/superpowers/specs/2026-10-25-fortified-area-design.md).
## A real Highland fort of the map (`o_fort`) is an enemy base: a SAM launcher on each of the four
## towers and two machine-gun jeeps in the yard. Closer than ACTIVATE_R — banner «Обнаружена база
## противника» and an optional timer. The base is taken when the four launchers are down; the jeeps
## are extra targets. The base keeps at most FortBalance.MISSILE_CAP missiles in the air (locks count).
## Built on AASite: the same targets list, `active`, timer and cleanup; GroundTarget asks `can_launch`.

var fort: Dictionary = {}
var launchers: Array[GroundTarget] = []


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


## Autotest trace of the activity (tools/ci, `--autotest --fort`).
func _log(what: String) -> void:
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: fort ", what)
