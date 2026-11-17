extends Node
## Trailer capture (marketing tool, `-- --trailercap`): plays a bot sortie with fixed frame time and
## saves PNG frames only inside chosen run-time windows. Outside the windows the render loop is off,
## so the GPU-less cloud (lavapipe, ~3 s per Forward+ frame) only pays for the frames it keeps.
## Args: --capscale=F (window content scale: --resolution=1080x1920 with 1.7778 gives the same zoom as a
## 1920x1920 render cropped to 1080 wide, at 56% of the pixels), --capdir=DIR, --capwin=A-B,C-D (run seconds), --capscan (log action per second, no frames),
## --capseed=N, --capend=S (quit after this run second), --capzoom=F (camera zoom held every frame, so store
## art can frame the plane closer than the player slider allows), --caphud (keep the HUD, as a player sees it: no
## debug labels, the hull is refilled every frame instead of god mode, which the HUD would show), --capcards=N:T (also save the first N card-pick screens after run second T,
## once the cards are up), --capclean (hide the 2D world layer: HP arcs, sectors, name tags and target rings over the 3D
## view, so store art shows only the scene), --captilt=D (camera tilt held every frame, degrees from vertical).
## Story shots for store art (Kanta 17.11): fort (an active fortified area with its SAMs up, player close),
## fortdown (the taken fort burning; the player is moved back over it), missile (enemy missiles closing on the
## player; a class with flares fires a salvo), convoyhit (convoy close with the player's rockets/bombs in the air),
## loop (Wasp's loop in «Битва асов», started by the director), boom (several kills in two seconds close by),
## flares (a missile within range: the director fires a flare salvo right away and records the missiles turning).
## Sorties are not frame-exact between runs, so --capshots=NAME:MIN_T:LEN,... picks moments live:
## each named shot (see `_want`) starts once, after MIN_T, when its condition holds, and records LEN s.

const PREROLL := 1.5   # seconds rendered before a window so GPU particles and smoke are already alive

var m: Node
var dir := ""
var wins: Array = []   # [[from, to], ...]
var scan := false
var end_t := 0.0
var _n := 0
var _scan_t := 0.0
var _kills_prev := 0
var _saving := false
var shots: Array = []   # [{name, min_t, len, state: 0 wait / 1 preroll+rec / 2 done, t0}]
var _st := {}           # latest stats from `_stats`
var _kill_hist: Array = []
var zoom := 0.0      # >0: camera_zoom forced every frame (--capzoom)
var keep_hud := false
var cards_left := 0  # card-pick screens still to save (--capcards)
var cards_from := 0.0
var _in_cards := false
var clean := false   # --capclean
var tilt := -1.0     # >=0: cam_tilt forced every frame (--captilt)
var _fort_pos := Vector2.INF   # last seen fortified area (its ruin stays on the map after it is taken)
var _fort_done_t := -1.0       # run second the fort was taken, -1 while it stands
var _acts: Array = []          # pending director actions: [{t, kind}]


func _init(main: Node) -> void:
	m = main


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capdir="):
			dir = a.substr(9)
		elif a.begins_with("--capwin="):
			for w in a.substr(9).split(","):
				var p := w.split("-")
				wins.append([float(p[0]), float(p[1])])
				end_t = maxf(end_t, float(p[1]))
		elif a.begins_with("--capshots="):
			for w in a.substr(11).split(","):
				var p := w.split(":")
				shots.append({"name": p[0], "min_t": float(p[1]), "len": float(p[2]), "state": 0, "t0": 0.0})
		elif a.begins_with("--capscale="):
			get_window().content_scale_factor = float(a.substr(11))
		elif a.begins_with("--capend="):
			end_t = float(a.substr(9))
		elif a.begins_with("--capcards="):
			var p := a.substr(11).split(":")
			cards_left = int(p[0])
			cards_from = float(p[1]) if p.size() > 1 else 0.0
		elif a.begins_with("--capzoom="):
			zoom = float(a.substr(10))
		elif a.begins_with("--captilt="):
			tilt = float(a.substr(10))
	scan = OS.get_cmdline_user_args().has("--capscan")
	keep_hud = OS.get_cmdline_user_args().has("--caphud")
	clean = OS.get_cmdline_user_args().has("--capclean")
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.frame_post_draw.connect(_on_drawn)


