extends Node
## Trailer capture (marketing tool, `-- --trailercap`): plays a bot sortie with fixed frame time and
## saves PNG frames only inside chosen run-time windows. Outside the windows the render loop is off,
## so the GPU-less cloud (lavapipe, ~3 s per Forward+ frame) only pays for the frames it keeps.
## Args: --capscale=F (window content scale: --resolution=1080x1920 with 1.7778 gives the same zoom as a
## 1920x1920 render cropped to 1080 wide, at 56% of the pixels), --capdir=DIR, --capwin=A-B,C-D (run seconds), --capscan (log action per second, no frames),
## --capseed=N, --capend=S (quit after this run second).
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
	scan = OS.get_cmdline_user_args().has("--capscan")
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.frame_post_draw.connect(_on_drawn)


func _process(_d: float) -> void:
	if m.hud != null:
		m.hud.visible = m.state != "playing"
	var t: float = m.run_time
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
				_saving = t >= sh["t0"] + PREROLL
				if t > sh["t0"] + PREROLL + sh["len"]:
					sh["state"] = 2
					print("TRAILERCAP: shot %s done at %.1f" % [sh["name"], t])
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
	var name := "win"
	for sh in shots:
		if sh["state"] == 1:
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
			print("TRAILERCAP: shot %s starts at %.1f %s" % [sh["name"], t, JSON.stringify(_st)])
			return


## Condition for each shot name (prefix before "_" so a run can hold several shots of one kind).
func _want(name: String, _t: float) -> bool:
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
	return false


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
	_st = {"near": near, "kinds": kinds, "ace_d": int(ace_d), "act": act, "kills2": int(m.run.kills) - int(_kill_hist[0][1]), "lvl": int(m.run.level)}
