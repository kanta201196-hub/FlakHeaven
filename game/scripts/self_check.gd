class_name SelfCheck
extends RefCounted
## Build self-check (R-23, Kanta 31.10): the contact sheet attached to every build. One Godot process shoots one
## part at one graphics preset and writes JPEG frames plus a JSON manifest into an output folder; the wrapper
## tools/ci/selfcheck.sh runs the processes and tools/ci/selfcheck_page.py builds the page.
##   hangar — every plane (class × plane 1/2) with each weapon it may carry alone on its hardpoints, at weapon
##            lvl 1 / 3 / 5 and modernised, from the hangar's default view (Hangar3D, the «САМОЛЁТ» tab); then
##            the weapon store («ОРУЖИЕ» tab): each weapon on its stand at the same levels.
##   combat — every plane in a sortie at the gameplay camera (VisualBench points): in flight, then close-ups of the
##            nozzle flames, the muzzle points (magenta markers), the stores (rolled belly-up) and the trails.
## Each frame also runs cheap geometry checks (MountCheck): a weapon, turret, flame or muzzle point that lies
## farther than GAP_MAX from the skin it belongs to, or a node that is missing, becomes an issue in the manifest.
##
## Flags (read once here): --selfcheck=hangar|combat with --selfcheck-out=<absolute folder>, inside --visual
## (combat: also --tilt=28 --op=1, as the gameplay camera); --gfx=N names the preset in the files. Debug builds
## only: in a tester or release build (Main.DEBUG off) it does nothing. Created by VisualBench, which feeds it.

## Active self-check of this process; null in normal play
static var I: SelfCheck = null

## Frame size and JPEG quality of the sheet
const OUT_W := 1920
const OUT_H := 1080
const JPEG_Q := 0.85
## A part floats when its gap to the skin it hangs on is above this share of the plane length (about 15–20 cm on
## a real fighter): a pylon top, a turret ring, a muzzle point
const GAP_MAX := 0.01
## Nozzle flame: the mean gap of a ring at the nozzle's inner radius to the lip, in nozzle radii, above which the
## flame does not sit in its nozzle (a flame between two nozzles has no lip round it at all)
const NOZZLE_RING_MAX := 0.6
## Weapon store: gap between the weapon and its stand (view units; the weapon is about 0.6 long there)
const STAND_GAP_MAX := 0.01
## Frames to wait after a hangar rebuild before the shot (the SubViewport draws the new model on the next frame)
const WAIT_FRAMES := 1
## SubViewport supersample of the hangar plane view (664 × 434 at 1080p → ≈ 1990 wide) and of the store view
const SS_PLANE := 3.0
const SS_STORE := 4.5
## Hangar camera: the hangar's default yaw (Hangar3D.YAW0), a little farther than its DIST0 so the whole plane
## fits a 16:9 frame; turrets and the «Салют» launcher sit on top and show from the default pitch, stores hanging
## under the wings or in the bay only from a little below
const HANGAR_DIST := 1.5
const PITCH_UNDER := -0.2   ## the lowest the hangar camera goes (Hangar3D.bench_pitch_min)
## Weapon view tier → weapon level shown (Hangar3D.weapon_tier); 4 is the modernised weapon
const TIER_LEVEL := {1: 1, 2: 3, 3: 5, 4: 5}
## Weapon store: classes whose store shows a different model (their own turret; the «Кит» bay cassette)
const STORE_CLASSES := {"turret": ["attacker", "bomber"], "bombs": ["attacker", "bomber"]}
## Combat wide shots: camera zoom (1 = the gameplay camera)
const ZOOM_FLIGHT := 1.0
const ZOOM_TRAIL := 1.4
## Combat close-ups: plane length as a share of the frame height, so a small fighter and a «Кит» fill it alike
## (a fixed zoom left the fighter a speck and the bomber at 400 px of 1920)
const FILL_NOZZLE := 1.7
const FILL_CLOSE := 0.85
## Nozzle close-up: the camera moves this share of the plane length back from its centre, onto the nozzles
const NOZZLE_BACK := 0.32
## Close-up: frames of its own camera before the shot (the flame and the markers need a frame or two to follow)
const SETTLE_MIN := 3
## Muzzle markers: sphere radius as a share of the plane length
const MARKER_R := 0.008

