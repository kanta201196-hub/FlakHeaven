extends SceneTree
## Review frames of the comic-page cutscenes (ST-12) without playing a sortie: draws every `StoryComic` page with
## `HudComic` at a few scene times and saves `user://comic_<page>_<t>.png`. The `--storyshots --cutshot` replay
## shows the same pages in the real game but takes ~4 min per scene on the cloud's software renderer; this takes
## seconds. Run: `xvfb-run godot --path game --rendering-driver opengl3 --resolution 1920x1080 -s res://tools/comic_shots/comic_shots.gd`
## User args: `--times=a,b,c` (shares of the scene length; negative = seconds before the end; default 0.45 and
## 0.6 s before the end), `--only=<page key>` (one page, e.g. for an animation strip), `--lang=en` (default ru,
## the language Kanta plays in).

var _ctrl: Control
var _hud: HudComic
var _queue: Array = []   # [page key, scene time]
var _cur: Array = []
var _tex := {}
var _wait := 0
var _lang := "ru"   # set on every frame: the Settings autoload applies the saved language after _initialize


func _initialize() -> void:
	_ctrl = Control.new()
	_ctrl.size = Vector2(1920, 1080)
	root.add_child(_ctrl)
	_ctrl.draw.connect(_on_draw)
	_hud = HudComic.new(_ctrl, [])
	var shares := [0.45, -0.6]
	var only := ""
	_lang = "ru"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--times="):
			shares = Array(a.substr(8).split(",")).map(func(x): return float(x))
		elif a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--lang="):
			_lang = a.substr(7)
	for key in StoryComic.PAGES:
		if only != "" and key != only:
			continue
		var dur := float(StoryComic.scene_of(key).get("dur", 1.0))
		for s in shares:
			_queue.append([key, dur + float(s) if float(s) < 0.0 else dur * float(s)])


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var img := root.get_texture().get_image()
			img.save_png("user://comic_%s_%05.2f.png" % [String(_cur[0]).replace(".", "_"), float(_cur[1])])
		return false
	if _queue.is_empty():
		print("COMIC SHOTS done")
		return true
	TranslationServer.set_locale(_lang)
	_cur = _queue.pop_front()
	_tex = {}
	for path in StoryComic.images(_cur[0]):
		_tex[path] = load(path)
	_ctrl.size = root.size
	_ctrl.queue_redraw()
	_wait = 3
	return false


func _on_draw() -> void:
	if _cur.is_empty():
		return
	_hud.draw(_ctrl.size, _cur[0], float(_cur[1]), StoryComic.scene_of(_cur[0]), _tex)
