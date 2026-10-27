class_name DecalEditInput
extends RefCounted
## Input of the hangar decal editor (spec 2026-10-27-plane-decals-design.md §6): opens and closes it, turns
## mouse, keys and the gamepad into DecalEditor calls, and keeps the profile and the 3D view in step with it.
## The rules themselves (what a click places, what the cap refuses) live in DecalEditor; the panel is HudDecals.
##
## The gamepad is read raw (buttons and axes of the first pad), not through the combat actions: those carry
## keyboard and mouse binds too (the left button fires), which would act twice in the editor.
## Every change goes to the profile at once (Profile.set_decals); the file is written when the editor closes.

const CURSOR_SPEED := 900.0   ## gamepad cursor, px per second at full tilt
const CURSOR_SLOW := 0.45     ## over the plane the cursor slows down, so it can be put on a small spot
const DEADZONE := 0.2
const CAM_SPEED := 2.2        ## right stick, radians per second
const REPEAT := 0.12          ## held trigger: one scale step this often
const HOLD_FINE := 0.35       ## a bumper held this long turns in fine steps
const FINE_EVERY := 0.05
const DRAG_PX := 4.0          ## a press that moves less than this only selects the decal
const NOTE_TIME := 3.0

var m: Main
var note := ""                ## why the last action did nothing (shown in the panel)
var note_t := 0.0
var tally := 0                ## the class's real kill tally (read when the editor opens)
var _dirty := false           ## the profile holds decal changes the file does not have yet
var _press_at := Vector2.ZERO
var _press_grab := false
var _was := {}                ## gamepad button / key → down last frame
var _held := {}               ## gamepad button → seconds held
var _hit: Array = []          ## the skin under the cursor this frame


func _init(main: Main) -> void:
	m = main


## True while the editor is open
func is_open() -> bool:
	return m.decal_edit != null


## Opens the editor on the plane on view in the hangar
func open() -> void:
	var h3 := Hangar3D.I
	if h3 == null or m.decal_edit != null:
		return
	var key := h3.model_key()
	var cls := key.get_slice("_", 0)
	var lvl := int(key.get_slice("_", 1))
	if cls != m.hangar_cls or lvl != h3.view_lvl:
		return
	var e := DecalEditor.new()
	e.open(cls, lvl, Profile.decals(cls, lvl))
	m.decal_edit = e
	tally = Profile.decal_tally(cls)
	note = ""
	h3.decal_mode = true
	h3.decal_cursor = h3.rect.get_center()
	if not h3.decal_press.is_connected(_on_press):
		h3.decal_press.connect(_on_press)
		h3.decal_wheel.connect(_on_wheel)
	HudDecals.focus = -1


## Closes the editor: the decals stay in the profile, the profile file is written, the plane shows the real tally
func close() -> void:
	var e := m.decal_edit
	if e == null:
		return
	m.decal_edit = null
	_store(e)
	if _dirty:
		Profile.save()
		_dirty = false
	var h3 := Hangar3D.I
	if h3 != null:
		h3.decal_close("%s_%d" % [e.cls, e.lvl], Profile.decals(e.cls, e.lvl), tally)
	HudDecals.focus = -1


## Esc / B: drops the move, the tool or the selection first; with nothing to drop, leaves the editor
func back() -> void:
	if m.decal_edit != null and not m.decal_edit.cancel():
		close()


func _store(e: DecalEditor) -> void:
	if e.changed:
		Profile.set_decals(e.cls, e.lvl, e.records)
		e.changed = false
		_dirty = true


## Shows why an action did nothing; `buzz` — also the refusal sound (panel buttons get theirs from MainInput)
func _say(s: String, buzz := false) -> void:
	note = s
	note_t = NOTE_TIME
	if buzz:
		m.sfx.play("ui_ban", -10.0, 0.8)


## Per frame while the hangar is open: closes the editor when its plane is no longer on view, reads keys and the
## gamepad, and draws the decal under the cursor
func frame(delta: float) -> void:
	var e := m.decal_edit
	if e == null:
		return
	var h3 := Hangar3D.I
	if h3 == null or m.hangar_tab != "plane" or m.hangar_cls != e.cls or h3.view_lvl != e.lvl \
			or h3.model_key() != "%s_%d" % [e.cls, e.lvl]:
		close()
		return
	note_t = maxf(0.0, note_t - delta)
	_keys()
	_pad(h3, delta)
	if m.decal_edit == null:   # B closed it
		return
	_hit = h3.decal_ray(h3.decal_cursor) if (h3.decal_pad or HudDecals.focus < 0) else []
	var live := e.preview(_hit)
	if live == null and e.sel >= 0 and not e.moving:
		live = e.records[e.sel]   # the selected decal pulses
	_store(e)
	h3.decal_refresh(e.shown(), live, maxi(tally, DecalEditor.PREVIEW_TALLY))