var m: Main
## "hangar" or "combat"
var part := ""
var out_dir := ""
var gfx := -1
## --selfcheck-only=a,b: keep jobs whose class, plane («bomber_2»), section, weapon or shot is in the list
var only := PackedStringArray()
var frames: Array[Dictionary] = []
var issues: Array[Dictionary] = []
var _jobs: Array[Dictionary] = []
var _job: Dictionary = {}
var _wait := 0
var _t_job := 0
var _t0 := 0
var _variant := ""   # combat: plane whose loadout is on the player now
var _markers: Array[Node3D] = []
var _started := false
var _finished := false
var _applied := false   # hangar: the current job reached Hangar3D
var _ccam: Camera3D = null   # combat close-up camera
var _close_name := ""   # the close-up point the camera serves now
var _close_n := 0   # frames of that point so far


## The self-check the command line asks for, or null. Reads the flags once.
static func from_args(main: Main) -> SelfCheck:
	var sc := SelfCheck.new()
	sc.m = main
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--selfcheck="):
			sc.part = a.get_slice("=", 1)
		elif a.begins_with("--selfcheck-out="):
			sc.out_dir = a.get_slice("=", 1)
		elif a.begins_with("--gfx="):
			sc.gfx = int(a.get_slice("=", 1))
		elif a.begins_with("--selfcheck-only="):
			sc.only = a.get_slice("=", 1).split(",", false)
	if not sc.part in ["hangar", "combat"] or sc.out_dir == "":
		return null
	DirAccess.make_dir_recursive_absolute(sc.out_dir)
	sc._t0 = Time.get_ticks_msec()
	return sc


# ---------- what to shoot (pure: no scene needed) ----------

## Plane keys that exist: [class, plane level] for every class and plane 1 / 2 (PlaneClasses.PLANES)
static func planes() -> Array:
	var out: Array = []
	for c: String in PlaneClasses.LIST:
		for lv: int in (PlaneClasses.PLANES[c] as Dictionary).keys():
			out.append([c, lv])
	return out


## Weapons plane `lv` of `cls` may carry, in the order of its list (the experimental heavy weapons left out)
static func plane_weapons(cls: String, lv: int) -> Array[String]:
	var out: Array[String] = []
	for w: String in PlaneClasses.PLANES[cls][lv]["weapons"]:
		if Weapons.in_game(w):
			out.append(w)
	return out


## Weapon view tiers that exist for `w`: lvl 1 / 3 / 5, and modernised only where the weapon evolves (Prog.EVOS)
static func tiers(w: String) -> Array[int]:
	var out: Array[int] = [1, 2, 3]
	if Prog.EVOS.has(w):
		out.append(4)
	return out


## Camera pitch of a hangar frame with weapon `w`: the default from above for what sits on top (turrets, flares),
## PITCH_UNDER for everything that hangs below
static func hangar_pitch(w: String) -> float:
	return Hangar3D.PITCH0 if w in ["turret", "flares"] else PITCH_UNDER


## Hangar jobs: every plane × weapon × tier 1–4. A tier the weapon lacks (no modernisation) stays in the list as
## "na", so the sheet shows an empty cell instead of a hole.
static func hangar_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pl: Array in planes():
		for w in plane_weapons(pl[0], pl[1]):
			for t in [1, 2, 3, 4]:
				out.append({"section": "hangar", "cls": pl[0], "lvl": pl[1], "weapon": w, "tier": t, "na": not tiers(w).has(t)})
	return out


## Weapon store jobs: each weapon of any plane on its stand at its tiers; turrets and bombs once per class whose
## store shows them differently (STORE_CLASSES), the rest with the attacker's store (the model does not depend on it)
static func store_jobs() -> Array[Dictionary]:
	var seen: Array[String] = []
	for pl: Array in planes():
		for w in plane_weapons(pl[0], pl[1]):
			if not seen.has(w):
				seen.append(w)
	var out: Array[Dictionary] = []
	for w in seen:
		for c: String in STORE_CLASSES.get(w, ["attacker"]):
			for t in [1, 2, 3, 4]:
				out.append({"section": "store", "cls": c, "lvl": 0, "weapon": w, "tier": t, "na": not tiers(w).has(t)})
	return out


## Hardpoint groups of `cls` in the hangar with weapon `w` alone, as Hangar3D.bench_weapons wants them: the group
## the game would give `w` as the only start weapon (Profile.start_assign) carries it, the others carry nothing.
## A turret is built in: every group stays empty and the turret shows alone.
static func loadout(cls: String, w: String) -> Array:
	var names: Array = []
	for gd: Dictionary in PlaneClasses.DATA[cls]["groups"]:
		names.append(gd["name"])
	var where: Array = Profile.start_assign(names, [] if w == "turret" else [w], PlaneClasses.signature(cls))
	return where.map(func(x: String) -> String: return Hangar3D.BENCH_EMPTY if x == "" else x)


