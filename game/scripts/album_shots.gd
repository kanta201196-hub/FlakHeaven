class_name AlbumShots
extends RefCounted
## Frames for the build album pictures (PG-16, Kanta 2026-11-11 «сразу нормально с картинками»): one in-game
## frame per album entry, the effect at work on the gameplay camera. For every entry this class can collect, the
## driver clears the plane, mounts what the recipe needs (weapons at a high level, catalyst modules, wingmen, the
## class skill), grants the entry (opens the synergy, modernizes, picks the profile, fills the archetype), lets the
## plane fight for a few seconds in god mode with the HUD hidden, and saves SHOTS frames per entry:
##   user://album/<kind>_<id>_<n>.png  (n = 0…SHOTS-1; the best one is picked by hand into res://art/album/)
## Run per class (the class that flies the entry best is chosen by `owner_of`):
##   godot --path game --rendering-driver opengl3 -- --autotest --god --class=fighter --albumshots [--only=syn:carousel]
## Debug only; it never runs in a player build because `--autotest` is a debug flag.

## Plane tier flown for the frames: tier 3 carries every weapon of its class
const TIER := 3
## Seconds of sortie time skipped first, so the sky and the ground are busy
const START_T := 330.0
## Seconds of fighting before the first frame, between frames, and frames per entry
const WARM := 0.6
const EVERY := 0.35
const SHOTS := 5
## Camera zoom for the frames (1 — the gameplay camera): close enough to see the plane, wide enough for the effect
const ZOOM := 2.8
## Targets set out ahead of the plane for every entry: air ones at this distance range, px, and how many
const AIR_D := Vector2(200.0, 460.0)
const AIR_N := 14
## Each entry is shot over another part of the map (a seeded offset from the start, px), so the album is not one
## landscape sixty times
const SPREAD := 6000.0
## The plane flies this share of its cruise speed during the frames, so the fight it starts stays in the frame
const SLOW := 0.3
## A bomber crossing ahead: a big, tough target that draws every weapon's fire into the frame
const BOMBER_D := 420.0
const BOMBER_HP := 25.0
## Weapons that want ground targets: an AA site is set out ahead for them
const GROUND_W := ["bombs", "hebomb", "rockets", "agm"]
## Output frame size
const OUT := Vector2i(960, 540)
## Class preference per weapon family: the class whose plane wears that family by default
const CLASS_ORDER := ["fighter", "attacker", "bomber"]

var m: Main
var _ids: Array = []
var _i := -1
var _t := 0.0
var _shot := 0
var _started := false
var _origin := Vector2.ZERO


func _init(main: Main) -> void:
	m = main


## Class that shoots entry `id`: a skill synergy's own class, else the first class of `CLASS_ORDER` whose tier-`TIER`
## plane can collect it (with `pref` for the weapon families the attacker and the bomber are known for)
static func owner_of(id: String) -> String:
	var kind := AlbumBook.kind(id)
	var sid := id.get_slice(":", 1)
	if kind == "syn" and SynPairs.SKILL_REQ.has(sid):
		var sk := _skill_of(sid)
		for c: String in PlaneClasses.CLASS_SKILLS:
			if (PlaneClasses.CLASS_SKILLS[c] as Array).has(sk):
				return c
		return ""
	var order := CLASS_ORDER.duplicate()
	var w := ""
	if kind == "evo":
		w = Modernizations.weapon_of(sid)
	elif kind == "prof":
		w = sid
	if w in ["bombs", "hebomb", "turret"]:
		order = ["bomber", "attacker", "fighter"]
	elif w in ["rockets", "agm"]:
		order = ["attacker", "fighter", "bomber"]
	elif kind == "arch":
		order = {"blast": ["bomber"], "turrets": ["bomber"], "wing": ["fighter"]}.get(sid, []) + CLASS_ORDER
	for c: String in order:
		var ctx := _plane_ctx(c)
		var r := AlbumNear.row(ctx, id)
		if not r.is_empty() and r["reach"]:
			return c
	return ""


## Class skill (`PlaneClasses.SKILL3` key) of class `c`
static func _class_skill(c: String) -> String:
	return String((PlaneClasses.DATA[c] as Dictionary).get("skill3", ""))


## Class skill whose synergy is `sid` ("" — none)
static func _skill_of(sid: String) -> String:
	for sk in PlaneClasses.SKILL3:
		if PlaneClasses.SKILL3[sk]["syn"]["id"] == sid:
			return String(sk)
	return ""


## A bare context of class `c` at tier `TIER` (what the plane may carry, nothing collected)
static func _plane_ctx(c: String) -> Dictionary:
	var pd := PlaneClasses.plane(c, TIER)
	var sk := _class_skill(c)
	return {"snap": {"w": {}, "taken": {}, "wing": 0, "s3": 0}, "weapons": (pd["weapons"] as Array).filter(func(w): return Weapons.in_game(w)),
		"wing_cap": int(pd.get("wingmen", 0)), "skill_syn": String(PlaneClasses.SKILL3[sk]["syn"]["id"]) if PlaneClasses.SKILL3.has(sk) else "",
		"owned": [], "course": "", "evo_done": [], "evo_time": true, "profiles": {}, "third_open": {"aam": true, "rockets": true, "bombs": true, "srm": true, "agm": true, "hebomb": true, "flares": true},
		"tags": {}, "arch_on": true, "pairs_on": true}


