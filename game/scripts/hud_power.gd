class_name HudPower
extends RefCounted
## «Момент силы» (PG-13): opening a synergy, an archetype rank III or a modernization is shown as an event —
## a short colour flash over the screen, the name large in the upper centre, a layered sound and rings
## pulsing around the plane for the first seconds. Presentation only: it changes no numbers.
## `Hud` owns one instance, feeds it from `Events.power_moment`, ticks it and `HudFlight.draw_post` draws it.
## Moments wait in a queue (one card can open a synergy and a rank III together) and their clock runs only
## in flight, so a moment opened on the card screen plays when the player is back in the air.
## F1 `power_moment` = 0 — the old one-line banner at the top instead (`HudPower.on`).

## Seconds one moment stays on screen (real time); the last FADE of them it fades out.
const SHOW := 2.6
const FADE := 0.45
## Screen flash: seconds and peak opacity.
const FLASH := 0.35
const FLASH_A := 0.32
## Title «punch»: starts this much larger and settles in PUNCH seconds.
const PUNCH_K := 0.35
const PUNCH := 0.2
## Rings around the plane: how many, seconds apart, radius in world px.
const PULSES := 4
const PULSE_GAP := 0.45
const PULSE_R := 240.0
## Queue cap: a burst of unlocks never keeps the screen busy for long.
const QUEUE_MAX := 3

## Kicker line above the title per kind (translated at draw time).
const KICKER := {
	&"synergy": "НОВАЯ СВЯЗКА · СЛОТ %d",
	&"arch": "АРХЕТИП · РАНГ III",
	&"evo": "МОДЕРНИЗАЦИЯ",
}

## Print a POWER line per moment (autotest log), set by `Hud`.
var log_lines := false
var _queue: Array[Moment] = []
var _cur: Moment
var _age := 0.0
var _pulses_done := 0


## True when unlocks play as a moment; false — the s16 top banner (F1 `power_moment`, R-22: on by default).
static func on() -> bool:
	return Tuning.g("power_moment") >= 0.5


## Queues a moment (from `Events.power_moment`). `slot` is used by synergies only.
func push(kind: StringName, title: String, line: String, color: Color, slot: int) -> void:
	if _queue.size() >= QUEUE_MAX:
		return
	var mo := Moment.new()
	mo.kind = kind
	mo.title = title
	mo.line = line
	mo.color = color
	mo.slot = slot
	_queue.append(mo)


## Drops everything (new sortie).
func clear() -> void:
	_queue.clear()
	_cur = null


## Seconds the current moment has been on screen, -1 with none (debug frames).
func age() -> float:
	return _age if _cur != null else -1.0


## Kind of the moment on screen (&"" with none; debug frames).
func kind() -> StringName:
	return _cur.kind if _cur != null else &""


## Advances the current moment by `real` seconds of real time; only while `flying` (state «playing»),
## so the flash and sound come when the fight is visible. Starts the next queued moment, plays its sound
## and sends the rings around the plane.
func tick(real: float, flying: bool) -> void:
	if not flying:
		return
	if _cur == null:
		if _queue.is_empty():
			return
		_cur = _queue.pop_front()
		_age = 0.0
		_pulses_done = 0
		_start_sound()
		if log_lines:
			print("POWER %s: %s" % [_cur.kind, _cur.title])
	else:
		_age += real
	var m := Main.I
	while _pulses_done < PULSES and _age >= _pulses_done * PULSE_GAP:
		if m != null and is_instance_valid(m.player):
			# each ring a little wider, so they read as a wave leaving the plane
			m.fx.ring(m.player.global_position, PULSE_R * (1.0 + 0.25 * _pulses_done), _cur.color)
		_pulses_done += 1
	if _age >= SHOW:
		_cur = null


## Draws the flash and the title plate on `ci` (the flight HUD's top layer).
func draw(ci: CanvasItem, size: Vector2) -> void:
	if _cur == null:
		return
	var c := _cur.color
	if _age < FLASH:
		var fa := FLASH_A * (1.0 - _age / FLASH)
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color(c.r, c.g, c.b, fa))
	var a := clampf((SHOW - _age) / FADE, 0.0, 1.0) * clampf(_age / 0.08, 0.0, 1.0)
	var grow := clampf(_age / PUNCH, 0.0, 1.0)
	var k := 1.0 + PUNCH_K * (1.0 - grow) * (1.0 - grow)
	var cy := size.y * 0.27
	# plate: a dark band whose coloured edges open from the centre
	var pw := minf(size.x - 40.0, 900.0)
	var open := ease(clampf(_age / 0.3, 0.0, 1.0), 0.4)
	# a long effect line wraps (synergy texts run to ~110 characters); the band grows to hold it
	var lf := UiStyle.head_font(600, 1)
	var line := Loc.out(_cur.line)
	var lh := 0.0
	if line != "":
		lh = lf.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, pw - 40.0, UiStyle.FS_BODY).y
	var band := Rect2((size.x - pw) / 2.0, cy - 66.0, pw, 108.0 + lh)
	ci.draw_rect(band, Color(0.02, 0.025, 0.03, 0.62 * a))
	var lw := pw * open
	var lx := (size.x - lw) / 2.0
	ci.draw_rect(Rect2(lx, band.position.y, lw, 2.5), Color(c.r, c.g, c.b, 0.9 * a))
	ci.draw_rect(Rect2(lx, band.end.y - 2.5, lw, 2.5), Color(c.r, c.g, c.b, 0.9 * a))
	var kick := Loc.t(String(KICKER.get(_cur.kind, "")))
	if _cur.kind == &"synergy":
		kick = kick % _cur.slot
	var kf := UiStyle.head_font(700, 3)
	UiStyle.text(ci, kf, Vector2(0, cy - 34.0), kick, UiStyle.FS_LABEL, Color(c.r, c.g, c.b, a),
		HORIZONTAL_ALIGNMENT_CENTER, size.x)
	# title: hero size, shrunk to fit the band, with a coloured glow behind it
	var tf := UiStyle.head_font(800, 2)
	var fs := float(UiStyle.FS_HERO)
	var tw := UiStyle.text_w(tf, _cur.title, UiStyle.FS_HERO)
	if tw > pw - 40.0:
		fs *= (pw - 40.0) / tw
	var ts := maxi(int(fs * k), UiStyle.FS_H2)
	var ty := cy + 18.0 + (ts - fs) * 0.3
	var glow := Color(c.r, c.g, c.b, 0.35 * a)
	for off: Vector2 in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		UiStyle.text(ci, tf, Vector2(off.x, ty + off.y), _cur.title, ts, glow, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	UiStyle.text(ci, tf, Vector2(0, ty), _cur.title, ts, Color(UiStyle.TEXT_WARM, a),
		HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if line != "":
		ci.draw_multiline_string(lf, Vector2(band.position.x + 20.0, cy + 50.0), line, HORIZONTAL_ALIGNMENT_CENTER,
			pw - 40.0, UiStyle.FS_BODY, -1, Color(UiStyle.TEXT_WARM, 0.85 * a))


## Two existing sounds together: the synergy sting at full pitch and a low level-up under it.
func _start_sound() -> void:
	var m := Main.I
	if m == null:
		return
	m.sfx.play("synergy", -3.0, 1.0)
	m.sfx.play("levelup", -9.0, 0.75)


## One queued moment: what opened, its player-facing title and line (already translated), colour,
## and `slot` — the synergy slot number for the kicker.
class Moment:
	extends RefCounted
	var kind: StringName
	var title: String
	var line: String
	var color: Color
	var slot: int