## Combat: weapons of plane `lv` on the base groups and the third group, in Player group order, the signature
## first and then the next weapons of the plane's list, so every pylon of the plane carries something
static func combat_loadout(cls: String, lv: int) -> Array[String]:
	var pool: Array[String] = []
	for w in plane_weapons(cls, lv):
		if w != "turret" and w != "flares":   # turrets are built in; flares are skin panels, nothing hangs
			pool.append(w)
	var defs := PlaneClasses.group_defs(cls, true)
	var out: Array[String] = []
	for i in defs.size():
		out.append(pool[i % pool.size()] if not pool.is_empty() else "")
	# bombs belong in the bomb bay: swap them onto it when the class has one
	var bay := -1
	for i in defs.size():
		if String(defs[i]["name"]).begins_with("Бомбоотсек"):
			bay = i
	var bi := out.find("bombs")
	if bay >= 0 and bi >= 0 and bi != bay:
		out[bi] = out[bay]
		out[bay] = "bombs"
	return out


## Combat points for VisualBench at `at`: per plane — in flight at the gameplay camera, then close-ups of the nozzles
## (afterburner on), the muzzle points, the stores (belly to the camera) and the trails with missile smoke
static func combat_points(at: Vector2) -> Array:
	var out: Array = []
	for pl: Array in planes():
		var key := "%s_%d" % [pl[0], pl[1]]
		var base := {"pos": at, "cls": [pl[0], pl[1]], "sc": key}
		var shots := [
			{"sc_shot": "flight", "fly": true, "zoom": ZOOM_FLIGHT, "wait": 3.0},
			{"sc_shot": "nozzles", "sc_ab": true, "sc_back": NOZZLE_BACK, "sc_fill": FILL_NOZZLE, "wait": 2.0, "sc_check": true},
			{"sc_shot": "muzzles", "sc_markers": true, "sc_fill": FILL_CLOSE, "wait": 1.0},
			{"sc_shot": "stores", "roll": 0.55, "sc_fill": FILL_CLOSE, "wait": 1.0},
			{"sc_shot": "trails", "fly": true, "sc_ab": true, "missiles": true, "zoom": ZOOM_TRAIL, "wait": 3.0},
		]
		for s: Dictionary in shots:
			var p := base.duplicate(true)
			p.merge(s)
			p["name"] = "sc_%s_%s" % [key, s["sc_shot"]]
			out.append(p)
	return out


## True when job or point `j` passes --selfcheck-only (always without it). A term joined with "+" passes only
## when all its parts match (`store+srm`: the weapon store's srm frames, not every plane carrying srm).
func wanted(j: Dictionary) -> bool:
	if only.is_empty():
		return true
	var c: String = j["cls"][0] if j["cls"] is Array else j["cls"]
	var lv: int = j["cls"][1] if j["cls"] is Array else j["lvl"]
	var keys := [c, "%s_%d" % [c, lv], j.get("section", "combat"), j.get("weapon", ""), j.get("sc_shot", "")]
	for t in only:
		if Array(t.split("+", false)).all(func(part: String) -> bool: return part in keys):
			return true
	return false


# ---------- hangar part ----------

## Per frame in the hangar part (VisualBench hands over): enters the hangar, then shoots the jobs one by one
func process_hangar() -> void:
	if not _gate():
		return
	if not _started:
		_started = true
		m.ui_click("menu_hangar")
		# the sortie world behind the hangar screen costs most of a software-rendered frame and is never seen
		m.get_viewport().disable_3d = true
		if Render3D.I != null:
			Render3D.I.process_mode = Node.PROCESS_MODE_DISABLED
		Hangar3D.anim_time = 0.0   # no sway, the mechanisation at rest: the same pose in every frame
		_jobs = hangar_jobs()
		_jobs.append_array(store_jobs())
		_jobs.assign(_jobs.filter(wanted))
		print("SELFCHECK hangar: %d jobs" % _jobs.size())
		return
	var h3 := Hangar3D.I
	if _job.is_empty():
		while not _jobs.is_empty() and bool(_jobs[0]["na"]):
			frames.append(_entry(_jobs.pop_front(), ""))
		if _jobs.is_empty():
			finish()
			return
		_job = _jobs.pop_front()
		_wait = 0
		_t_job = Time.get_ticks_msec()
		_applied = _setup_job(_job)
		return
	if h3 == null:
		return
	if not _applied:   # the hangar view did not exist yet when the job was set up
		_applied = _setup_job(_job)
		return
	if _job["section"] == "hangar":
		h3.debug_view(Hangar3D.YAW0, hangar_pitch(_job["weapon"]), HANGAR_DIST, Vector3.ZERO)
	else:
		h3.debug_view(Hangar3D.YAW0, 0.25, 1.0)   # the store view's own default (Hangar3D.show_weapon)
	_wait += 1
	if _wait <= WAIT_FRAMES:
		return
	var file := _file_name(_job)
	var ok := _save(h3.vp.get_texture().get_image(), file, true)
	var e := _entry(_job, file if ok else "")
	if not ok:
		_issue(e, "capture", "кадр не сохранился")
	elif _job["section"] == "hangar":
		_check_hangar(e)
	else:
		_check_store(e)
	e["ms"] = Time.get_ticks_msec() - _t_job
	frames.append(e)
	_write_manifest(false)
	print("SELFCHECK frame %s %d ms" % [file, e["ms"]])
	_job = {}