## Edge of a key or pad button: true on the frame it goes down
func _edge(id: String, down: bool) -> bool:
	var was: bool = _was.get(id, false)
	_was[id] = down
	return down and not was


func _keys() -> void:
	var e := m.decal_edit
	var fine := Input.is_key_pressed(KEY_SHIFT)
	if _edge("q", Input.is_key_pressed(KEY_Q)):
		e.rotate_by(1, fine)
	if _edge("e", Input.is_key_pressed(KEY_E)):
		e.rotate_by(-1, fine)
	if _edge("f", Input.is_key_pressed(KEY_F)):
		e.toggle_mirror()
	if _edge("del", Input.is_key_pressed(KEY_DELETE)):
		e.remove()


func _pad(h3: Hangar3D, delta: float) -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return
	var dev := pads[0]
	var e := m.decal_edit
	var v := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
	if v.length() > DEADZONE:
		var k := (minf(v.length(), 1.0) - DEADZONE) / (1.0 - DEADZONE)
		var speed := CURSOR_SPEED * (CURSOR_SLOW if not _hit.is_empty() else 1.0)
		if not h3.decal_pad:
			h3.decal_cursor = h3.rect.get_center() if not h3.rect.has_point(h3.decal_cursor) else h3.decal_cursor
		h3.decal_cursor = (h3.decal_cursor + v.normalized() * k * speed * delta).clamp(h3.rect.position, h3.rect.end - Vector2.ONE)
		h3.decal_pad = true
		HudDecals.focus = -1
	var r := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
	if r.length() > DEADZONE:
		h3.orbit(r.x * CAM_SPEED * delta, r.y * CAM_SPEED * 0.75 * delta)
	for d: Array in [[JOY_BUTTON_DPAD_UP, Vector2i.UP], [JOY_BUTTON_DPAD_DOWN, Vector2i.DOWN],
			[JOY_BUTTON_DPAD_LEFT, Vector2i.LEFT], [JOY_BUTTON_DPAD_RIGHT, Vector2i.RIGHT]]:
		if _edge("pad%d" % int(d[0]), Input.is_joy_button_pressed(dev, int(d[0]))):
			HudDecals.move_focus(d[1])
	if _edge("padA", Input.is_joy_button_pressed(dev, JOY_BUTTON_A)):
		if HudDecals.focus >= 0:
			var a := HudDecals.focused_action()
			if a != "":
				m.ui_click(a)
		else:
			_pad_a(h3)
	if _edge("padB", Input.is_joy_button_pressed(dev, JOY_BUTTON_B)):
		back()
		return
	if _edge("padX", Input.is_joy_button_pressed(dev, JOY_BUTTON_X)):
		e.toggle_mirror()
	if _edge("padY", Input.is_joy_button_pressed(dev, JOY_BUTTON_Y)):
		e.next_paint(1)
	for b: Array in [[JOY_BUTTON_LEFT_SHOULDER, 1], [JOY_BUTTON_RIGHT_SHOULDER, -1]]:
		var id := "padS%d" % int(b[0])
		var down := Input.is_joy_button_pressed(dev, int(b[0]))
		if _edge(id, down):
			e.rotate_by(int(b[1]))
			_held[id] = 0.0
		elif down:
			_held[id] = float(_held.get(id, 0.0)) + delta
			if float(_held[id]) > HOLD_FINE + FINE_EVERY:
				_held[id] = HOLD_FINE
				e.rotate_by(int(b[1]), true)
	for t: Array in [[JOY_AXIS_TRIGGER_LEFT, -1], [JOY_AXIS_TRIGGER_RIGHT, 1]]:
		var id := "padT%d" % int(t[0])
		var down := Input.get_joy_axis(dev, int(t[0])) > 0.5
		if _edge(id, down):
			e.scale_by(int(t[1]))
			_held[id] = 0.0
		elif down:
			_held[id] = float(_held.get(id, 0.0)) + delta
			if float(_held[id]) > REPEAT * 2.0:
				_held[id] = REPEAT
				e.scale_by(int(t[1]))


## Gamepad A over the view: put the moving decal down, stamp the tool, or pick up the decal under the cursor
func _pad_a(h3: Hangar3D) -> void:
	var e := m.decal_edit
	var hit := h3.decal_ray(h3.decal_cursor)
	if e.moving:
		if not e.drop(hit):
			_say(Loc.t("Наведите на самолёт"), true)
		return
	if e.tool != "":
		if not e.place(hit):
			_say(Loc.t("Наведите на самолёт") if hit.is_empty() else Loc.t("Не больше %d знаков на самолёт") % DecalLoadout.MAX_DECALS, true)
		return
	if not hit.is_empty() and e.select_at(hit[0]) >= 0:
		e.grab()