## Called every frame by MainDebug. Returns true while it drives the game (the autotest bot then stays out).
func process(delta: float) -> bool:
	if m.state == "menu" and not _started:
		_prepare_profile()
		return false
	if not (m.state in ["playing", "levelup", "paused", "album"]) or not is_instance_valid(m.player):
		return false
	if m.state != "playing":   # level-ups and pauses would change the plane under the frame
		m.run.pending_levels = 0
		m._set_state("playing")
	if not _started:
		_started = true
		_ids = Profile.album_ids().filter(func(id): return owner_of(String(id)) == m.cls_id and _wanted(String(id)))
		# wingmen persist on the plane, so entries that need them go last
		_ids.sort_custom(func(a, b): return int(_needs_wing(String(a))) < int(_needs_wing(String(b))))
		print("ALBUMSHOTS: class %s, %d entries: %s" % [m.cls_id, _ids.size(), str(_ids)])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://album"))
		m.god_mode = true
		m.run_time = maxf(m.run_time, START_T)
		m.spawner.process_mode = Node.PROCESS_MODE_DISABLED   # only the targets set out per entry, so frames stay readable
		_origin = m.player.global_position
		if m.hud != null:
			m.hud.visible = false
		_next()
		return true
	m.camera.zoom = Vector2.ONE * ZOOM
	m.player.hp = m.player.max_hp
	m.player.mods["speed"] = SLOW
	_t += delta / maxf(Engine.time_scale, 0.01)
	if _i >= _ids.size():
		print("ALBUMSHOTS: done")
		m.get_tree().quit()
		return true
	if _t >= WARM + _shot * EVERY:
		_save(String(_ids[_i]), _shot)
		_shot += 1
		if _shot >= SHOTS:
			_next()
	return true


## Fresh-profile setup in the menu: every tier of the classes owned and tier `TIER` selected, so the plane carries
## every weapon of its class (srm needs the fighter's tier 3)
func _prepare_profile() -> void:
	for c: String in CLASS_ORDER:
		Profile.cls(c)["tiers"] = [1, 2, 3]
		Profile.cls(c)["plane_sel"] = TIER


func _wanted(id: String) -> bool:
	for a in m._args:
		if String(a).begins_with("--only="):
			return String(a).substr(7).split(",").has(id)
	return true


static func _needs_wing(id: String) -> bool:
	if AlbumBook.kind(id) != "syn":
		return AlbumBook.kind(id) == "arch" and id == "arch:wing"
	return SynPairs.req(id.get_slice(":", 1)).any(func(t): return t.has("wing") or (t.has("mods") and (t["mods"] as Array).has("radio")))


func _next() -> void:
	_i += 1
	_t = 0.0
	_shot = 0
	if _i < _ids.size():
		_setup(String(_ids[_i]))
		_targets()


## Clears the sky and sets out fresh targets ahead of the plane: drones and interceptors, plus an AA site when a
## weapon on the plane hits the ground
func _targets() -> void:
	var p := m.player
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(_ids[_i]))
	p.global_position = _origin + Vector2(rng.randf_range(-SPREAD, SPREAD), rng.randf_range(-SPREAD, SPREAD))
	p.heading = rng.randf_range(-PI, PI)
	m.camera.global_position = p.global_position
	m.camera.reset_smoothing()
	for e in m.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not (e is Wingman):
			(e as Node).queue_free()
	for n in m.world.get_children():
		if n is AASite:
			n.queue_free()
	var fwd := Vector2.from_angle(p.heading)
	for i in AIR_N:
		var e: Enemy = Interceptor.new() if i % 3 == 0 else Drone.new()
		var a := p.heading + rng.randf_range(-0.7, 0.7)
		e.position = p.global_position + Vector2.from_angle(a) * rng.randf_range(AIR_D.x, AIR_D.y)
		e.heading = p.heading + PI + rng.randf_range(-0.5, 0.5)
		m.world.add_child(e)
	var b := Bomber.new()   # one big target ahead that draws the fire into the frame
	b.heading = p.heading + PI * 0.75
	b.position = p.global_position + fwd * BOMBER_D - Vector2.from_angle(b.heading) * 120.0
	m.world.add_child(b)
	b.apply_hp_mult(BOMBER_HP)
	for g in p.groups:   # every weapon fires at once instead of waiting out its first reload
		(g as Hardpoint).cd = 0.0
	if p.groups.any(func(g): return GROUND_W.has((g as Hardpoint).weapon)):
		var site := AASite.new()
		site.setup_spots(AASite.place(Terrain3D.active(), p.global_position + fwd * 520.0, p.heading, 0.7), 1.0, 0.0)
		m.world.add_child(site)