## Puts the hangar on the job's tab, plane, weapon and tier; false while the hangar view does not exist yet
func _setup_job(j: Dictionary) -> bool:
	var h3 := Hangar3D.I
	if j["section"] == "hangar":
		Hangar3D.bench_tab_w = ""
		Hangar3D.bench_supersample = SS_PLANE
		Hangar3D.bench_weapons = {j["cls"]: loadout(j["cls"], j["weapon"])}
		m.hangar_tab = "plane"
		m.hangar_cls = j["cls"]
		if h3 != null:
			h3.debug_show(j["cls"], j["lvl"], j["tier"])
	else:
		Hangar3D.bench_weapons = {}
		Hangar3D.bench_supersample = SS_STORE
		Hangar3D.bench_tab_w = j["weapon"]
		m.hangar_tab = "weapons"
		m.hangar_cls = j["cls"]
		m.hangar_w = j["weapon"]
		if h3 != null:
			h3.weapon_tier = j["tier"]
	return h3 != null


## Hangar plane: the GLB, each weapon on its skin (no skin-lookup miss, gap ≤ GAP_MAX), the job's weapon really
## mounted, the turret count of its level, the nozzle flames in their nozzles
func _check_hangar(e: Dictionary) -> void:
	var h3 := Hangar3D.I
	var cls: String = e["cls"]
	var lvl: int = e["lvl"]
	var key := "%s_%d" % [cls, lvl]
	var model := h3.debug_model()
	if model == null or not ResourceLoader.exists("res://models/hangar/fh_hangar_%s.glb" % key):
		_issue(e, "model", "нет ангарной модели %s" % key)
		return
	var faces := MountCheck.faces_of(model, h3.pivot, PackedStringArray(["nozzle_flame"]))
	var grid := MountCheck.build_grid(faces, GAP_MAX * 4.0)
	var found := false
	var turrets := 0
	for mt: Dictionary in h3.debug_mounts:
		var w: String = mt["weapon"]
		found = found or w == e["weapon"]
		if w == "turret":
			turrets += 1
		var node := mt["node"] as MeshInstance3D
		if node == null:
			_issue(e, "skin", "%s: панель в обшивке не легла на модель" % _wname(w))
			continue
		if bool(mt["miss"]):
			_issue(e, "miss", "%s (%s): под точкой подвеса нет обшивки — оружие на запасной высоте" % [_wname(w), mt["side"]])
		if mt["side"] == "skin":
			continue
		var gap := MountCheck.grid_gap(grid, MountCheck.node_points(node, h3.pivot), GAP_MAX)
		if gap > GAP_MAX:
			_issue(e, "gap", "%s (%s) висит в воздухе: зазор %s длины самолёта" % [_wname(w), mt["side"], _pct(gap)], gap, GAP_MAX)
	if not found:
		_issue(e, "missing", "%s не подвешено" % _wname(e["weapon"]))
	if int(PlaneClasses.DATA[cls]["turrets"]) > 0:
		var want := PlaneClasses.turret_slots(cls, int(TIER_LEVEL[e["tier"]]), lvl)
		if turrets != want:
			_issue(e, "turrets", "турелей %d, а по уровню должно быть %d" % [turrets, want], turrets, want)
	_check_nozzles(e, key, model, MountCheck.rel_xf(model, h3.pivot), faces, 1.0, model.find_child("nozzle_flame", false, false) != null)


