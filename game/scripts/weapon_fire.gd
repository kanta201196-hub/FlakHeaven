class_name WeaponFire
extends RefCounted
## Firing of the standard weapons added in PG-01 (`srm`, `agm`, `hebomb`), called from `Hardpoint.update`.
## Kept out of `hardpoint.gd` so that file does not grow by another weapon per stage. Each function fires
## one volley for hardpoint group `hp` of player `p` and returns true if anything left the pylons.
## Damage and reload come from `hp.dmg()` / `hp.reload_time()`, which read `WeaponBalance` for these ids.


## Short-range heat missiles: one per slot at the nearest air targets in range, faster turn than `aam`.
static func fire_srm(hp: Hardpoint, p: Player) -> bool:
	var targets: Array = []
	for i in hp.slots:
		var t := Weapons.pick_target(p.global_position, hp.range_px(), "nearest", targets, true, false, true)
		if t == null:
			break
		targets.append(t)
	if targets.is_empty():
		return false
	var md := hp.dmg()
	for i in hp.slots:
		var t: Enemy = targets[i % targets.size()]
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := hp.slot_pos(p, i)
		var vel := p.velocity + Vector2.from_angle(p.heading + side * 0.35) * 180.0
		Main.I.projectiles.spawn_player_missile(pos, vel, t, md, "ракеты ближнего боя",
			{"turn_k": WeaponBalance.SRM_TURN_K, "spd_k": 1.1, "life": 1.8, "splash": 40.0})
		if Boom3D.active():
			Boom3D.ensure().launch(pos, Vector2.from_angle(p.heading), p.velocity)
	Main.I.sfx.play("aam_launch", -18.0, 1.7)
	return true


## Guided air-to-ground missile: one per slot at ground targets in range — armored first, then big, then nearest.
static func fire_agm(hp: Hardpoint, p: Player) -> bool:
	var targets: Array = []
	for i in hp.slots:
		var t := _agm_target(p.global_position, hp.range_px(), targets)
		if t == null:
			break
		targets.append(t)
	if targets.is_empty():
		return false
	var md := hp.dmg()
	for i in hp.slots:
		var t: Enemy = targets[i % targets.size()]
		var pos := hp.slot_pos(p, i)
		var vel := p.velocity + Vector2.from_angle(p.heading) * 120.0
		Main.I.projectiles.spawn_player_missile(pos, vel, t, md, "УР В-З",
			{"ground_k": WeaponBalance.AGM_GROUND_K, "spd_k": 0.9, "life": 3.6, "big": true, "free": 0.25})
		if Boom3D.active():
			Boom3D.ensure().launch(pos, Vector2.from_angle(p.heading), p.velocity)
	Main.I.sfx.play("aam_launch", -14.0, 0.8)
	return true


## Ground target for `agm`: armored beats big beats near; `skip` — already taken by this volley.
static func _agm_target(from: Vector2, max_dist: float, skip: Array) -> Enemy:
	var best: Enemy = null
	var best_score := INF
	for n in Main.I.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0 or not e.is_ground or skip.has(e):
			continue
		var d := from.distance_to(e.global_position)
		if d > max_dist:
			continue
		var score := d - (4000.0 if e.defense == "armor" else 0.0) - (2000.0 if e.big else 0.0)
		if score < best_score:
			best_score = score
			best = e
	return best


## HE bomb: one heavy bomb per slot — auto on the nearest ground targets, or by button at the aim point.
static func fire_hebomb(hp: Hardpoint, p: Player, manual: bool) -> bool:
	var targets: Array = []
	if not manual:
		for s in hp.slots:
			var t := Weapons.pick_target(p.global_position, 600.0, "nearest", targets, false, true)
			if t == null:
				break
			targets.append(t)
		if targets.is_empty():
			return false
	var fuse := WeaponBalance.HEBOMB_FUSE
	for s in hp.slots:
		var to: Vector2
		if not targets.is_empty():
			var t: Enemy = targets[s % targets.size()]
			to = t.global_position + t.move_vel * fuse
		else:
			to = hp.aim_point(p)
		Main.I.projectiles.spawn_bomb(hp.slot_pos(p, s), fuse, hp.dmg() * Hardpoint.GROUND_BOMB_K, hp.range_px(), "фугасные бомбы", to, true)
		Main.I.projectiles.bombs[-1]["vt"] = WeaponModels.HEBOMB_VT0 + WeaponModels.tier(hp.level)
		Main.I.projectiles.bombs[-1]["shake"] = WeaponBalance.HEBOMB_SHAKE
		hp.bay_release(p, Main.I.projectiles.bombs[-1], 0.0)
	Main.I.sfx.play("bomb_drop", -12.0, 0.8)
	return true