func _save(id: String, n: int) -> void:
	var img := m.get_viewport().get_texture().get_image()
	img.resize(OUT.x, OUT.y, Image.INTERPOLATE_LANCZOS)
	var path := "user://album/%s_%d.png" % [id.replace(":", "_"), n]
	img.save_png(path)
	print("ALBUMSHOTS: ", path)


# ---------- loadout per entry ----------

## Clears the plane and gives it what entry `id` needs, then grants the entry
func _setup(id: String) -> void:
	var p := m.player
	_clear(p)
	var kind := AlbumBook.kind(id)
	var sid := id.get_slice(":", 1)
	var allowed: Array = (PlaneClasses.plane(m.cls_id, TIER)["weapons"] as Array).filter(func(w): return Weapons.in_game(w))
	match kind:
		"syn":
			for t: Dictionary in SynPairs.req(sid):
				if t.has("w"):
					for w in t["w"]:
						if allowed.has(w) or (w == "turret" and _has_builtin(p, "turret")):
							_mount(p, String(w), 4)
							break
				elif t.has("mods"):
					for mk in t["mods"]:
						if mk != "radio" or p.permanent_wingmen() > 0 or int(p.cls["wingmen"]) > 0:
							_give_mod(p, String(mk), 3)
				elif t.has("wing"):
					_wing(p)
				elif t.has("skill"):
					p.skill3 = _skill_of(sid)
					p.mods["s3_lvl"] = 3
			# radio needs a wingman to act on
			if SynPairs.req(sid).any(func(t): return t.has("mods") and (t["mods"] as Array).has("radio")):
				_wing(p)
			p.open_synergy(sid)
		"evo":
			var w := Modernizations.weapon_of(sid)
			var c := Modernizations.cat(sid)
			for mk: String in c:
				_give_mod(p, mk, int(c[mk]))
			if w == "gun":
				p.evolve("gun")
			else:
				_mount(p, w, Weapons.MAX_LEVEL)
				p.evolve(sid)
		"prof":
			var g := _mount(p, sid, 4)
			if g != null:
				g.profile = id.get_slice(":", 2)
		"arch":
			var tg := sid
			var need := int(ArchBalance.at_of(tg)[2])
			p.add_tags([tg], need)
			# the family's weapons, so the rank's effect has something to act on
			var fam := {"missiles": ["aam", "srm", "agm"], "blast": ["bombs", "rockets", "hebomb"], "kinetic": [], "turrets": ["turret"],
				"wing": [], "maneuver": ["flares"], "armor": []}
			for w in fam.get(tg, []):
				if allowed.has(w) or (w == "turret" and _has_builtin(p, "turret")):
					_mount(p, String(w), 4)
			if tg == "wing":
				_wing(p)
			if tg == "armor":
				_give_mod(p, "armor", 3)
			if tg in ["kinetic", "maneuver"]:
				_give_mod(p, "gun_dmg" if tg == "kinetic" else "roll", 3)
	print("ALBUMSHOTS: setup %s — weapons %s, syn %s" % [id, str(p.groups.map(func(g): return "%s:%d" % [(g as Hardpoint).weapon, (g as Hardpoint).level])), str(p.syn.keys())])


## Takes every hardpoint weapon off the free mounts and resets what the last entry gave
func _clear(p: Player) -> void:
	for g in p.groups:
		var h: Hardpoint = g
		h.evo = false
		h.evo_id = ""
		h.profile = ""
		if not h.builtin:
			h.weapon = ""
			h.level = 0
	p.syn.clear()
	p.gun_evo = false
	p.mods["s3_lvl"] = 1
	for k in p.taken.keys():
		p.taken[k] = 0
	for tg: String in Prog.TAG_ORDER:
		p.add_tags([tg], -p.tag(tg))


func _has_builtin(p: Player, w: String) -> bool:
	return p.groups.any(func(g): return (g as Hardpoint).builtin and (g as Hardpoint).weapon == w)


## Puts weapon `w` at level `lv` on the first free mount (a built-in mount of that weapon is raised instead);
## returns the mount, or null when there is none
func _mount(p: Player, w: String, lv: int) -> Hardpoint:
	for g in p.groups:
		var h: Hardpoint = g
		if h.weapon == w:
			h.level = maxi(h.level, lv)
			return h
	for g in p.groups:
		var h: Hardpoint = g
		if h.is_empty() and not h.builtin and (not h.heavy or Weapons.EXP.has(w)):
			h.weapon = w
			h.level = lv
			h.cd = 0.3
			h.priority = "nearest"
			h.trigger = "auto"
			return h
	print("ALBUMSHOTS: no free mount for ", w)
	return null


func _give_mod(p: Player, mk: String, n: int) -> void:
	p.taken[mk] = maxi(int(p.taken.get(mk, 0)), n)


func _wing(p: Player) -> void:
	if p.permanent_wingmen() == 0:
		var types: Array = p.cls.get("wing_types", ["swift"])
		p.add_wingman(String(types[0]) if not types.is_empty() else "swift", 1.0)