## Weapon store: the weapon rests on its stand (gap ≤ STAND_GAP_MAX) instead of floating over it
func _check_store(e: Dictionary) -> void:
	var h3 := Hangar3D.I
	var weapon: MeshInstance3D = null
	var rest := PackedVector3Array()
	for c in h3.pivot.get_children():
		if c.is_queued_for_deletion() or not c is Node3D:
			continue
		if weapon == null and c is MeshInstance3D:
			weapon = c as MeshInstance3D   # show_weapon adds the weapon first, its stand after
		else:
			rest.append_array(MountCheck.faces_of(c as Node3D, h3.pivot))
	if weapon == null:
		_issue(e, "missing", "%s: модели нет на складе" % _wname(e["weapon"]))
		return
	if rest.is_empty():
		_issue(e, "stand", "%s: нет подставки" % _wname(e["weapon"]))
		return
	var grid := MountCheck.build_grid(rest, STAND_GAP_MAX * 4.0)
	var gap := MountCheck.grid_gap(grid, MountCheck.node_points(weapon, h3.pivot), STAND_GAP_MAX)
	if gap > STAND_GAP_MAX:
		_issue(e, "stand", "%s не лежит на подставке: зазор %s" % [_wname(e["weapon"]), _num(gap)], gap, STAND_GAP_MAX)


# ---------- combat part ----------

## Called by VisualBench._hold for a self-check point: the plane's loadout, the afterburner, the camera offset and
## the muzzle markers; weapons that leave the pylon stay loaded (no launches hide them)
func hold(p: Dictionary) -> void:
	if not p.has("sc") or not _gate():
		return
	var pl := m.player
	if _variant != p["sc"]:
		_variant = p["sc"]
		_set_variant(p["cls"][0], p["cls"][1])
	for g: Hardpoint in pl.groups:
		if Weapons.leaves_pylon(g.weapon) or g.weapon == "turret":
			g.cd = 0.29   # above zero: no launch; below 0.3: Render3D still shows the store
	if p.get("sc_ab", false):
		pl.ab_t = 1.0
	if p.has("sc_fill"):
		_frame_close(p)
	else:
		_frame_game()
	if p.get("sc_markers", false) and _markers.is_empty():
		_add_markers()


## Close-up framing, every frame of the point: a camera of its own on the gameplay camera's tilt, aimed at the
## plane (or sc_back of its length behind it: the nozzles) from the distance at which the plane length is sc_fill
## of the frame height. The gameplay camera cannot do this: it stands over the combat plane at a height that
## shrinks with zoom, while the plane flies at its relief altitude above that plane, so a close zoom put the camera
## level with the plane or under it (the fighter's nozzle frame came out empty).
func _frame_close(p: Dictionary) -> void:
	var r3 := Render3D.I
	var u := _player_unit()
	if r3 == null or u == null:
		return
	if _ccam == null:
		_ccam = Camera3D.new()
		_ccam.fov = Render3D.FOV
		_ccam.near = 1.0
		_ccam.far = 9000.0
		_ccam.keep_aspect = Camera3D.KEEP_HEIGHT
		_ccam.cull_mask = r3.cam.cull_mask
		r3.add_child(_ccam)
	if _close_name != String(p["name"]):
		_close_name = p["name"]
		_close_n = 0
	_close_n += 1
	var pl := m.player
	var len_px := maxf(_plane_px(), 1.0)
	var d := -Vector2.from_angle(pl.heading) * float(p.get("sc_back", 0.0)) * len_px
	var target := u.node.global_position + Vector3(d.x, 0.0, d.y)
	var dist := len_px / (float(p["sc_fill"]) * 2.0 * tan(deg_to_rad(Render3D.FOV) * 0.5))
	var tilt := deg_to_rad(Tuning.g("cam_tilt"))
	_ccam.global_position = target + Vector3(0.0, cos(tilt), sin(tilt)) * dist
	_ccam.basis = Basis.looking_at(Vector3(0.0, -cos(tilt), -sin(tilt)), Vector3(0, 0, -1))
	_ccam.current = true


## The gameplay camera again after a close-up
func _frame_game() -> void:
	if _ccam != null and _ccam.current and Render3D.I != null:
		Render3D.I.cam.current = true


## VisualBench asks before it shoots a point: a close-up waits SETTLE_MIN frames of its own camera (a slow frame
## can outlast the point's whole wait); any other point is ready at once
func settled(p: Dictionary) -> bool:
	if not p.has("sc_fill") or not _gate():
		return true
	return _close_name == String(p.get("name", "")) and _close_n >= SETTLE_MIN