func _process(_d: float) -> void:
	if m.hud != null and not keep_hud:
		m.hud.visible = m.state != "playing"
	if keep_hud:
		m.god_mode = false
		Main.DEBUG = false
		if m.player != null and is_instance_valid(m.player):
			m.player.hp = m.player.max_hp
	if zoom > 0.0:
		Tuning.set_param("camera_zoom", zoom)
	if tilt >= 0.0:
		Tuning.set_param("cam_tilt", tilt)
	if clean and m.world != null and is_instance_valid(m.world):
		m.world.modulate = Color(1, 1, 1, 0)
	var t: float = m.run_time
	_run_acts(t)
	var playing: bool = m.state == "playing"
	var render := false
	_saving = false
	if playing and not scan:
		for w in wins:
			if t >= w[0] - PREROLL and t <= w[1]:
				render = true
				_saving = t >= w[0]
		_direct(t)
		for sh in shots:
			if sh["state"] == 1:
				render = true
				var pre := _preroll(String(sh["name"]))
				_saving = t >= sh["t0"] + pre
				if t > sh["t0"] + pre + sh["len"]:
					sh["state"] = 2
					print("TRAILERCAP: shot %s done at %.1f" % [sh["name"], t])
	if m.state == "levelup" and cards_left > 0 and t >= cards_from:
		render = true
		_saving = m._state_t >= MainInput.CARD_INPUT_DELAY + 0.02
		_in_cards = true
	elif _in_cards:
		_in_cards = false
		cards_left -= 1
	_set_render(render)
	if playing and t >= _scan_t:
		_scan_t = t + 1.0
		_log(t)
	if not shots.is_empty() and shots.all(func(x): return x["state"] == 2):
		end_t = minf(end_t, t) if end_t > 0.0 else t
	if end_t > 0.0 and t > end_t:
		print("TRAILERCAP: done, %d frames" % _n)
		m.get_tree().quit()


var _render_on := true


## Turns drawing of the root viewport and every SubViewport on or off (the render loop switch alone
## does not stop lavapipe from drawing).
func _set_render(on: bool) -> void:
	if on == _render_on:
		return
	_render_on = on
	RenderingServer.viewport_set_active(get_viewport().get_viewport_rid(), on)
	for vp in m.find_children("*", "SubViewport", true, false):
		RenderingServer.viewport_set_active((vp as SubViewport).get_viewport_rid(), on)


func _on_drawn() -> void:
	if not _saving or dir == "":
		return
	var img := get_viewport().get_texture().get_image()
	var name := "cards" if _in_cards else "win"
	for sh in shots:
		if sh["state"] == 1 and not _in_cards:
			name = sh["name"]
	img.save_png("%s/%s_%05d_%07.2f.png" % [dir, name, _n, float(m.run_time)])
	_n += 1


## One line per run second: what is on screen, so the capture run can pick the loudest moments.
func _log(t: float) -> void:
	var near := 0
	var kinds := {}
	var pp: Vector2 = m.player.global_position
	for n in m.get_tree().get_nodes_in_group("enemies"):
		if (n as Node2D).global_position.distance_to(pp) < 900.0:
			near += 1
			var k := String((n.get_script() as Script).get_global_name()) if n.get_script() else "?"
			kinds[k] = int(kinds.get(k, 0)) + 1
	var act := ""
	if m.spawner != null and is_instance_valid(m.spawner.activity_node):
		act = String((m.spawner.activity_node.get_script() as Script).get_global_name())
	var kills: int = m.run.kills
	print("SCAN t=%d lvl=%d near=%d kills+=%d boss=%s act=%s kinds=%s" % [int(t), m.run.level, near, kills - _kills_prev, m.boss_alive(), act, JSON.stringify(kinds)])
	_kills_prev = kills


var _dir_t := 0.0


## Live director: twice a second refreshes the stats and starts the first waiting shot whose
## condition holds (one shot at a time).
func _direct(t: float) -> void:
	if t < _dir_t:
		return
	_dir_t = t + 0.5
	_stats(t)
	for sh in shots:
		if sh["state"] == 1:
			return
	for sh in shots:
		if sh["state"] == 0 and t >= sh["min_t"] and _want(String(sh["name"]), t):
			sh["state"] = 1
			sh["t0"] = t
			_on_shot_start(String(sh["name"]).split("_")[0], t)
			print("TRAILERCAP: shot %s starts at %.1f %s" % [sh["name"], t, JSON.stringify(_st)])
			return


## Condition for each shot name (prefix before "_" so a run can hold several shots of one kind).
func _want(name: String, t: float) -> bool:
	var k: Dictionary = _st.get("kinds", {})
	var g := func(n: String) -> int: return int(k.get(n, 0))
	match name.split("_")[0]:
		"intro", "any":
			return true
		"swarm":
			return int(_st["near"]) >= 40 and int(_st["kills2"]) >= 4
		"aa":
			return String(_st["act"]) == "AASite" and g.call("GroundTarget") >= 3 and int(_st["near"]) >= 15
		"convoy":
			return g.call("ConvoyVehicle") >= 4
		"heli":
			return g.call("Helicopter") >= 1 and g.call("ConvoyVehicle") >= 3
		"ace":
			return float(_st["ace_d"]) < 550.0
		"bombers":
			return g.call("Bomber") >= 2
		"late":
			return int(_st["near"]) >= 50 and int(_st["kills2"]) >= 9
		"fort":
			return bool(_st["fort_up"]) and float(_st["fort_d"]) < 650.0 and int(_st["emsl"]) >= 1
		"fortdown":
			return _fort_done_t >= 0.0 and t > _fort_done_t + 4.0
		"missile":
			return int(_st["emsl"]) >= 2
		"convoyhit":
			return g.call("ConvoyVehicle") >= 3 and int(_st["pord"]) >= 3
		"loop":
			return Main.aces() and float(_st["ace_d"]) < 700.0 and m.player.loop_t <= 0.0
		"boom":
			return int(_st["kills2"]) >= 5
		"flares":
			return int(_st["emsl"]) >= 1 and (m.player.cls_id == "bomber" or Main.aces())
	return false


