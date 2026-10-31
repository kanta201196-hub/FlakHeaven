class_name WeaponFire
extends RefCounted
## Firing of the standard weapons added in PG-01 (`srm`, `agm`, `hebomb`), called from `Hardpoint.update`.
## Kept out of `hardpoint.gd` so that file does not grow by another weapon per stage. Each function fires
## one volley for hardpoint group `hp` of player `p` and returns true if anything left the pylons.
## Damage and reload come from `hp.dmg()` / `hp.reload_time()`, which read `WeaponBalance` for these ids.


## Short-range heat missiles: one per slot at the nearest air targets in range, faster turn than `aam`.
## PG-06 profiles: «Рой» — three mini-missiles per slot at different targets; «Гончая» — twice the turn and a
## longer flight; «Перехватчик» — the launch goes at an enemy missile near the player when there is one.
static func fire_srm(hp: Hardpoint, p: Player) -> bool:
	var pd := hp.prof()
	var guard := float(pd.get("intercept", 0.0))
	if guard > 0.0:
		var shot := 0
		for i in hp.slots:
			var at = Main.I.projectiles.intercept_missile_at(p.global_position, guard)
			if at == null:
				break
			shot += 1
			Main.I.fx.explosion(at, 18.0)
		if shot > 0:
			Main.I.stats_add_counter("intercepted", shot)
			Main.I.sfx.play("aam_launch", -18.0, 1.9)
			return true
	var per_slot := int(pd.get("per_slot", 1))
	var targets: Array = []
	for i in hp.slots * per_slot:
		var t := Weapons.pick_target(p.global_position, hp.range_px(), "nearest", targets, true, false, true)
		if t == null:
			break
		targets.append(t)
	if targets.is_empty():
		return false
	var md := hp.dmg()
	for i in hp.slots * per_slot:
		var t: Enemy = targets[i % targets.size()]
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := hp.slot_pos(p, i % hp.slots)
		var vel := p.velocity + Vector2.from_angle(p.heading + side * (0.35 + 0.15 * floori(i / float(hp.slots)))) * 180.0
		Main.I.projectiles.spawn_player_missile(pos, vel, t, md, "ракеты ближнего боя",
			{"turn_k": WeaponBalance.SRM_TURN_K * float(pd.get("turn", 1.0)), "spd_k": 1.1 * float(pd.get("spd", 1.0)),
			"life": float(pd.get("life", 1.8)), "splash": 40.0 if per_slot == 1 else 25.0})
		if Boom3D.active() and i < hp.slots:
			Boom3D.ensure().launch(pos, Vector2.from_angle(p.heading), p.velocity)
	Main.I.sfx.play("aam_launch", -18.0, 1.7)
	return true


## Guided air-to-ground missile: one per slot at ground targets in range — armored first, then big, then nearest.
## PG-06 profiles: «Кассетная» splits over the target into submunitions on the neighbours; «Бетонобой» hits
## armor harder; «Противорадарная» goes for radars and AA guns first.
static func fire_agm(hp: Hardpoint, p: Player) -> bool:
	var pd := hp.prof()
	var antiradar: bool = pd.get("antiradar", false)
	var targets: Array = []
	for i in hp.slots:
		var t := _agm_target(p.global_position, hp.range_px(), targets, antiradar)
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
		var opts := {"ground_k": WeaponBalance.AGM_GROUND_K, "spd_k": 0.9 * float(pd.get("spd", 1.0)), "life": 3.6, "big": true, "free": 0.25}
		if pd.has("split"):
			opts["split"] = int(pd["split"])
			opts["split_dmg"] = md * float(pd["split_k"])
			opts["split_ground"] = true
			opts["split_src"] = "УР В-З"
		if pd.has("armor_k"):
			opts["armor_k"] = float(pd["armor_k"])
		Main.I.projectiles.spawn_player_missile(pos, vel, t, md, "УР В-З", opts)
		if Boom3D.active():
			Boom3D.ensure().launch(pos, Vector2.from_angle(p.heading), p.velocity)
	Main.I.sfx.play("aam_launch", -14.0, 0.8)
	return true


## Ground target for `agm`: armored beats big beats near; `skip` — already taken by this volley.
## `antiradar` (PG-06 «Противорадарная»): a radar first, then any AA site gun, before everything else.
static func _agm_target(from: Vector2, max_dist: float, skip: Array, antiradar := false) -> Enemy:
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
		if antiradar and e is GroundTarget:
			var v: String = (e as GroundTarget).variant
			score -= 12000.0 if v == "radar" else (8000.0 if v in ["sam", "zsu"] else 0.0)
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