## Called by VisualBench._save for a self-check point instead of its own PNG: the JPEG, the manifest entry and,
## on the point that asks for it, the combat checks
func save_combat(name: String, img: Image, p: Dictionary) -> void:
	var j := {"section": "combat", "cls": p["cls"][0], "lvl": p["cls"][1], "weapon": "", "tier": 0, "shot": p["sc_shot"]}
	var file := "c_%s_%s_g%d.jpg" % [p["sc"], p["sc_shot"], gfx]
	var ok := _save(img, file, false)
	var e := _entry(j, file if ok else "")
	if not ok:
		_issue(e, "capture", "кадр не сохранился")
	if p.get("sc_check", false):
		_check_combat(e)
	frames.append(e)
	_write_manifest(false)
	print("SELFCHECK frame %s (%s)" % [file, name])
	for n in _markers:
		if is_instance_valid(n):
			n.queue_free()
	_markers.clear()


## The player becomes plane `lv` of `cls` with the combat loadout at lvl 5 on every group, built in Player.setup's
## group order (base groups, turrets, the plane-2 heavy hardpoint, the third group), so the 3D layout matches
func _set_variant(cls: String, lv: int) -> void:
	var pl := m.player
	pl.cls_id = cls
	pl.plane_lvl = lv
	pl.cls = PlaneClasses.plane(cls, lv)
	pl.size = float(pl.cls["size"])
	var load := combat_loadout(cls, lv)
	var defs := PlaneClasses.group_defs(cls, true)
	var gs: Array[Hardpoint] = []
	var third: Hardpoint = null
	for i in defs.size():
		var h := Hardpoint.new(defs[i]["name"], int(defs[i]["slots"]), load[i])
		h.level = Weapons.MAX_LEVEL
		h.mount_frac = float(defs[i].get("frac", 0.0))
		if i < (PlaneClasses.DATA[cls]["groups"] as Array).size():
			gs.append(h)
		else:
			third = h
	if int(PlaneClasses.DATA[cls]["turrets"]) > 0:
		var tg := Hardpoint.new("Турели", 1, "turret", true)
		tg.level = Weapons.MAX_LEVEL
		tg.slots = PlaneClasses.turret_slots(cls, tg.level, lv)
		gs.append(tg)
	if lv == 2:
		var heavy := Hardpoint.new("Тяжёлый подвес", 1, "")
		heavy.heavy = true
		gs.append(heavy)
	if third != null:
		gs.append(third)
	pl.groups.clear()
	pl.groups.append_array(gs)


## Plane length on screen in world px (Render3D sizes the player's unit the same way)
func _plane_px() -> float:
	var pl := m.player
	var tex := PlaneArt.plane_tex(pl.cls_id, pl.plane_lvl)
	var t1 := PlaneArt.plane_tex(pl.cls_id, 1)
	var k := float(tex.get_width()) / float(t1.get_width()) if tex != null and t1 != null else 1.0
	return Tuning.g("plane_len") * pl.size * k


## Magenta spheres, drawn over everything, at the points rounds and stores leave from: the course gun ports (both
## sides), each turret's barrel point, each missile or bomb on its pylon
func _add_markers() -> void:
	var u := _player_unit()
	if u == null or u.bm == null:
		return
	var root := u.node
	var tw := float(u.tex.get_width())
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.1, 0.9)
	mat.no_depth_test = true
	mat.render_priority = 10
	var sm := SphereMesh.new()
	sm.radius = MARKER_R * tw
	sm.height = MARKER_R * tw * 2.0
	sm.material = mat
	for pt in _muzzle_points(u):
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.name = "selfcheck_marker"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = pt
		root.add_child(mi)
		_markers.append(mi)