## Left button over the view: like A, but a press on a decal and a drag moves it (a click without a drag only
## selects it)
func _on_press(p: Vector2, pressed: bool) -> void:
	var e := m.decal_edit
	var h3 := Hangar3D.I
	if e == null or h3 == null:
		return
	HudDecals.focus = -1
	var hit := h3.decal_ray(p)
	if pressed:
		_press_at = p
		_press_grab = false
		if e.moving or e.tool != "":
			_pad_a(h3)
			return
		if hit.is_empty():
			return
		if e.select_at(hit[0]) >= 0:
			e.grab()
			_press_grab = true
		return
	if not _press_grab or not e.moving:
		return
	_press_grab = false
	if p.distance_to(_press_at) < DRAG_PX or not e.drop(hit):
		e.moving = false   # a click only selects; released off the plane, the decal stays where it was


## Wheel over the view: scales the selected decal or the tool, else zooms the camera
func _on_wheel(steps: int) -> void:
	var e := m.decal_edit
	if e == null:
		return
	if e.sel >= 0 or e.tool != "":
		e.scale_by(steps)
	elif Hangar3D.I != null:
		Hangar3D.I.zoom(steps)


## A panel button `hg:dc:...` (split at «:», without «hg»); false when it did nothing
func action(p: PackedStringArray) -> bool:
	if p.size() < 2:
		return false
	if p[1] == "open":
		open()
		return m.decal_edit != null
	var e := m.decal_edit
	if e == null:
		return false
	var h3 := Hangar3D.I
	var hull := h3.decal_hull() if h3 != null else null
	match p[1]:
		"close":
			close()
		"pic":
			var why := e.pick(p[2], Profile.decal_open(p[2], e.cls))
			if why == "locked":
				_say(Loc.t("Этот знак ещё закрыт: %s") % HudDecals.need_text(p[2], e.cls))
			elif why == "cap":
				_say(Loc.t("Не больше %d знаков на самолёт") % DecalLoadout.MAX_DECALS)
			return why == ""
		"sel":
			e.tool = ""
			e.moving = false
			e.sel = clampi(int(p[2]), -1, e.records.size() - 1)
		"up", "down":
			e.sel = clampi(int(p[2]), 0, e.records.size() - 1)
			e.order(-1 if p[1] == "up" else 1)
		"del":
			e.sel = clampi(int(p[2]), 0, e.records.size() - 1)
			e.remove()
		"preset":
			if e.tool == "":
				_say(Loc.t("Сначала выберите картинку"))
				return false
			if hull == null or not e.preset(hull, h3.model_key(), p[2], int(p[3])):
				_say(Loc.t("Не больше %d знаков на самолёт") % DecalLoadout.MAX_DECALS if e.records.size() >= DecalLoadout.MAX_DECALS else Loc.t("Сюда этот самолёт знак не берёт"))
				return false
		"c1":
			e.set_paint(1, p[2])
		"c2":
			e.set_paint(2, p[2])
		"digit":
			e.set_text(_digit(_text_now(e), int(p[2]), int(p[3])))
		"digits":
			var t := _text_now(e)
			e.set_text(t + "0" if int(p[2]) > 0 else t.substr(0, t.length() - 1))
		"rot":
			e.rotate_by(int(p[2]))
		"size":
			e.scale_by(int(p[2]))
		"mirror":
			e.toggle_mirror()
		"other":
			if hull == null or not e.other_side(hull):
				_say(Loc.t("Не больше %d знаков на самолёт") % DecalLoadout.MAX_DECALS if e.records.size() >= DecalLoadout.MAX_DECALS else Loc.t("Сначала выберите знак на самолёте"))
				return false
		"remove":
			if e.sel < 0:
				return false
			e.remove()
	_store(e)
	return true


## Digits being edited: the selected number's, else the tool's
static func _text_now(e: DecalEditor) -> String:
	if e.sel >= 0 and DecalCatalog.kind(e.records[e.sel].id) == "number":
		return e.records[e.sel].text
	return e.text


## `s` with digit `i` stepped by `d` (9 wraps to 0)
static func _digit(s: String, i: int, d: int) -> String:
	if i < 0 or i >= s.length():
		return s
	return s.substr(0, i) + str(wrapi(int(s[i]) + d, 0, 10)) + s.substr(i + 1)