## A flare salvo is fired by the director at the shot start, so its shot cannot wait the full preroll:
## the missiles would already be lured away by the first saved frame.
func _preroll(name: String) -> float:
	return 0.25 if name.split("_")[0] == "flares" else PREROLL


## What a shot needs from the director when it starts: flares into the missiles, the loop, the move back over
## the ruined fort. Actions land inside the preroll or the recorded window.
func _on_shot_start(kind: String, t: float) -> void:
	match kind:
		"missile":
			if m.player.cls_id == "bomber" or Main.aces():
				_acts.append({"t": t + PREROLL, "kind": "flares_close"})
		"loop":
			_acts.append({"t": t + PREROLL - 0.2, "kind": "loop"})
		"flares":
			_acts.append({"t": t + 0.3, "kind": "flares"})
		"fortdown":
			if _fort_pos != Vector2.INF:
				m.player.global_position = _fort_pos + Vector2(-260, 220)


func _run_acts(t: float) -> void:
	for a in _acts.duplicate():
		if t < float(a["t"]):
			continue
		if String(a["kind"]) == "flares_close" and int(_near_msl(180.0)) == 0 and t < float(a["t"]) + 1.2:
			continue   # wait until a missile is about to hit, so the frame holds both the missile and the flares
		_acts.erase(a)
		if m.player == null or not is_instance_valid(m.player):
			continue
		match String(a["kind"]):
			"flares", "flares_close":
				m.player.skills._flare_salvo(Main.aces())
				print("TRAILERCAP: flares at %.1f" % t)
			"loop":
				m.player.skills._start_loop(false)
				print("TRAILERCAP: loop at %.1f" % t)


func _stats(t: float) -> void:
	var near := 0
	var kinds := {}
	var ace_d := 99999.0
	var pp: Vector2 = m.player.global_position
	for n in m.get_tree().get_nodes_in_group("enemies"):
		var d := (n as Node2D).global_position.distance_to(pp)
		if d < 900.0:
			near += 1
			var k := String((n.get_script() as Script).get_global_name()) if n.get_script() else "?"
			kinds[k] = int(kinds.get(k, 0)) + 1
		if n is Boss or n is RivalAce:
			ace_d = minf(ace_d, d)
	_kill_hist.append([t, int(m.run.kills)])
	while _kill_hist.size() > 1 and t - float(_kill_hist[0][0]) > 2.0:
		_kill_hist.pop_front()
	var act := ""
	if m.spawner != null and is_instance_valid(m.spawner.activity_node):
		act = String((m.spawner.activity_node.get_script() as Script).get_global_name())
	var fort_up := false
	var fort_d := 99999.0
	if m.spawner != null and is_instance_valid(m.spawner.activity_node) and m.spawner.activity_node is FortArea:
		var fa: FortArea = m.spawner.activity_node
		_fort_pos = fa.global_position   # air-space projection of the fort, where the camera looks
		fort_up = fa.active and not fa.done
		fort_d = pp.distance_to(_fort_pos)
		if fa.done and _fort_done_t < 0.0:
			_fort_done_t = t
			print("TRAILERCAP: fort taken at %.1f" % t)
	elif _fort_pos != Vector2.INF and _fort_done_t < 0.0:
		_fort_done_t = t   # the activity freed the node the moment the base was taken
		print("TRAILERCAP: fort left the activity at %.1f" % t)
	var emsl := _near_msl(330.0)
	var pord: int = m.projectiles.rockets.size() + m.projectiles.pmissiles.size() + m.projectiles.bombs.size()
	_st = {"near": near, "fort_up": fort_up, "fort_d": int(fort_d), "emsl": emsl, "pord": pord, "kinds": kinds, "ace_d": int(ace_d), "act": act, "kills2": int(m.run.kills) - int(_kill_hist[0][1]), "lvl": int(m.run.level)}


## Enemy missiles still homing within `r` of the player.
func _near_msl(r: float) -> int:
	var n := 0
	var pp: Vector2 = m.player.global_position
	for ms in m.projectiles.missiles:
		if not bool(ms.get("lost", false)) and (ms["p"] as Vector2).distance_to(pp) < r:
			n += 1
	return n