## Muzzle and launch points of the player's unit in its own axes (picture px)
func _muzzle_points(u: Unit3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var model := u.node.get_child(0) as Node3D
	var gp := ModuleParts.gun_point(u.tex.resource_path.get_file().get_basename())
	if gp != Vector3.INF and model != null:
		out.append(model.transform * gp)
		out.append(model.transform * Vector3(gp.x, gp.y, -gp.z))
	for k: String in u.weapons:
		var wmi := u.weapons[k] as MeshInstance3D
		if wmi == null or k.ends_with("_skin") or k.ends_with("_fair") or wmi.mesh == null:
			continue
		out.append(wmi.transform * Vector3(0.35, 0.0, 0.0) if k.contains("_turret_") else wmi.position)
	return out


## Battle model of the player: every weapon mounted and on its skin, the flames in the nozzles, the trail starting
## at them, the course-gun ports on the nose, the turret muzzle points on their barrels
func _check_combat(e: Dictionary) -> void:
	var u := _player_unit()
	if u == null or u.bm == null:
		_issue(e, "model", "нет боевой 3D-модели")
		return
	var key := u.tex.resource_path.get_file().get_basename()
	var root := u.node
	var model := root.get_child(0) as Node3D
	var tw := float(u.tex.get_width())
	var lim := GAP_MAX * tw
	var faces := MountCheck.faces_of(model, root, PackedStringArray(["module_parts"]))
	var grid := MountCheck.build_grid(faces, lim * 4.0)
	var want := 0
	for gk: Variant in u.wcache:
		if gk is int:
			for mt: Dictionary in u.wcache[gk]["mounts"]:
				if not mt.has("skin"):
					want += 1
	var have := 0
	for k: String in u.weapons:
		var wmi := u.weapons[k] as MeshInstance3D
		if k.ends_with("_skin") or k.ends_with("_fair"):
			if wmi == null or wmi.mesh == null:
				_issue(e, "skin", "панель/обтекатель %s не легли на обшивку" % k)
			continue
		have += 1
		if wmi == null or wmi.mesh == null:
			_issue(e, "missing", "подвес %s без модели" % k)
			continue
		var gap := MountCheck.grid_gap(grid, MountCheck.node_points(wmi, root), lim)
		if gap > lim:
			_issue(e, "gap", "%s висит в воздухе: зазор %s длины самолёта" % [k, _pct(gap / tw)], gap / tw, GAP_MAX)
		if k.contains("_turret_"):
			var mp := wmi.transform * (wmi.get_meta("muzzle_local", Vector3(0.35, 0.0, 0.0)) as Vector3)
			var own := MountCheck.faces_of(wmi, root)
			var mg := MountCheck.point_gap(own, mp, lim * 4.0)
			if mg > lim:
				_issue(e, "muzzle", "точка вылета турели %s не на стволах: %s длины самолёта" % [k, _pct(mg / tw)], mg / tw, GAP_MAX)
	if have != want:
		_issue(e, "missing", "моделей на подвесах %d из %d" % [have, want], have, want)
	var flames: Array = u.fx.get("flames", [])
	var nz := PlaneFx.model_nozzles(key, tw)
	if not nz.is_empty() and flames.size() != (nz["jet"] as Array).size():
		_issue(e, "flame", "факелов %d, сопел %d" % [flames.size(), (nz["jet"] as Array).size()], flames.size(), (nz["jet"] as Array).size())
	_check_nozzles(e, key, model, model.transform, faces, tw, not flames.is_empty())
	for tp: Vector3 in u.fx.get("trail", []):
		var r := float(NozzleFlame.NOZZLES.get(key, [0, 0, 0, 0.0])[3]) * tw
		var tg := MountCheck.point_gap(faces, tp, lim * 4.0 + r * 2.0)
		if tg > lim + r * 2.0:
			_issue(e, "trail", "след начинается в %s длины от самолёта" % _pct(tg / tw), tg / tw, GAP_MAX)
	var gp := ModuleParts.gun_point(key)
	if gp == Vector3.INF:
		_issue(e, "gun", "нет точки курсовой пушки")
	else:
		var g2 := MountCheck.point_gap(faces, model.transform * gp, lim * 4.0)
		if g2 > lim:
			_issue(e, "gun", "точка курсовой пушки не на носу: %s длины" % _pct(g2 / tw), g2 / tw, GAP_MAX)


## Nozzle flames of plane `key`: present when the plane has jets, and each nozzle (NozzleFlame.NOZZLES, model axes,
## moved by `xf` and scaled by `scale`) has a lip round it — the mean gap of a ring at its inner radius
func _check_nozzles(e: Dictionary, key: String, model: Node3D, xf: Transform3D, faces: PackedVector3Array, scale: float, has_flame: bool) -> void:
	var n: Array = NozzleFlame.NOZZLES.get(key, [])
	if n.is_empty():
		return
	if not has_flame:
		_issue(e, "flame", "нет факела в соплах")
	var r: float = float(n[3]) * scale
	for z: float in ([0.0] if is_zero_approx(float(n[2])) else [-float(n[2]), float(n[2])]):
		var c := xf * Vector3(float(n[0]), float(n[1]), z)
		var ring := MountCheck.ring(c, xf.basis.x, r)
		var g := MountCheck.mean_gap(faces, ring, r * 3.0)
		e["nozzle_ring"] = snappedf(g / r if not is_inf(g) else 99.0, 0.01)
		if g > r * NOZZLE_RING_MAX:
			_issue(e, "nozzle", "факел не в сопле (z %.3f): обод в среднем в %s радиуса" % [z, "%.2f" % (g / r) if not is_inf(g) else "> 3"], g / r, NOZZLE_RING_MAX)


func _player_unit() -> Unit3D:
	if Render3D.I == null or not is_instance_valid(m.player):
		return null
	return Render3D.I.debug_unit(m.player.get_instance_id())


# ---------- output ----------

## Writes the final manifest of this process and quits with code 0; the page script reads it
func finish() -> void:
	if _finished:
		return
	_finished = true
	_write_manifest(true)
	print("SELFCHECK done: %d frames, %d issues, %.0f s" % [frames.size(), issues.size(), (Time.get_ticks_msec() - _t0) / 1000.0])
	m.get_tree().quit(0)


## manifest_<part>_g<gfx>.json: written after every frame too, so a run cut short by its time limit keeps what it
## shot (`complete` false tells the page it was cut)
func _write_manifest(complete: bool) -> void:
	var renderer := RenderingServer.get_current_rendering_method()
	var titles := {}
	for c: String in PlaneClasses.LIST:
		titles[c] = PlaneClasses.DATA[c]["title"]
	var wnames := {}
	for w: String in Weapons.DEFS:
		wnames[w] = Weapons.DEFS[w]["short"]
	var evos := {}
	for w: String in Prog.EVOS:
		evos[w] = Prog.EVOS[w]["title"]
	var doc := {"part": part, "gfx": gfx, "renderer": renderer, "seconds": (Time.get_ticks_msec() - _t0) / 1000.0,
		"frames": frames, "issues": issues, "class_titles": titles, "weapon_names": wnames, "evo_names": evos,
		"complete": complete}
	var f := FileAccess.open(out_dir.path_join("manifest_%s_g%d.json" % [part, gfx]), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc, " "))
		f.close()


