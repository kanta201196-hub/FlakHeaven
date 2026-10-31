class_name HudDialog
extends HudKit
## Picture of a hangar dialogue scene (`Dialog`): the 3D hangar view behind a dark scrim, the crew member's portrait
## left and the guest's right (the one talking is bright), a name plate with the trait title when the line is
## «in character», the typed line or the choice buttons, and the key hints. Portraits without a picture yet show a
## plate with the callsign and a silhouette, so the scenes ship before the art (ST-08). Drawn in code (ADR-05).

const PANEL_W := 1120.0
const PANEL_H := 236.0
const PORTRAIT := Vector2(230.0, 345.0)   # art is 256×384 (2:3)
const C_GUEST := Color(0.62, 0.84, 1.0)
const C_CREW := UiStyle.ACCENT_SOFT

var _portraits := {}   # guest → Texture2D or null


func draw(m: Main, size: Vector2) -> void:
	var full := Rect2(Vector2.ZERO, size)
	var h3 := Hangar3D.ensure(ctrl)
	ctrl.draw_texture_rect(h3.show_plane(m.cls_id, full), full, false)
	ctrl.draw_rect(full, Color(0.02, 0.03, 0.025, 0.42))
	_buttons.append([full, "dlg:next"])   # a click anywhere advances; the buttons below sit on top (CR-01 order)
	var s := Dialog.current()
	if s.is_empty():
		return
	var who := String(s.get("who", ""))
	var crew_talks := who == "crew"
	var guest := Dialog.last_guest if (crew_talks or who == "") else who
	var pr := Rect2((size.x - PANEL_W) * 0.5, size.y - PANEL_H - 56.0, PANEL_W, PANEL_H)
	_panel(pr, false, UiStyle.ACCENT_DIM)
	# portraits stand on the panel's bottom edge, at its two ends
	var lp := Rect2(pr.position.x + 18.0, pr.end.y - PORTRAIT.y - 14.0, PORTRAIT.x, PORTRAIT.y)
	var rp := Rect2(pr.end.x - 18.0 - PORTRAIT.x, lp.position.y, PORTRAIT.x, PORTRAIT.y)
	var callsign := String(Profile.cls(m.cls_id)["callsign"])
	_portrait(lp, Profile.portrait(m.cls_id), callsign, C_CREW, crew_talks or s.has("choice"))
	_portrait(rp, _guest_tex(guest), guest, C_GUEST, not crew_talks and not s.has("choice"))
	var x := lp.end.x + 28.0
	var w := rp.position.x - 28.0 - x
	var y := pr.position.y + 44.0
	if s.has("choice"):
		_text(Vector2(x, y), String(s.get("prompt", "")), 20, UiStyle.TEXT_2)
		var opts: Array = s.get("options", [])
		var oy := y + 24.0
		for k in opts.size():
			var r := Rect2(x, oy, w, 44.0)
			var on := k == Dialog.focus
			_panel(r, on or r.has_point(ctrl.get_local_mouse_position()))
			_text(Vector2(r.position.x + 18.0, r.position.y + 30.0), "%d · %s" % [k + 1, Loc.t(String((opts[k] as Array)[0]))], 19, Color.WHITE if on else UiStyle.TEXT)
			_buttons.append([r, "dlg:opt:%d" % k])
			oy += 52.0
		_text(Vector2(rp.position.x - 28.0 - 760.0, pr.position.y + 24.0), "↑ ↓ — выбор · Enter — подтвердить · Esc — пропустить сцену", 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 760.0)
		return
	# name plate: «Шмель» · Торопыга on a trait line, else the plain name
	var name := callsign if crew_talks else who
	var plate := "«%s»" % Loc.t(name)
	if crew_talks and bool(s.get("trait", false)):
		var tr := Profile.trait_of(m.cls_id)
		if tr.has("title"):
			plate += " · " + Loc.t(String(tr["title"]))
	_text(Vector2(x, y), plate, 20, C_CREW if crew_talks else C_GUEST)
	_para(Vector2(x, y + 36.0), DialogFlow.shown(Loc.t(String(s.get("text", ""))), Dialog.t), w, 22, UiStyle.TEXT)
	_text(Vector2(rp.position.x - 28.0 - 760.0, pr.position.y + 24.0), "Enter — дальше · Esc — пропустить сцену", 14, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 760.0)
	var fade := clampf(1.0 - Dialog.total / Dialog.FADE, 0.0, 1.0)
	if fade > 0.0:
		ctrl.draw_rect(full, Color(0, 0, 0, fade))


## A portrait in `r`: the picture, or a plate with a silhouette and the name when there is none; dimmed when the
## other side talks.
func _portrait(r: Rect2, tex: Texture2D, name: String, accent: Color, lit: bool) -> void:
	var a := 1.0 if lit else 0.55
	ctrl.draw_rect(r, Color(0.03, 0.035, 0.04, 0.9))
	if tex != null:
		ctrl.draw_texture_rect(tex, r, false, Color(a, a, a, 1.0))
	else:
		var c := Color(0.35, 0.37, 0.42) * a
		ctrl.draw_circle(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.36), r.size.x * 0.2, c)
		ctrl.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.2, r.size.y * 0.62), Vector2(r.size.x * 0.6, r.size.y * 0.38)), c)
		_text(Vector2(r.position.x, r.end.y - 22.0), "«%s»" % Loc.t(name), 18, Color(accent, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	ctrl.draw_rect(r, Color(accent, a), false, 2.0 if lit else 1.5)


## Portrait of a guest from `DialogFlow.portrait_file`, cached; null until the picture exists.
func _guest_tex(who: String) -> Texture2D:
	if not _portraits.has(who):
		var path := DialogFlow.portrait_file(who)
		_portraits[who] = load(path) if path != "" and ResourceLoader.exists(path) else null
	return _portraits[who]
