class_name FortDamage
extends RefCounted
## Conditional destructibility of one «Укрепрайон» fort (FA-03, spec 2026-10-25-fortified-area-design.md,
## «Conditional destructibility»). The fort is not a physics object: it is split into pieces with hidden
## pools, and each piece swaps to a broken model when its pool runs out. Player explosions hit walls, gate
## and store; tower crowns follow their launcher's HP. Bullets never reach here (only blasts do), so walls
## do not chip under gun fire. States never go back: the fort stays broken for the rest of the sortie.
## Pure logic in the fort's unit-mesh space (FortBuild.mesh, wall line ±0.42); FortArea converts the
## blast and plays the effects, FortView shows the pieces.

enum { INTACT, DAMAGED, BROKEN }

## Piece id → INTACT / DAMAGED / BROKEN. Ids: t0..t3 (towers, FortBuild order), w0..w7 (FortBuild.WALLS),
## gate, store.
var state := {}
## Piece id → explosive hits still to take (bomb = 1, FortDamage.hit_weight).
var pool := {}
## Bumps on every change, so a view can tell its pieces are stale.
var ver := 0


func _init() -> void:
	for i in 4:
		state["t%d" % i] = INTACT
	for w: Array in FortBuild.WALLS:
		state[w[0]] = INTACT
		pool[w[0]] = FortBalance.WALL_POOL
	state["gate"] = INTACT
	pool["gate"] = FortBalance.GATE_POOL
	state["store"] = INTACT


## Weight of one player explosion of base radius `r_px` (before radius upgrades) against a piece's pool: its
## share of a bomb's radius, capped, so upgrades do not change how many hits a wall takes.
static func hit_weight(r_px: float) -> float:
	return clampf(r_px / FortBalance.BOMB_R, 0.0, FortBalance.HIT_CAP)


## A blast at `p` (unit space) of radius `r` (unit) and weight `w` (hit_weight) lands on every wall section,
## the gate and the store it reaches. Returns the ids that changed state.
func apply_blast(p: Vector2, r: float, w: float) -> Array[String]:
	var out: Array[String] = []
	var k := FortBuild.K
	var half_t := FortBuild.WT * 0.5 * k
	for wall: Array in FortBuild.WALLS:
		var id: String = wall[0]
		if state[id] != INTACT:
			continue
		var c := Geometry2D.get_closest_point_to_segment(p, (wall[1] as Vector2) * k, (wall[2] as Vector2) * k)
		if c.distance_to(p) <= r + half_t and _drain(id, w):
			out.append(id)
	if state["gate"] == INTACT and p.distance_to(FortBuild.GATE_C * k) <= r + FortBuild.GATE_R * k and _drain("gate", w):
		out.append("gate")
	if state["store"] == INTACT and w > 0.0:
		var h := FortBuild.STORE_H * k
		var d := ((p - FortBuild.STORE_C * k).abs() - h).max(Vector2.ZERO)
		if d.length() <= r:
			state["store"] = BROKEN   # fuel: any explosive hit sets it off
			out.append("store")
	if not out.is_empty():
		ver += 1
	return out


## Tower `i` follows its launcher's HP share `hp_frac`: at half it is damaged, at zero the crown collapses.
## Returns true when the state changed.
func set_tower(i: int, hp_frac: float) -> bool:
	var id := "t%d" % i
	var want := BROKEN if hp_frac <= 0.0 else (DAMAGED if hp_frac <= FortBalance.TOWER_DAMAGED else INTACT)
	if want <= int(state[id]):
		return false
	state[id] = want
	ver += 1
	return true


## Is anything broken yet (a view keeps the single intact mesh until then).
func any() -> bool:
	return ver > 0


func _drain(id: String, w: float) -> bool:
	pool[id] = float(pool[id]) - w
	if float(pool[id]) > 1e-4:
		return false
	state[id] = BROKEN
	return true