## Saves `img` as a 1920 × 1080 JPEG: a hangar view (`crop`) is cut to 16:9 round its centre first
func _save(img: Image, file: String, crop: bool) -> bool:
	if img == null or img.is_empty():
		return false
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	if crop:
		var w := img.get_width()
		var h := img.get_height()
		var cw := mini(w, int(h * 16.0 / 9.0))
		var ch := mini(h, int(w * 9.0 / 16.0))
		img = img.get_region(Rect2i((w - cw) / 2, (h - ch) / 2, cw, ch))
	if img.get_width() != OUT_W or img.get_height() != OUT_H:
		img.resize(OUT_W, OUT_H, Image.INTERPOLATE_LANCZOS)
	return img.save_jpg(out_dir.path_join(file), JPEG_Q) == OK


func _file_name(j: Dictionary) -> String:
	if j["section"] == "store":
		return "s_%s_%s_t%d_g%d.jpg" % [j["cls"], j["weapon"], j["tier"], gfx]
	return "h_%s_%d_%s_t%d_g%d.jpg" % [j["cls"], j["lvl"], j["weapon"], j["tier"], gfx]


func _entry(j: Dictionary, file: String) -> Dictionary:
	var e := {"section": j["section"], "cls": j["cls"], "lvl": j["lvl"], "weapon": j.get("weapon", ""),
		"tier": j.get("tier", 0), "shot": j.get("shot", ""), "gfx": gfx, "file": file, "na": j.get("na", false)}
	return e


func _issue(e: Dictionary, what: String, text: String, value: Variant = null, limit: Variant = null) -> void:
	var i := {"file": e["file"], "section": e["section"], "cls": e["cls"], "lvl": e["lvl"], "weapon": e["weapon"],
		"tier": e["tier"], "shot": e["shot"], "gfx": gfx, "what": what, "text": text}
	if value != null:
		# a gap past the search radius comes back as INF, which JSON cannot hold: -1 means «farther than searched»
		i["value"] = snappedf(float(value), 0.0001) if is_finite(float(value)) else -1.0
		i["limit"] = limit
	issues.append(i)
	print("SELFCHECK issue %s: %s" % [e["file"], text])


## Gate: debug builds only. Logs once and turns the self-check off otherwise.
func _gate() -> bool:
	if Main.DEBUG:
		return true
	print("SELFCHECK: off — debug builds only")
	I = null
	return false


static func _wname(w: String) -> String:
	return String(Weapons.DEFS[w]["short"]) if Weapons.DEFS.has(w) else w


static func _pct(share: float) -> String:
	return "> %.1f%%" % (GAP_MAX * 400.0) if is_inf(share) else "%.1f%%" % (share * 100.0)


static func _num(v: float) -> String:
	return "> %.3f" % (STAND_GAP_MAX * 4.0) if is_inf(v) else "%.3f" % v
